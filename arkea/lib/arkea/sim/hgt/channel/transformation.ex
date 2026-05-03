defmodule Arkea.Sim.HGT.Channel.Transformation do
  @moduledoc """
  Natural transformation channel (Phase 13 — DESIGN.md Block 8).

  A *competent* recipient lineage takes up free DNA from its phase
  `dna_pool` and integrates a donor gene into its chromosome via simple
  positional homologous recombination (allelic replacement).

  This module is **strictly pure**: no I/O, no OTP calls. All
  stochasticity comes from the `:rand` state passed as an argument.

  ## Generative model

  In real biology natural transformation is a regulated, multi-step
  process: the donor DNA must (a) survive in the environment, (b) bind
  to a competence pseudopilus, (c) cross the membrane through a pore,
  (d) escape host restriction, and (e) recombine with the chromosome
  through a homology-directed pathway. Arkea collapses this into the
  generative chain:

      uptake_rate ∝ phenotype.competence_score × fragment.abundance × @uptake_base
      → R-M gate (Defense.restriction_check/3 with fragment methylation)
      → allelic replacement (positional homology — same chromosome index)

  - **Competence** (`Phenotype.competence_score`) is non-zero only when
    the recipient encodes the three Phase-13 categories
    (`:channel_pore + :transmembrane_anchor + :ligand_sensor`); the
    score scales with the geometric mean of their counts.
  - **R-M gating** (`Arkea.Sim.HGT.Defense`) reuses Phase 12 logic: if
    the recipient's restriction enzymes match a fragment locus that the
    donor's methylase did not protect, the fragment is digested.
  - **Recombination** is positional. The fragment carries the donor's
    chromosome (or a representative subset). A donor gene at index *i*
    can replace the recipient's chromosome[i] only when both indices
    exist; out-of-range indices are skipped (no homology, no insertion).

  ## Constraints

  - At most one transformant child per recipient per call (mirrors the
    Phase 6 conjugation rate ceiling).
  - Self-uptake (recipient origin == fragment origin) is rejected: it
    has no genetic effect and would inflate counts artificially.
  - Each successful uptake consumes one unit of `fragment.abundance` —
    abundance conservation across the gate.
  """

  @behaviour Arkea.Sim.HGT.Channel

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Gene
  alias Arkea.Sim.HGT.Defense
  alias Arkea.Sim.HGT.DnaFragment
  alias Arkea.Sim.Phenotype

  @impl true
  def name, do: :transformation

  @uptake_base 0.0006
  @p_uptake_max 0.20
  @child_seed_abundance 5

  @doc """
  Run one transformation sweep across a phase.

  For each `(competent recipient, fragment)` pair the function rolls
  the uptake probability, applies the R-M gate, and on success builds a
  transconjugant child lineage with the donor gene swapped at its
  chromosomal locus.

  Returns `{updated_lineages, updated_phase, new_children, rng_out}`.

  Pure.
  """
  @impl true
  @spec step(
          [Lineage.t()],
          Phase.t(),
          non_neg_integer(),
          :rand.state()
        ) :: {[Lineage.t()], Phase.t(), [Lineage.t()], :rand.state()}
  def step(lineages, %Phase{dna_pool: pool} = phase, _tick, rng) when map_size(pool) == 0,
    do: {lineages, phase, [], rng}

  def step(lineages, %Phase{} = phase, tick, rng) do
    competent =
      Enum.filter(lineages, fn l ->
        l.genome != nil and Lineage.abundance_in(l, phase.name) > 0 and competent?(l)
      end)

    if competent == [] do
      {lineages, phase, [], rng}
    else
      do_step(lineages, competent, phase, tick, rng)
    end
  end

  @doc """
  True iff the recipient phenotype crosses the competence threshold.

  Competence is gated rather than gradual: below the threshold the
  uptake rate falls below detection in any reasonable simulation
  duration, so it is cheaper to skip than to roll trivially-rare
  events.
  """
  @spec competent?(Lineage.t()) :: boolean()
  def competent?(%Lineage{genome: nil}), do: false

  def competent?(%Lineage{genome: genome}) do
    Phenotype.from_genome(genome).competence_score >= 0.10
  end

  # ---------------------------------------------------------------------------
  # Private

  defp do_step(lineages, competent, phase, tick, rng) do
    Enum.reduce(competent, {lineages, phase, [], rng}, fn recipient, acc ->
      Enum.reduce(acc |> elem(1) |> Map.fetch!(:dna_pool), acc, fn {fragment_id, fragment}, inner_acc ->
        attempt_uptake(fragment_id, fragment, recipient, tick, inner_acc)
      end)
    end)
  end

  defp attempt_uptake(fragment_id, fragment, recipient, tick, {ls, ph, children, rng}) do
    cond do
      fragment.abundance == 0 ->
        {ls, ph, children, rng}

      fragment.origin_lineage_id == recipient.id ->
        # Skip self-uptake: it would not change the recipient's genome.
        {ls, ph, children, rng}

      not Map.has_key?(ph.dna_pool, fragment_id) ->
        {ls, ph, children, rng}

      true ->
        do_attempt_uptake(fragment_id, fragment, recipient, tick, {ls, ph, children, rng})
    end
  end

  defp do_attempt_uptake(fragment_id, fragment, recipient, tick, {ls, ph, children, rng}) do
    current_recipient = find_lineage(ls, recipient.id) || recipient
    recipient_phenotype = Phenotype.from_genome(current_recipient.genome)
    p_uptake = compute_uptake_probability(recipient_phenotype, fragment)

    {roll, rng1} = :rand.uniform_s(rng)

    if roll >= p_uptake do
      {ls, ph, children, rng1}
    else
      run_rm_gate(fragment_id, fragment, current_recipient, recipient_phenotype, tick, {ls, ph, children, rng1})
    end
  end

  defp run_rm_gate(fragment_id, fragment, recipient, phenotype, tick, {ls, ph, children, rng}) do
    case Defense.restriction_check(
           phenotype.restriction_profile,
           fragment.methylation_profile,
           rng
         ) do
      {:digested, _sites, rng1} ->
        # The R-M system cleaved the incoming DNA. Consume one unit
        # (abundance conservation) and emit no transformant.
        {ls, consume_one_fragment(ph, fragment_id), children, rng1}

      {:passed, rng1} ->
        attempt_recombination(fragment_id, fragment, recipient, tick, {ls, ph, children, rng1})
    end
  end

  defp attempt_recombination(fragment_id, fragment, recipient, tick, {ls, ph, children, rng}) do
    case pick_homologous_pair(fragment.genes, recipient.genome.chromosome, rng) do
      {nil, _, rng1} ->
        # No homology found: rejection (Phase 13 simplified). Consume
        # one fragment unit so abundance still goes down on the gate
        # event itself.
        {ls, consume_one_fragment(ph, fragment_id), children, rng1}

      {donor_gene, index, rng1} ->
        finalise_transformation(
          fragment_id,
          fragment,
          recipient,
          donor_gene,
          index,
          tick,
          {ls, ph, children, rng1}
        )
    end
  end

  defp finalise_transformation(
         fragment_id,
         _fragment,
         recipient,
         donor_gene,
         index,
         tick,
         {ls, ph, children, rng}
       ) do
    new_chromosome = List.replace_at(recipient.genome.chromosome, index, donor_gene)
    new_genome = rebuild_genome_with_chromosome(recipient.genome, new_chromosome)

    child_tick = max(tick + 1, recipient.created_at_tick + 1)
    child_abundances = %{ph.name => @child_seed_abundance}
    child = Lineage.new_child(recipient, new_genome, child_abundances, child_tick)

    updated_recipient = decrement_abundance(recipient, ph.name, @child_seed_abundance)
    new_lineages = replace_lineage(ls, recipient.id, updated_recipient)

    new_phase = consume_one_fragment(ph, fragment_id)
    {new_lineages, new_phase, [child | children], rng}
  end

  defp pick_homologous_pair(donor_genes, recipient_chromosome, rng) do
    n_recipient = length(recipient_chromosome)
    n_donor = length(donor_genes)

    candidates =
      0..(min(n_donor, n_recipient) - 1)//1
      |> Enum.to_list()

    case candidates do
      [] ->
        {nil, nil, rng}

      [single] ->
        {Enum.at(donor_genes, single), single, rng}

      _ ->
        {raw, rng1} = :rand.uniform_s(length(candidates), rng)
        index = Enum.at(candidates, raw - 1)
        {Enum.at(donor_genes, index), index, rng1}
    end
  end

  defp rebuild_genome_with_chromosome(%Genome{} = genome, new_chromosome) do
    Genome.new(new_chromosome, plasmids: genome.plasmids, prophages: genome.prophages)
  end

  defp compute_uptake_probability(%Phenotype{competence_score: c}, %DnaFragment{abundance: a}) do
    raw = @uptake_base * c * a
    raw |> max(0.0) |> min(@p_uptake_max)
  end

  defp consume_one_fragment(%Phase{dna_pool: pool} = phase, fragment_id) do
    case Map.get(pool, fragment_id) do
      nil ->
        phase

      %DnaFragment{abundance: a} when a <= 1 ->
        %{phase | dna_pool: Map.delete(pool, fragment_id)}

      %DnaFragment{} = fragment ->
        %{phase | dna_pool: Map.put(pool, fragment_id, %{fragment | abundance: fragment.abundance - 1})}
    end
  end

  defp decrement_abundance(%Lineage{} = lineage, phase_name, amount) do
    current = Map.get(lineage.abundance_by_phase, phase_name, 0)
    new_count = max(current - amount, 0)
    new_abundances = Map.put(lineage.abundance_by_phase, phase_name, new_count)
    %{lineage | abundance_by_phase: new_abundances, fitness_cache: nil}
  end

  defp find_lineage(lineages, id), do: Enum.find(lineages, fn l -> l.id == id end)

  defp replace_lineage(lineages, id, replacement) do
    Enum.map(lineages, fn l -> if l.id == id, do: replacement, else: l end)
  end

  # Suppress unused alias warning when Gene type appears only in specs.
  _ = Gene
end
