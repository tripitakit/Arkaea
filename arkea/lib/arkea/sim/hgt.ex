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
      n_donor  = Lineage.abundance_in(donor, phase_name)
      n_recip  = Lineage.abundance_in(recipient, phase_name)
      n_total  = total abundance of all lineages in this phase
      p_conj   = clamp(strength × 0.005 × n_donor × n_recip / max(n_total², 1), 0.0, 0.3)

  When the RNG roll falls below `p_conj`, a new child lineage of the recipient
  is created carrying the donor's plasmid. Abundance is conserved: the
  recipient loses 1 unit in the phase.

  ## Prophage induction model

      stress_factor = max(0.0, 1.0 - atp_yield / max(energy_cost × 5.0, 0.1))
      p_induction   = clamp(0.03 × stress_factor, 0.0, 0.1) per prophage cassette

  On induction: the lineage loses `floor(abundance × 0.5)` units (lytic burst).
  """

  alias Arkea.Ecology.Lineage
  alias Arkea.Genome
  alias Arkea.Genome.Gene
  alias Arkea.Sim.Phenotype

  @conj_base_rate 0.005
  @p_conj_max 0.3
  @p_induction_max 0.1
  @p_induction_base 0.03
  @lysis_fraction 0.5

  # ---------------------------------------------------------------------------
  # Public API

  @doc """
  True if the plasmid (list of genes) is conjugative.

  A plasmid is conjugative when it contains at least one gene with at least one
  `:transmembrane_anchor` domain (pilus-like proxy, DESIGN.md Block 5).
  """
  @spec conjugative?([Gene.t()]) :: boolean()
  def conjugative?(plasmid_genes) when is_list(plasmid_genes) do
    conjugation_strength(plasmid_genes) > 0
  end

  @doc """
  Conjugation strength: total count of `:transmembrane_anchor` domains in the
  plasmid. Zero for non-conjugative plasmids.
  """
  @spec conjugation_strength([Gene.t()]) :: non_neg_integer()
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
  Prophage induction step.

  For each lineage with at least one integrated prophage, compute a per-cassette
  induction probability driven by metabolic stress. On induction, the lineage
  loses `floor(abundance × 0.5)` cells (lytic burst).

  Returns `{updated_lineages, new_rng}`.

  ## Stress formula

      energy_cost = phenotype.energy_cost  (0.0..5.0)
      stress_factor = max(0.0, 1.0 - atp_yield / max(energy_cost × 5.0, 0.1))
      p_induction = clamp(0.03 × stress_factor, 0.0, 0.1)

  When `atp_yield == 0.0` and `energy_cost > 0.0`, `stress_factor == 1.0` and
  induction probability is at its maximum (`0.1` per cassette).
  """
  @spec induction_step(
          lineages :: [Lineage.t()],
          atp_yields :: %{binary() => float()},
          phenotypes :: %{binary() => Phenotype.t() | nil},
          rng :: :rand.state()
        ) :: {[Lineage.t()], :rand.state()}
  def induction_step(lineages, atp_yields, phenotypes, rng) do
    Enum.map_reduce(lineages, rng, fn lineage, acc_rng ->
      maybe_induce(lineage, atp_yields, phenotypes, acc_rng)
    end)
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
    n_donor = Lineage.abundance_in(donor, phase_name)
    n_recip = Lineage.abundance_in(recipient, phase_name)
    denom = max(n_total * n_total, 1)
    raw = strength * @conj_base_rate * n_donor * n_recip / denom
    raw |> max(0.0) |> min(@p_conj_max)
  end

  # True when the recipient already carries a plasmid with the same gene_count
  # as the donor plasmid (heuristic identity check).
  defp recipient_has_plasmid?(recipient, donor_plasmid) do
    target_count = length(donor_plasmid)

    Enum.any?(recipient.genome.plasmids, fn p -> length(p) == target_count end)
  end

  # Execute a confirmed plasmid transfer: create a child lineage for the
  # recipient and decrement the recipient's abundance by 1.
  defp execute_transfer(donor, recipient, plasmid, phase_name, tick, lmap, children, rng) do
    child_genome = Genome.add_plasmid(recipient.genome, plasmid)

    # child tick must be strictly greater than parent (recipient) created_at_tick
    child_tick = max(tick + 1, recipient.created_at_tick + 1)
    child_abundances = %{phase_name => 1}
    child = Lineage.new_child(recipient, child_genome, child_abundances, child_tick)

    # Decrement recipient abundance by 1 (abundance conservation)
    updated_recipient = decrement_abundance(recipient, phase_name, 1)

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

  defp maybe_induce(lineage, _atp_yields, _phenotypes, rng)
       when lineage.genome == nil do
    {lineage, rng}
  end

  defp maybe_induce(lineage, _atp_yields, _phenotypes, rng)
       when lineage.genome.prophages == [] do
    {lineage, rng}
  end

  defp maybe_induce(lineage, atp_yields, phenotypes, rng) do
    atp = Map.get(atp_yields, lineage.id, 0.0)
    phenotype = Map.get(phenotypes, lineage.id)

    energy_cost =
      if phenotype != nil, do: phenotype.energy_cost, else: 0.0

    denom = max(energy_cost * 5.0, 0.1)
    stress_factor = max(0.0, 1.0 - atp / denom)
    p_induction = min(@p_induction_base * stress_factor, @p_induction_max)

    n_cassettes = length(lineage.genome.prophages)
    apply_induction_rolls(lineage, p_induction, n_cassettes, rng)
  end

  # Roll p_induction once per prophage cassette.
  defp apply_induction_rolls(lineage, _p, 0, rng), do: {lineage, rng}

  defp apply_induction_rolls(lineage, p, n, rng) when n > 0 do
    {roll, rng1} = :rand.uniform_s(rng)

    lineage_out =
      if roll < p do
        apply_lytic_burst(lineage)
      else
        lineage
      end

    apply_induction_rolls(lineage_out, p, n - 1, rng1)
  end

  # Reduce all abundances by the lysis fraction (floor of 50%).
  defp apply_lytic_burst(lineage) do
    new_abundances =
      Map.new(lineage.abundance_by_phase, fn {phase_name, count} ->
        lost = floor(count * @lysis_fraction)
        {phase_name, max(count - lost, 0)}
      end)

    %{lineage | abundance_by_phase: new_abundances, fitness_cache: nil}
  end
end
