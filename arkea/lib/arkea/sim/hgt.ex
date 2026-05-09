defmodule Arkea.Sim.HGT do
  @moduledoc """
  Pure horizontal gene transfer (HGT) logic for Phase 6 (01-DESIGN.md Block 5).

  Implements two HGT mechanisms:

  1. **Conjugation** — plasmid transfer between lineages in the same phase via
     pilus-like structures (proxied by `:transmembrane_anchor` domain count).
     The `step/4` function runs this logic for one phase per call.

  2. **Prophage induction** — stress-triggered lytic burst that reduces the
     abundance of lineages carrying integrated prophages. The `induction_step/4`
     function applies this loss.

  ## Discipline

  This module is **strictly pure**: no I/O, no OTP calls, no PubSub, no DB.
  All stochasticity is driven by the `:rand` state passed as an argument;
  callers must persist the returned state.

  ## Conjugation model

  For each ordered donor-recipient pair sharing a phase:

      strength = conjugation_strength(donor_plasmid)
      bias     = intergenic_transfer_bias(donor_genome, recipient_genome, donor_plasmid)
      n_donor  = Lineage.abundance_in(donor, phase_name)
      n_recip  = Lineage.abundance_in(recipient, phase_name)
      n_total  = total abundance of all lineages in this phase
      p_conj   = clamp(strength × bias × 0.005 × n_donor × n_recip / max(n_total², 1), 0.0, 0.3)

  When the RNG roll falls below `p_conj`, a new child lineage of the recipient
  is created carrying the donor's plasmid. Abundance is conserved: the
  recipient loses 1 unit in the phase.

  ## Prophage induction model

      stress_factor = max(0.0, 1.0 - atp_yield / max(energy_cost × 5.0, 0.1))
      p_induction   = clamp(0.03 × stress_factor, 0.0, 0.1) per prophage cassette

  On induction: the lineage loses `floor(abundance × 0.5)` units (lytic burst).
  """

  @behaviour Arkea.Sim.HGT.Channel

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Gene
  alias Arkea.Sim.HGT.Phage
  alias Arkea.Sim.Intergenic
  alias Arkea.Sim.Mutator
  alias Arkea.Sim.Phenotype

  @conj_base_rate 0.005
  @p_conj_max 0.3
  @p_induction_max 0.1
  @p_induction_base 0.03

  # ---------------------------------------------------------------------------
  # Public API

  @doc """
  Channel identifier — required by `Arkea.Sim.HGT.Channel`. Conjugation
  is the legacy Phase-6 channel; this name is what audit-log writers and
  per-channel tests expect to see in event maps.
  """
  @impl Arkea.Sim.HGT.Channel
  @spec name() :: :conjugation
  def name, do: :conjugation

  @doc """
  True if the plasmid is *self-conjugative* — it carries the full
  conjugation triad on its own genes (Phase 28 / 28.1 — closes
  L1.5).

  The triad (01-DESIGN.md Block 5, biology per Smillie et al. 2010):

    * **`pili_like`** — sex pilus apparatus. Proxied by
      `:transmembrane_anchor` domain count on plasmid genes. Builds
      the mating channel through which the relaxed strand crosses
      into the recipient.
    * **`relaxase_like`** — DNA-processing endonuclease that nicks
      one strand at *oriT* and chaperones it through the channel.
      Proxied by a plasmid gene that co-encodes `:dna_binding`
      (sequence-specific recognition of *oriT*) plus
      `:catalytic_site` with `reaction_class :hydrolysis` (the
      strand-cleaving activity).
    * **`oriT_like`** — origin of transfer DNA element where
      relaxase nicks. Already exposed via the
      `Genome.plasmid().oriT_present` boolean derived from the
      `orit_site` intergenic block (Phase 16).

  Plasmids with all three are self-conjugative. Plasmids with
  relaxase + oriT but lacking pili are *mobilizable* — they can
  conjugate only when a *helper plasmid* in the same donor cell
  supplies the pilus (see `mobilizable?/1` and `helper_plasmid/2`).
  This matches the canonical bacterial taxonomy of conjugative
  plasmids (e.g. R388 = self-conjugative; ColE1-type = mobilizable
  by an IncF/IncP helper).

  Accepts either a `Genome.plasmid()` map or a raw gene list (legacy
  callers without inc/oriT metadata fall back to a "no oriT known"
  assumption, never self-conjugative).
  """
  @spec self_conjugative?(Genome.plasmid() | [Gene.t()]) :: boolean()
  def self_conjugative?(plasmid) when is_map(plasmid) do
    pili_strength(plasmid) > 0 and
      relaxase_strength(plasmid) > 0 and
      Map.get(plasmid, :oriT_present, false)
  end

  def self_conjugative?(genes) when is_list(genes) do
    pili_strength(genes) > 0 and
      relaxase_strength(genes) > 0 and
      raw_genes_have_orit?(genes)
  end

  @doc """
  True if the plasmid is *mobilizable* — it carries `relaxase_like` +
  `oriT_like` but **lacks** `pili_like`. Mobilizable plasmids cannot
  initiate conjugation on their own; they require a co-resident
  helper plasmid (see `helper_plasmid/2`) to supply the pilus
  apparatus.

  A plasmid that is `self_conjugative?/1` is *not* `mobilizable?/1` —
  the two predicates are mutually exclusive.
  """
  @spec mobilizable?(Genome.plasmid() | [Gene.t()]) :: boolean()
  def mobilizable?(plasmid) when is_map(plasmid) do
    pili_strength(plasmid) == 0 and
      relaxase_strength(plasmid) > 0 and
      Map.get(plasmid, :oriT_present, false)
  end

  def mobilizable?(genes) when is_list(genes) do
    pili_strength(genes) == 0 and
      relaxase_strength(genes) > 0 and
      raw_genes_have_orit?(genes)
  end

  @doc """
  Backward-compatible alias for `self_conjugative?/1`. Pre-Phase-28
  callers asked "is this plasmid conjugative?" with the implicit
  meaning "*can it conjugate on its own*" — which now maps cleanly
  to the self-conjugative predicate. Mobilizable plasmids are
  surfaced separately via `mobilizable?/1`.
  """
  @spec conjugative?(Genome.plasmid() | [Gene.t()]) :: boolean()
  def conjugative?(plasmid), do: self_conjugative?(plasmid)

  @doc """
  Pilus strength of a plasmid: total count of `:transmembrane_anchor`
  domains across the plasmid's genes. Zero ⇒ no pilus apparatus
  encoded; the plasmid cannot self-conjugate but may still be
  mobilizable.

  Accepts either a `Genome.plasmid()` map or a raw gene list.
  """
  @spec pili_strength(Genome.plasmid() | [Gene.t()]) :: non_neg_integer()
  def pili_strength(%{genes: genes}) when is_list(genes), do: pili_strength(genes)

  def pili_strength(plasmid_genes) when is_list(plasmid_genes) do
    Enum.sum_by(plasmid_genes, fn gene ->
      Enum.count(gene.domains, fn domain -> domain.type == :transmembrane_anchor end)
    end)
  end

  @doc """
  Relaxase strength of a plasmid: count of plasmid genes that
  *co-encode* the relaxase signature — at least one `:dna_binding`
  domain (sequence-specific *oriT* recognition) AND at least one
  `:catalytic_site` with `reaction_class: :hydrolysis` (the nicking
  activity).

  Pure structural detection — the same gene must carry both
  signatures to count as a relaxase. Two adjacent genes encoding
  the activities separately do *not* count, matching the in vivo
  picture where relaxase is a single multifunctional protein
  (e.g. TrwC in R388, MobA in RP4).
  """
  @spec relaxase_strength(Genome.plasmid() | [Gene.t()]) :: non_neg_integer()
  def relaxase_strength(%{genes: genes}) when is_list(genes), do: relaxase_strength(genes)

  def relaxase_strength(plasmid_genes) when is_list(plasmid_genes) do
    Enum.count(plasmid_genes, &relaxase_gene?/1)
  end

  defp relaxase_gene?(%Gene{domains: domains}) do
    has_dna_binding = Enum.any?(domains, fn d -> d.type == :dna_binding end)

    has_hydrolytic =
      Enum.any?(domains, fn d ->
        d.type == :catalytic_site and Map.get(d.params, :reaction_class) == :hydrolysis
      end)

    has_dna_binding and has_hydrolytic
  end

  @doc """
  Conjugation strength legacy accessor — returns the *pilus* strength
  for backward compatibility with pre-Phase-28 callers. The triad-
  aware `pili_strength/1`, `relaxase_strength/1`, and
  `Map.get(plasmid, :oriT_present, false)` accessors are the
  preferred APIs.
  """
  @spec conjugation_strength(Genome.plasmid() | [Gene.t()]) :: non_neg_integer()
  def conjugation_strength(plasmid), do: pili_strength(plasmid)

  defp raw_genes_have_orit?(genes) when is_list(genes) do
    Enum.any?(genes, fn gene ->
      blocks = Map.get(gene, :intergenic_blocks, %{})
      transfer = Map.get(blocks, :transfer, Map.get(blocks, "transfer", []))
      "orit_site" in List.wrap(transfer)
    end)
  end

  @doc """
  Find a helper plasmid in a *donor* genome that can supply the
  pilus apparatus to a *mobilizable* plasmid. The helper must
  itself be self-conjugative (so it provides a working pilus and
  has its own relaxase / oriT — though those don't aid the mob
  plasmid). Returns `nil` when no such helper exists.

  Phase 28 / 28.1 — Smillie et al. 2010 model: in vivo, an IncF
  helper plasmid in the same donor cell can mobilise a co-resident
  ColE1-type relaxosome by lending its T4SS apparatus.
  """
  @spec helper_plasmid(Genome.t(), Genome.plasmid()) :: Genome.plasmid() | nil
  def helper_plasmid(%Genome{plasmids: plasmids}, %{} = mob_plasmid) do
    Enum.find(plasmids, fn p ->
      p != mob_plasmid and self_conjugative?(p)
    end)
  end

  def helper_plasmid(_, _), do: nil

  @doc """
  Run one HGT conjugation step for all lineages in a single phase.

  For each (donor, recipient) pair where the donor has a conjugative plasmid
  and the recipient lacks it, compute the conjugation probability and
  stochastically transfer the plasmid.

  Returns `{updated_lineages, phase, new_child_lineages, events, new_rng}`
  conforming to the `Arkea.Sim.HGT.Channel.result/0` 5-tuple shape so
  the caller (`Tick.step_hgt/1`) can prepend `events` onto
  `BiotopeState.pending_events`. Sub-task 2.1 (remediation) reordered
  the arguments to `(lineages, phase, tick, rng)` and the second slot
  of the result to the `Phase` struct itself: conjugation does not
  modify phase chemistry, so the input phase is returned unchanged.

  ## Events

  - `%{type: :hgt_transfer, channel: :conjugation, donor_lineage_id,
       recipient_lineage_id, plasmid_inc_group, tick}` — emitted on every
    successful transfer that reaches `execute_transfer/8`.
  - `%{type: :plasmid_displaced, recipient_lineage_id,
       displaced_inc_group, new_donor_lineage_id, tick}` — emitted when
    the recipient already carries a plasmid of the same `inc_group` as
    the donor's; the conjugation is suppressed (current biology) but the
    inc-group conflict is surfaced for the audit log so downstream
    consumers can distinguish "no transfer happened" from "no transfer
    attempted".

  ## Constraints

  - At most 1 HGT event per (donor, recipient) pair per tick.
  - At most `div(length(lineages), 4)` new children per tick.
  - Lineages with `genome: nil` are skipped (no genome to transfer to/from).
  """
  @impl Arkea.Sim.HGT.Channel
  @spec step(
          lineages :: [Lineage.t()],
          phase :: Phase.t(),
          tick :: non_neg_integer(),
          rng :: :rand.state()
        ) :: {[Lineage.t()], Phase.t(), [Lineage.t()], [map()], :rand.state()}
  def step(lineages, %Phase{} = phase, tick, rng) when is_integer(tick) do
    phase_name = phase.name
    max_children = max(div(length(lineages), 4), 1)
    n_total = total_abundance_in_phase(lineages, phase_name)

    donors = find_donors(lineages, phase_name)
    eligible_recipients = find_eligible_recipients(lineages, phase_name)

    lineage_map = Map.new(lineages, fn l -> {l.id, l} end)

    {lineage_map_out, children, events, rng_out} =
      Enum.reduce(donors, {lineage_map, [], [], rng}, fn {donor, plasmid, transfer_mode}, acc ->
        do_donor_transfers(
          donor,
          plasmid,
          transfer_mode,
          eligible_recipients,
          phase_name,
          n_total,
          tick,
          acc,
          max_children
        )
      end)

    updated = Enum.map(lineages, fn l -> Map.get(lineage_map_out, l.id, l) end)
    # Events were prepended (`[event | acc]`); reverse to recover insertion order.
    # Conjugation does not modify phase chemistry — return the input phase struct.
    {updated, phase, children, Enum.reverse(events), rng_out}
  end

  @doc """
  Prophage induction step (Phase 12 — 01-DESIGN.md Block 8).

  For each lineage with at least one integrated prophage cassette in
  `:lysogenic` state, compute a per-cassette induction probability driven
  by metabolic stress. On induction, the cassette is committed to the
  lytic cycle: `Arkea.Sim.HGT.Phage.lytic_burst/5` reduces the host
  abundance, deposits free virions in the phase `phage_pool`, drops the
  cassette from the host genome, and appends a chromosomal fragment to
  the phase `dna_pool`.

  Returns `{updated_lineages, updated_phases, new_rng}`.

  ## Stress formula

      energy_cost = phenotype.energy_cost  (0.0..5.0)
      stress_factor = max(0.0, 1.0 - atp_yield / max(energy_cost × 5.0, 0.1))
      p_induction = clamp(0.03 × stress_factor × (1 - repressor_strength), 0.0, 0.1)

  When `atp_yield == 0.0` and `energy_cost > 0.0`, `stress_factor == 1.0`
  and induction probability is `0.03 × (1 - repressor_strength)` per
  cassette. A high-repressor cassette (`repressor_strength = 1.0`) is
  effectively immune to stress-driven induction; this gives selection a
  handle on the lysogeny↔lysis trade-off.
  """
  @spec induction_step(
          lineages :: [Lineage.t()],
          phases :: [Phase.t()],
          atp_yields :: %{binary() => float()},
          phenotypes :: %{binary() => Phenotype.t() | nil},
          tick :: non_neg_integer(),
          rng :: :rand.state()
        ) :: {[Lineage.t()], [Phase.t()], :rand.state()}
  def induction_step(lineages, phases, atp_yields, phenotypes, tick, rng) do
    phases_by_name = Map.new(phases, fn p -> {p.name, p} end)

    {updated_lineages, updated_phase_map, rng_out} =
      Enum.reduce(lineages, {[], phases_by_name, rng}, fn lineage,
                                                          {acc_lineages, acc_phases, acc_rng} ->
        {lineage_out, acc_phases_out, acc_rng_out} =
          maybe_induce(lineage, acc_phases, atp_yields, phenotypes, tick, acc_rng)

        {[lineage_out | acc_lineages], acc_phases_out, acc_rng_out}
      end)

    new_phases =
      Enum.map(phases, fn p -> Map.get(updated_phase_map, p.name, p) end)

    {Enum.reverse(updated_lineages), new_phases, rng_out}
  end

  # ---------------------------------------------------------------------------
  # Private — conjugation helpers

  # Find all (lineage, plasmid, transfer_mode) donor triples: lineage
  # has genome and abundance > 0 in this phase, AND the plasmid is
  # either self-conjugative (supplies its own triad) or mobilizable
  # with a self-conjugative helper plasmid co-resident in the same
  # donor (Phase 28 / 28.1 — Smillie et al. 2010 helper-mobilisation).
  defp find_donors(lineages, phase_name) do
    for lineage <- lineages,
        lineage.genome != nil,
        Lineage.abundance_in(lineage, phase_name) > 0,
        plasmid <- lineage.genome.plasmids,
        transfer_mode = transfer_mode_for(plasmid, lineage.genome),
        not is_nil(transfer_mode),
        do: {lineage, plasmid, transfer_mode}
  end

  # Pick the transfer mode for a plasmid in a given donor genome.
  # Returns `:self_conjugative` when the plasmid carries the full
  # triad on its own, `:mobilized` when a helper plasmid in the
  # donor supplies the pilus, or `nil` when no transfer is possible.
  defp transfer_mode_for(plasmid, %Genome{} = genome) do
    cond do
      self_conjugative?(plasmid) -> :self_conjugative
      mobilizable?(plasmid) and helper_plasmid(genome, plasmid) != nil -> :mobilized
      true -> nil
    end
  end

  # Find all lineages eligible to receive a plasmid: genome != nil and
  # abundance > 0 in this phase.
  defp find_eligible_recipients(lineages, phase_name) do
    Enum.filter(lineages, fn l ->
      l.genome != nil and Lineage.abundance_in(l, phase_name) > 0
    end)
  end

  # Total abundance of all lineages in a phase.
  defp total_abundance_in_phase(lineages, phase_name) do
    Enum.sum_by(lineages, fn l -> Lineage.abundance_in(l, phase_name) end)
  end

  # Transfer context groups the static per-phase parameters shared across all
  # (donor, recipient) pair evaluations within a single `step/4` call.
  defp transfer_ctx(donor, plasmid, transfer_mode, phase_name, n_total, tick) do
    %{
      donor: donor,
      plasmid: plasmid,
      transfer_mode: transfer_mode,
      phase_name: phase_name,
      n_total: n_total,
      tick: tick
    }
  end

  # Process all transfer attempts from one donor across all recipients.
  defp do_donor_transfers(
         donor,
         plasmid,
         transfer_mode,
         recipients,
         phase_name,
         n_total,
         tick,
         acc,
         max_children
       ) do
    ctx = transfer_ctx(donor, plasmid, transfer_mode, phase_name, n_total, tick)

    Enum.reduce(recipients, acc, fn recipient, {lmap, children, events, rng} ->
      if length(children) >= max_children do
        {lmap, children, events, rng}
      else
        attempt_transfer(ctx, recipient, lmap, children, events, rng)
      end
    end)
  end

  # Attempt a single plasmid transfer from donor to recipient.
  # Skips if donor == recipient, recipient already has the plasmid,
  # or the recipient is no longer in the map (was already updated).
  defp attempt_transfer(ctx, recipient, lmap, children, events, rng) do
    current_recipient = Map.get(lmap, recipient.id, recipient)

    cond do
      ctx.donor.id == recipient.id ->
        {lmap, children, events, rng}

      recipient_has_plasmid?(current_recipient, ctx.plasmid) ->
        # Sub-task 1.4: surface the inc-group conflict as an audit event.
        # The transfer is suppressed (biology unchanged), but downstream
        # consumers can distinguish "no transfer happened" (this branch)
        # from "no transfer attempted" (the donor.id == recipient.id branch).
        event = build_plasmid_displaced_event(ctx.donor, current_recipient, ctx.plasmid, ctx.tick)
        {lmap, children, [event | events], rng}

      true ->
        {roll, rng1} = :rand.uniform_s(rng)

        p =
          conjugation_probability(
            ctx.plasmid,
            ctx.transfer_mode,
            ctx.donor,
            current_recipient,
            ctx.phase_name,
            ctx.n_total
          )

        if roll < p do
          execute_transfer(ctx, current_recipient, lmap, children, events, rng1)
        else
          {lmap, children, events, rng1}
        end
    end
  end

  # Compute the conjugation probability for a (donor, recipient,
  # transfer_mode) triple. Phase 28 / 28.1 — the *triad* gates
  # whether a plasmid can conjugate at all (handled in
  # `find_donors`/`transfer_mode_for`); once gated, the throughput
  # factor remains the *pilus count* (preserving the pre-Phase-28
  # calibration so existing Phase 5/6/7 transfer-rate tests keep
  # firing). Mobilizable transfers borrow the helper plasmid's
  # pilus strength scaled by `@mobilisation_efficiency` (helper-
  # mediated transfer is biologically less efficient than self-
  # conjugation — the relaxosome must assemble at the mob
  # plasmid's oriT and dock with the helper's T4SS, an extra
  # protein-protein interaction that introduces failure modes,
  # Smillie et al. 2010).
  defp conjugation_probability(plasmid, transfer_mode, donor, recipient, phase_name, n_total) do
    strength = effective_strength(plasmid, transfer_mode, donor.genome)

    transfer_bias =
      Intergenic.transfer_probability_multiplier(donor.genome, recipient.genome, plasmid)

    n_donor = Lineage.abundance_in(donor, phase_name)
    n_recip = Lineage.abundance_in(recipient, phase_name)
    denom = max(n_total * n_total, 1)
    raw = strength * transfer_bias * @conj_base_rate * n_donor * n_recip / denom
    raw |> max(0.0) |> min(@p_conj_max)
  end

  @mobilisation_efficiency 0.5

  defp effective_strength(plasmid, :self_conjugative, _donor_genome) do
    pili_strength(plasmid)
  end

  defp effective_strength(plasmid, :mobilized, donor_genome) do
    case helper_plasmid(donor_genome, plasmid) do
      nil ->
        0

      %{} = helper ->
        helper_pili = pili_strength(helper)
        round(helper_pili * @mobilisation_efficiency)
    end
  end

  # True when the recipient already carries a plasmid identical to the
  # donor plasmid by Phase-16 incompatibility (`inc_group`). Same group
  # ⇒ would displace, so we suppress the transfer to avoid creating a
  # transconjugant identical to the donor.
  defp recipient_has_plasmid?(recipient, %{inc_group: inc} = _donor_plasmid) do
    Enum.any?(recipient.genome.plasmids, fn p -> p.inc_group == inc end)
  end

  # Execute a confirmed plasmid transfer: create a child lineage for the
  # recipient and decrement the recipient's abundance by 5. The
  # transfer-context bundle keeps the arity bounded.
  defp execute_transfer(ctx, recipient, lmap, children, events, rng) do
    %{
      donor: donor,
      plasmid: plasmid,
      transfer_mode: transfer_mode,
      phase_name: phase_name,
      tick: tick
    } =
      ctx

    child_genome = Genome.add_plasmid(recipient.genome, plasmid)

    # child tick must be strictly greater than parent (recipient) created_at_tick
    child_tick = max(tick + 1, recipient.created_at_tick + 1)
    # Seed the transconjugant with 5 units so it survives the dilution step
    # in the same tick (floor(5 × (1 - rate)) ≥ 1 for any rate ≤ 0.80).
    child_abundances = %{phase_name => 5}
    child = Lineage.new_child(recipient, child_genome, child_abundances, child_tick)

    # Decrement recipient abundance by 5 (abundance conservation)
    updated_recipient = decrement_abundance(recipient, phase_name, 5)

    # Ensure donor is also preserved in map (it may have been updated by prior step)
    lmap1 = Map.put(lmap, recipient.id, updated_recipient)
    lmap2 = Map.put(lmap1, donor.id, Map.get(lmap1, donor.id, donor))

    event = build_hgt_transfer_event(donor, recipient, plasmid, transfer_mode, tick)

    {lmap2, [child | children], [event | events], rng}
  end

  # Sub-task 1.4 — channel-direct audit event constructors.
  # Phase 28 / 28.1 — payload now includes `transfer_mode`
  # (`:self_conjugative` | `:mobilized`) so the audit log
  # distinguishes triad-complete transfers from helper-mediated ones
  # (the gene-tree-vs-species-tree view of Phase 26 / 3.8 can use
  # this to refine HGT incongruence detection).

  defp build_hgt_transfer_event(
         %Lineage{} = donor,
         %Lineage{} = recipient,
         plasmid,
         transfer_mode,
         tick
       ) do
    %{
      type: :hgt_transfer,
      channel: :conjugation,
      transfer_mode: transfer_mode,
      donor_lineage_id: donor.id,
      recipient_lineage_id: recipient.id,
      plasmid_inc_group: plasmid_inc_group(plasmid),
      tick: tick
    }
  end

  defp build_plasmid_displaced_event(%Lineage{} = donor, %Lineage{} = recipient, plasmid, tick) do
    %{
      type: :plasmid_displaced,
      recipient_lineage_id: recipient.id,
      displaced_inc_group: plasmid_inc_group(plasmid),
      new_donor_lineage_id: donor.id,
      tick: tick
    }
  end

  defp plasmid_inc_group(%{inc_group: inc}), do: inc
  defp plasmid_inc_group(_), do: nil

  # Decrement the abundance in `phase_name` by `amount`, clamped at 0.
  defp decrement_abundance(lineage, phase_name, amount) do
    current = Map.get(lineage.abundance_by_phase, phase_name, 0)
    new_count = max(current - amount, 0)
    new_abundances = Map.put(lineage.abundance_by_phase, phase_name, new_count)
    %{lineage | abundance_by_phase: new_abundances, fitness_cache: nil}
  end

  # ---------------------------------------------------------------------------
  # Private — prophage induction helpers

  defp maybe_induce(lineage, phases_by_name, _atp_yields, _phenotypes, _tick, rng)
       when lineage.genome == nil do
    {lineage, phases_by_name, rng}
  end

  defp maybe_induce(lineage, phases_by_name, _atp_yields, _phenotypes, _tick, rng)
       when lineage.genome.prophages == [] do
    {lineage, phases_by_name, rng}
  end

  defp maybe_induce(lineage, phases_by_name, atp_yields, phenotypes, tick, rng) do
    atp = Map.get(atp_yields, lineage.id, 0.0)
    phenotype = Map.get(phenotypes, lineage.id)

    energy_cost =
      if phenotype != nil, do: phenotype.energy_cost, else: 0.0

    denom = max(energy_cost * 5.0, 0.1)
    stress_factor = max(0.0, 1.0 - atp / denom)

    # Phase 17: SOS adds a multiplicative amplifier on top of the
    # ATP-deficit stress signal. The two pathways converge on the same
    # prophage repressor (RecA-mediated cleavage in vivo), so a cell
    # with both metabolic stress and DNA damage induces faster than
    # either alone.
    # Phase 25.5 / 7.6 — lineage-specific SOS threshold from
    # `:ligand_sensor` domains carrying `signal_key == "dna_damage"`.
    sos_threshold = Mutator.sos_threshold(lineage)

    sos_mult =
      if Mutator.sos_active?(lineage.dna_damage, sos_threshold),
        do: Mutator.sos_induction_amplifier(),
        else: 1.0

    apply_induction_rolls(lineage, phases_by_name, stress_factor, sos_mult, tick, rng)
  end

  # Walk each cassette in order, rolling its own induction probability.
  # On induction, delegate to `Phage.lytic_burst/5` which mutates both the
  # lineage genome (cassette dropped) and the lineage's primary phase.
  defp apply_induction_rolls(lineage, phases_by_name, stress_factor, sos_mult, tick, rng) do
    indexed = Enum.with_index(lineage.genome.prophages)

    Enum.reduce(indexed, {lineage, phases_by_name, rng}, fn
      {cassette, _idx}, {acc_lineage, acc_phases, acc_rng} ->
        roll_for_cassette(
          acc_lineage,
          acc_phases,
          cassette,
          stress_factor,
          sos_mult,
          tick,
          acc_rng
        )
    end)
  end

  defp roll_for_cassette(lineage, phases_by_name, cassette, stress_factor, sos_mult, tick, rng) do
    p =
      min(
        @p_induction_base * stress_factor * sos_mult * (1.0 - cassette.repressor_strength),
        @p_induction_max
      )

    {roll, rng1} = :rand.uniform_s(rng)

    if roll < p do
      trigger_burst(lineage, phases_by_name, cassette, tick, rng1)
    else
      {lineage, phases_by_name, rng1}
    end
  end

  defp trigger_burst(lineage, phases_by_name, cassette, tick, rng) do
    primary_phase_name = primary_phase_for(lineage, phases_by_name)

    case Map.get(phases_by_name, primary_phase_name) do
      nil ->
        {lineage, phases_by_name, rng}

      phase ->
        idx = Enum.find_index(lineage.genome.prophages, fn c -> c == cassette end)

        if is_nil(idx) do
          {lineage, phases_by_name, rng}
        else
          {l_out, p_out, _virion, rng_out} = Phage.lytic_burst(lineage, phase, idx, tick, rng)
          {l_out, Map.put(phases_by_name, p_out.name, p_out), rng_out}
        end
    end
  end

  defp primary_phase_for(lineage, phases_by_name) do
    case Map.keys(phases_by_name) do
      [] ->
        nil

      [first | _] = phase_names ->
        inhabited =
          Enum.filter(phase_names, fn name ->
            Map.get(lineage.abundance_by_phase, name, 0) > 0
          end)

        if inhabited != [] do
          Enum.max_by(inhabited, fn name ->
            Map.get(lineage.abundance_by_phase, name, 0)
          end)
        else
          first
        end
    end
  end
end
