defmodule Arkea.Sim.HGT do
  @moduledoc """
  Pure horizontal gene transfer (HGT) logic for Phase 6 (DESIGN.md Block 5).

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
  True if the plasmid is conjugative.

  Accepts either a `Genome.plasmid()` map or a raw gene list (legacy).
  A plasmid is conjugative when it contains at least one gene with at
  least one `:transmembrane_anchor` domain (pilus-like proxy, DESIGN.md
  Block 5).
  """
  @spec conjugative?(Genome.plasmid() | [Gene.t()]) :: boolean()
  def conjugative?(plasmid), do: conjugation_strength(plasmid) > 0

  @doc """
  Conjugation strength: total count of `:transmembrane_anchor` domains
  in the plasmid. Zero for non-conjugative plasmids. Accepts either a
  `Genome.plasmid()` map or a raw gene list (legacy).
  """
  @spec conjugation_strength(Genome.plasmid() | [Gene.t()]) :: non_neg_integer()
  def conjugation_strength(%{genes: genes}) when is_list(genes), do: conjugation_strength(genes)

  def conjugation_strength(plasmid_genes) when is_list(plasmid_genes) do
    Enum.sum_by(plasmid_genes, fn gene ->
      Enum.count(gene.domains, fn domain -> domain.type == :transmembrane_anchor end)
    end)
  end

  @doc """
  Run one HGT conjugation step for all lineages in a single phase.

  For each (donor, recipient) pair where the donor has a conjugative plasmid
  and the recipient lacks it, compute the conjugation probability and
  stochastically transfer the plasmid.

  Returns `{updated_lineages, new_child_lineages, new_rng}`.

  ## Constraints

  - At most 1 HGT event per (donor, recipient) pair per tick.
  - At most `div(length(lineages), 4)` new children per tick.
  - Lineages with `genome: nil` are skipped (no genome to transfer to/from).
  """
  @spec step(
          phase_name :: atom(),
          lineages :: [Lineage.t()],
          tick :: non_neg_integer(),
          rng :: :rand.state()
        ) :: {[Lineage.t()], [Lineage.t()], :rand.state()}
  def step(phase_name, lineages, tick, rng) when is_atom(phase_name) and is_integer(tick) do
    max_children = max(div(length(lineages), 4), 1)
    n_total = total_abundance_in_phase(lineages, phase_name)

    donors = find_donors(lineages, phase_name)
    eligible_recipients = find_eligible_recipients(lineages, phase_name)

    lineage_map = Map.new(lineages, fn l -> {l.id, l} end)

    {lineage_map_out, children, rng_out} =
      Enum.reduce(donors, {lineage_map, [], rng}, fn {donor, plasmid}, acc ->
        do_donor_transfers(
          donor,
          plasmid,
          eligible_recipients,
          phase_name,
          n_total,
          tick,
          acc,
          max_children
        )
      end)

    updated = Enum.map(lineages, fn l -> Map.get(lineage_map_out, l.id, l) end)
    {updated, children, rng_out}
  end

  @doc """
  Prophage induction step (Phase 12 — DESIGN.md Block 8).

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

  # Find all (lineage, plasmid) donor pairs: lineage has genome, has
  # conjugative plasmids, and has abundance > 0 in this phase.
  defp find_donors(lineages, phase_name) do
    for lineage <- lineages,
        lineage.genome != nil,
        Lineage.abundance_in(lineage, phase_name) > 0,
        plasmid <- lineage.genome.plasmids,
        conjugative?(plasmid),
        do: {lineage, plasmid}
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
  defp transfer_ctx(donor, plasmid, phase_name, n_total, tick) do
    %{donor: donor, plasmid: plasmid, phase_name: phase_name, n_total: n_total, tick: tick}
  end

  # Process all transfer attempts from one donor across all recipients.
  defp do_donor_transfers(
         donor,
         plasmid,
         recipients,
         phase_name,
         n_total,
         tick,
         acc,
         max_children
       ) do
    ctx = transfer_ctx(donor, plasmid, phase_name, n_total, tick)

    Enum.reduce(recipients, acc, fn recipient, {lmap, children, rng} ->
      if length(children) >= max_children do
        {lmap, children, rng}
      else
        attempt_transfer(ctx, recipient, lmap, children, rng)
      end
    end)
  end

  # Attempt a single plasmid transfer from donor to recipient.
  # Skips if donor == recipient, recipient already has the plasmid,
  # or the recipient is no longer in the map (was already updated).
  defp attempt_transfer(ctx, recipient, lmap, children, rng) do
    current_recipient = Map.get(lmap, recipient.id, recipient)

    cond do
      ctx.donor.id == recipient.id ->
        {lmap, children, rng}

      recipient_has_plasmid?(current_recipient, ctx.plasmid) ->
        {lmap, children, rng}

      true ->
        {roll, rng1} = :rand.uniform_s(rng)

        p =
          conjugation_probability(
            ctx.plasmid,
            ctx.donor,
            current_recipient,
            ctx.phase_name,
            ctx.n_total
          )

        if roll < p do
          execute_transfer(
            ctx.donor,
            current_recipient,
            ctx.plasmid,
            ctx.phase_name,
            ctx.tick,
            lmap,
            children,
            rng1
          )
        else
          {lmap, children, rng1}
        end
    end
  end

  # Compute the conjugation probability for a (donor, recipient) pair.
  defp conjugation_probability(plasmid, donor, recipient, phase_name, n_total) do
    strength = conjugation_strength(plasmid)

    transfer_bias =
      Intergenic.transfer_probability_multiplier(donor.genome, recipient.genome, plasmid)

    n_donor = Lineage.abundance_in(donor, phase_name)
    n_recip = Lineage.abundance_in(recipient, phase_name)
    denom = max(n_total * n_total, 1)
    raw = strength * transfer_bias * @conj_base_rate * n_donor * n_recip / denom
    raw |> max(0.0) |> min(@p_conj_max)
  end

  # True when the recipient already carries a plasmid identical to the
  # donor plasmid by Phase-16 incompatibility (`inc_group`). Same group
  # ⇒ would displace, so we suppress the transfer to avoid creating a
  # transconjugant identical to the donor.
  defp recipient_has_plasmid?(recipient, %{inc_group: inc} = _donor_plasmid) do
    Enum.any?(recipient.genome.plasmids, fn p -> p.inc_group == inc end)
  end

  # Execute a confirmed plasmid transfer: create a child lineage for the
  # recipient and decrement the recipient's abundance by 5.
  defp execute_transfer(donor, recipient, plasmid, phase_name, tick, lmap, children, rng) do
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

    {lmap2, [child | children], rng}
  end

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
    sos_mult =
      if Mutator.sos_active?(lineage.dna_damage),
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
