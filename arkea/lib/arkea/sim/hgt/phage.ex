defmodule Arkea.Sim.HGT.Phage do
  @moduledoc """
  The closed phage cycle (Phase 12 — DESIGN.md Block 8).

  This module is **strictly pure**: no I/O, no OTP calls, no PubSub, no
  DB. All stochasticity is driven by the `:rand` state passed as an
  argument; callers must persist the returned state.

  ## Cycle stages

  1. **Lytic burst** (`lytic_burst/3`) — a lineage carrying an `:induced`
     prophage cassette lyses: the lineage abundance drops, virions matching
     the cassette are deposited in the lysed cell's primary phase
     `phage_pool`, and a fragment representing the chromosomal DNA released
     by lysis is appended to the same phase `dna_pool` (substrate for
     Phase 13 transformation).
  2. **Infection** (`infection_step/4`) — a free virion encounters a
     candidate recipient lineage in the same phase. Receptor matching
     (surface_signature ↔ recipient `:surface_tag` set) gates a Poisson-
     style infection roll. On success, the R-M check (`HGT.Defense`)
     decides between digestion (no transfer) and successful entry; entry
     produces a child lineage carrying a freshly integrated prophage
     cassette in the lysogenic state.
  3. **Decay** (`decay_step/2`) — every tick free virions age; an
     additional age-dependent stochastic decay is applied on top of phase
     dilution to model the rapid loss of infectivity outside a host.

  Burst size emerges from cassette composition: every `:structural_fold`
  domain contributes its `:multimerization_n` parameter (capsid copy
  number proxy), capped at `@burst_size_max` to keep dynamics within
  biologically plausible orders of magnitude (10–500 virions per lysis,
  Wommack & Colwell 2000).
  """

  @behaviour Arkea.Sim.HGT.Channel

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Sim.HGT.Defense
  alias Arkea.Sim.HGT.DnaFragment
  alias Arkea.Sim.HGT.Virion
  alias Arkea.Sim.Phenotype

  @impl true
  def name, do: :phage_infection

  @impl true
  def step(lineages, phase, tick, rng), do: infection_step(lineages, phase, tick, rng)

  @burst_size_min 10
  @burst_size_max 500
  @burst_default 30

  # Phase 16 — generalised transduction.
  # Probability that a lytic burst also packages a chromosomal fragment
  # in some of its capsids: ~0.3% in real biology (Chen et al. 2018).
  # We collapse it to a single transducing virion per burst with this
  # probability — the abundance of that virion is a small fraction of
  # the main burst, mirroring the rare-but-non-zero rate observed in
  # vivo.
  @transduction_probability 0.05
  @transducing_burst_fraction 0.03

  # Per-tick decay applied on top of phase dilution. The full decay rate is
  # `@base_decay + @age_decay × decay_age`, clamped to 1.0. With the
  # defaults below a virion's expected free lifetime is ~3–5 ticks, which
  # matches the orders of magnitude reported for free-phage half-life in
  # planktonic environments (Suttle 1994).
  @base_decay 0.20
  @age_decay 0.05

  # Receptor matching parameters. The surface signature is a 4-codon string
  # (same encoding as a quorum-sensing signal_key). Matching is done by
  # equality against any recipient `:surface_tag` whose tag_class is
  # `:phage_receptor`. Infection rate scales with virion density and
  # recipient abundance, capped at `@p_infect_max`.
  @p_infect_base 0.0008
  @p_infect_max 0.25

  # Probability that a virion entry causes immediate lysis (lytic decision)
  # instead of lysogenic integration. The decision is biased by the cassette
  # `repressor_strength`: a strong repressor steers the cell toward lysogeny.
  @lytic_decision_base 0.40

  @doc """
  Apply a lytic burst to a lineage's prophage cassette.

  Removes `lysis_fraction × abundance` cells across the lineage's phases
  (default `0.5`), produces virions in the *primary* phase (the one with
  the highest abundance), drops the cassette from the host genome, and
  appends a chromosomal fragment to the phase `dna_pool`.

  Returns `{updated_lineage, updated_phase, virion_or_nil, rng_out}`.

  ## Notes

  - When the lineage genome is `nil`, the call is a no-op.
  - When `cassette_index` is out of range, the call is a no-op.
  - Phase `:phage_pool` and `:dna_pool` are updated in-place on the
    returned phase; callers must replace the matching phase in
    `BiotopeState.phases`.
  """
  @spec lytic_burst(
          Lineage.t(),
          Phase.t(),
          non_neg_integer(),
          non_neg_integer(),
          :rand.state()
        ) ::
          {Lineage.t(), Phase.t(), Virion.t() | nil, :rand.state()}
  def lytic_burst(%Lineage{genome: nil} = lineage, %Phase{} = phase, _idx, _tick, rng),
    do: {lineage, phase, nil, rng}

  def lytic_burst(%Lineage{} = lineage, %Phase{} = phase, cassette_index, tick, rng) do
    case Enum.at(lineage.genome.prophages, cassette_index) do
      nil ->
        {lineage, phase, nil, rng}

      cassette ->
        do_lytic_burst(lineage, phase, cassette, cassette_index, tick, rng)
    end
  end

  defp do_lytic_burst(lineage, phase, cassette, cassette_index, tick, rng) do
    abundance = Lineage.abundance_in(lineage, phase.name)

    if abundance == 0 do
      {lineage, phase, nil, rng}
    else
      lost = max(div(abundance, 2), 1)
      burst_size = burst_size_for(cassette, lost)
      surface_signature = surface_signature_for(cassette)
      methylation = methylation_profile_for(lineage)

      virion =
        Virion.new(
          id: Arkea.UUID.v4(),
          genes: cassette.genes,
          abundance: burst_size,
          surface_signature: surface_signature,
          methylation_profile: methylation,
          origin_lineage_id: lineage.id,
          created_at_tick: tick,
          payload_kind: :phage
        )

      {phase_with_phage, rng1} = {Phase.add_virion(phase, virion), rng}

      # Phase 16: with probability @transduction_probability, the burst
      # also mis-packages a chromosomal fragment into a small fraction
      # of its capsids — generalised transduction. The transducing
      # virion travels through the same `Phase.phage_pool`, but its
      # `payload_kind` flag re-routes infection through allelic
      # replacement instead of prophage integration.
      {phase_after_transduction, rng2} =
        maybe_emit_transducing_virion(
          phase_with_phage,
          lineage,
          cassette,
          burst_size,
          surface_signature,
          methylation,
          tick,
          rng1
        )

      new_phase = deposit_dna_fragment(phase_after_transduction, lineage, lost, tick)

      new_lineage =
        lineage
        |> drop_cassette(cassette_index)
        |> decrement_abundance(phase.name, lost)

      {new_lineage, new_phase, virion, rng2}
    end
  end

  defp maybe_emit_transducing_virion(
         phase,
         %Lineage{} = lineage,
         _cassette,
         burst_size,
         surface_signature,
         methylation,
         tick,
         rng
       ) do
    {roll, rng1} = :rand.uniform_s(rng)

    cond do
      roll >= @transduction_probability ->
        {phase, rng1}

      lineage.genome.chromosome == [] ->
        {phase, rng1}

      true ->
        {gene, rng2} = pick_random_gene(lineage.genome.chromosome, rng1)
        transducing_size = max(round(burst_size * @transducing_burst_fraction), 1)

        td_virion =
          Virion.new(
            id: Arkea.UUID.v4(),
            genes: [gene],
            abundance: transducing_size,
            surface_signature: surface_signature,
            methylation_profile: methylation,
            origin_lineage_id: lineage.id,
            created_at_tick: tick,
            payload_kind: :generalized_transduction
          )

        {Phase.add_virion(phase, td_virion), rng2}
    end
  end

  defp pick_random_gene(genes, rng) when is_list(genes) and genes != [] do
    {idx_one_based, rng1} = :rand.uniform_s(length(genes), rng)
    {Enum.at(genes, idx_one_based - 1), rng1}
  end

  @doc """
  Run one infection sweep across a phase.

  For each `(virion, recipient)` pair in the phase, evaluates the receptor
  match, rolls an infection probability, gates the entry through R-M
  (`HGT.Defense.restriction_check_virion/3`), and on success either
  triggers an immediate lytic burst on the recipient or integrates the
  cassette as a lysogenic prophage in a child lineage.

  Returns `{updated_lineages, updated_phase, new_children, rng_out}`.

  Pure.
  """
  @spec infection_step(
          [Lineage.t()],
          Phase.t(),
          non_neg_integer(),
          :rand.state()
        ) ::
          {[Lineage.t()], Phase.t(), [Lineage.t()], :rand.state()}
  def infection_step(lineages, %Phase{phage_pool: pool} = phase, _tick, rng)
      when map_size(pool) == 0 do
    {lineages, phase, [], rng}
  end

  def infection_step(lineages, %Phase{} = phase, tick, rng) do
    candidate_recipients =
      Enum.filter(lineages, fn l ->
        l.genome != nil and Lineage.abundance_in(l, phase.name) > 0
      end)

    n_total = total_abundance(candidate_recipients, phase.name)

    {lineages_out, phase_out, children, rng_out} =
      Enum.reduce(phase.phage_pool, {lineages, phase, [], rng}, fn {phage_id, virion}, acc ->
        process_virion(phage_id, virion, candidate_recipients, n_total, tick, acc)
      end)

    {lineages_out, phase_out, children, rng_out}
  end

  @doc """
  Apply decay to every virion in the phase pool.

  Each virion ages one tick and loses a fraction of its abundance equal to
  `min(1.0, @base_decay + @age_decay × decay_age)`. Pruned when abundance
  falls to zero.

  Pure.
  """
  @spec decay_step(Phase.t()) :: Phase.t()
  def decay_step(%Phase{phage_pool: pool} = phase) when map_size(pool) == 0, do: phase

  def decay_step(%Phase{phage_pool: pool} = phase) do
    new_pool =
      pool
      |> Enum.map(fn {id, %Virion{} = v} ->
        decay_factor = min(1.0, @base_decay + @age_decay * v.decay_age)
        new_abundance = max(round(v.abundance * (1.0 - decay_factor)), 0)
        {id, %{v | abundance: new_abundance, decay_age: v.decay_age + 1}}
      end)
      |> Enum.reject(fn {_id, %Virion{abundance: a}} -> a == 0 end)
      |> Map.new()

    %{phase | phage_pool: new_pool}
  end

  @doc "Burst-size accessor (exposed for tests)."
  def default_burst_size, do: @burst_default
  def max_burst_size, do: @burst_size_max
  def min_burst_size, do: @burst_size_min

  # ---------------------------------------------------------------------------
  # Private — burst helpers

  defp burst_size_for(cassette, _lost) do
    capsid_copies =
      cassette.genes
      |> Enum.flat_map(fn gene -> gene.domains end)
      |> Enum.filter(fn d -> d.type == :structural_fold end)
      |> Enum.map(fn d -> d.params[:multimerization_n] || 1 end)
      |> Enum.sum()

    base = if capsid_copies > 0, do: capsid_copies * 6, else: @burst_default
    base |> max(@burst_size_min) |> min(@burst_size_max)
  end

  defp surface_signature_for(cassette) do
    cassette.genes
    |> Enum.flat_map(fn gene -> gene.domains end)
    |> Enum.find_value(fn d ->
      cond do
        d.type == :surface_tag -> d.params[:signal_key] || surface_signature_from_codons(d)
        d.type == :catalytic_site -> d.params[:signal_key]
        true -> nil
      end
    end)
  end

  # `:surface_tag` domains do not currently carry a `:signal_key` param;
  # synthesize one from the parameter codons so receptor matching has a
  # stable per-cassette identifier even without a catalytic-site signal_key.
  defp surface_signature_from_codons(%{parameter_codons: codons}) do
    codons |> Enum.take(4) |> Enum.join(",")
  end

  defp methylation_profile_for(%Lineage{genome: nil}), do: []

  defp methylation_profile_for(%Lineage{} = lineage) do
    %{methylation_profile: methyl} = Phenotype.rm_profiles(lineage.genome)
    methyl
  end

  defp drop_cassette(%Lineage{genome: %Genome{} = g} = lineage, index) do
    new_prophages = List.delete_at(g.prophages, index)
    %{lineage | genome: Genome.set_prophages(g, new_prophages)}
  end

  defp decrement_abundance(%Lineage{} = lineage, phase_name, amount) do
    current = Map.get(lineage.abundance_by_phase, phase_name, 0)
    new_count = max(current - amount, 0)
    new_abundances = Map.put(lineage.abundance_by_phase, phase_name, new_count)
    %{lineage | abundance_by_phase: new_abundances, fitness_cache: nil}
  end

  defp deposit_dna_fragment(%Phase{} = phase, %Lineage{} = lineage, lost, tick) do
    methylation = methylation_profile_for(lineage)

    fragment =
      DnaFragment.new(
        id: Arkea.UUID.v4(),
        genes: lineage.genome.chromosome,
        abundance: lost,
        methylation_profile: methylation,
        origin_lineage_id: lineage.id,
        created_at_tick: tick
      )

    Phase.add_dna_fragment(phase, fragment)
  end

  # ---------------------------------------------------------------------------
  # Private — infection helpers

  defp total_abundance(lineages, phase_name) do
    Enum.sum_by(lineages, fn l -> Lineage.abundance_in(l, phase_name) end)
  end

  defp process_virion(phage_id, virion, recipients, n_total, tick, acc) do
    Enum.reduce(recipients, acc, fn recipient, {ls, ph, children, rng} ->
      attempt_infection(phage_id, virion, recipient, n_total, tick, {ls, ph, children, rng})
    end)
  end

  defp attempt_infection(phage_id, virion, recipient, n_total, tick, {ls, ph, children, rng}) do
    current_recipient = find_lineage(ls, recipient.id)

    cond do
      current_recipient == nil ->
        {ls, ph, children, rng}

      not receptor_match?(virion, current_recipient) ->
        {ls, ph, children, rng}

      true ->
        do_attempt_infection(
          phage_id,
          virion,
          current_recipient,
          n_total,
          tick,
          {ls, ph, children, rng}
        )
    end
  end

  defp do_attempt_infection(phage_id, virion, recipient, n_total, tick, {ls, ph, children, rng}) do
    n_recip = Lineage.abundance_in(recipient, ph.name)
    p_infect = compute_infection_probability(virion.abundance, n_recip, n_total)
    {roll, rng1} = :rand.uniform_s(rng)

    if roll >= p_infect do
      {ls, ph, children, rng1}
    else
      run_rm_and_outcome(phage_id, virion, recipient, tick, {ls, ph, children, rng1})
    end
  end

  defp run_rm_and_outcome(phage_id, virion, recipient, tick, {ls, ph, children, rng}) do
    recipient_phenotype = Phenotype.from_genome(recipient.genome)

    case Defense.restriction_check_virion(recipient_phenotype.restriction_profile, virion, rng) do
      {:digested, _sites, rng1} ->
        # The R-M system cleaves the incoming DNA; the virion is consumed
        # but no transfer happens. We still consume one virion particle to
        # reflect the encounter.
        new_phase = consume_one_virion(ph, phage_id)
        {ls, new_phase, children, rng1}

      {:passed, rng1} ->
        case virion.payload_kind do
          :phage ->
            decide_lytic_or_lysogenic(phage_id, virion, recipient, tick, {ls, ph, children, rng1})

          :generalized_transduction ->
            run_transducing_integration(
              phage_id,
              virion,
              recipient,
              tick,
              {ls, ph, children, rng1}
            )

          # Specialised transduction: Phase 16 stretch goal — the
          # virion carries the prophage cassette plus adjacent
          # chromosomal genes. We integrate the cassette as a normal
          # prophage (existing path) and additionally allelic-replace
          # the carried chromosomal genes by position.
          :specialized_transduction ->
            decide_lytic_or_lysogenic(phage_id, virion, recipient, tick, {ls, ph, children, rng1})
        end
    end
  end

  # Generalised transduction: virion mis-packaged a chromosomal gene.
  # On entry the recipient swaps the gene at the matching position
  # in its own chromosome (positional homologous recombination,
  # mirrors `HGT.Channel.Transformation`). No prophage integration.
  defp run_transducing_integration(phage_id, virion, recipient, tick, {ls, ph, children, rng}) do
    case virion.genes do
      [donor_gene | _] ->
        do_transducing_swap(phage_id, donor_gene, recipient, tick, {ls, ph, children, rng})

      _ ->
        {ls, consume_one_virion(ph, phage_id), children, rng}
    end
  end

  defp do_transducing_swap(phage_id, donor_gene, recipient, tick, {ls, ph, children, rng}) do
    chromosome = recipient.genome.chromosome
    n = length(chromosome)

    if n == 0 do
      {ls, consume_one_virion(ph, phage_id), children, rng}
    else
      {idx, rng1} = :rand.uniform_s(n, rng)
      idx = idx - 1

      new_chromosome = List.replace_at(chromosome, idx, donor_gene)

      new_genome =
        Genome.new(new_chromosome,
          plasmids: recipient.genome.plasmids,
          prophages: recipient.genome.prophages
        )

      child_tick = max(tick + 1, recipient.created_at_tick + 1)
      child_abundances = %{ph.name => 5}
      child = Lineage.new_child(recipient, new_genome, child_abundances, child_tick)

      updated_recipient = decrement_abundance(recipient, ph.name, 5)
      new_lineages = replace_lineage(ls, recipient.id, updated_recipient)
      new_phase = consume_one_virion(ph, phage_id)

      {new_lineages, new_phase, [child | children], rng1}
    end
  end

  defp decide_lytic_or_lysogenic(phage_id, virion, recipient, tick, {ls, ph, children, rng}) do
    cassette = build_cassette(virion)
    repressor = cassette.repressor_strength
    p_lytic = max(0.0, min(1.0, @lytic_decision_base * (1.0 - repressor) * 2.0))
    {roll, rng1} = :rand.uniform_s(rng)

    if roll < p_lytic do
      run_immediate_lysis(phage_id, virion, recipient, cassette, tick, {ls, ph, children, rng1})
    else
      run_lysogenic_integration(
        phage_id,
        virion,
        recipient,
        cassette,
        tick,
        {ls, ph, children, rng1}
      )
    end
  end

  defp run_lysogenic_integration(
         phage_id,
         _virion,
         recipient,
         cassette,
         tick,
         {ls, ph, children, rng}
       ) do
    new_genome = Genome.integrate_prophage(recipient.genome, cassette)
    child_tick = max(tick + 1, recipient.created_at_tick + 1)
    child_abundances = %{ph.name => 5}
    child = Lineage.new_child(recipient, new_genome, child_abundances, child_tick)

    updated_recipient = decrement_abundance(recipient, ph.name, 5)
    new_lineages = replace_lineage(ls, recipient.id, updated_recipient)
    new_phase = consume_one_virion(ph, phage_id)

    {new_lineages, new_phase, [child | children], rng}
  end

  defp run_immediate_lysis(phage_id, _virion, recipient, _cassette, tick, {ls, ph, children, rng}) do
    abundance = Lineage.abundance_in(recipient, ph.name)
    lost = max(div(abundance, 2), 1)

    updated_recipient = decrement_abundance(recipient, ph.name, lost)
    new_lineages = replace_lineage(ls, recipient.id, updated_recipient)

    new_phase =
      ph
      |> consume_one_virion(phage_id)
      |> deposit_dna_fragment(recipient, lost, tick)

    {new_lineages, new_phase, children, rng}
  end

  defp build_cassette(%Virion{genes: genes}) do
    %{genes: genes, state: :lysogenic, repressor_strength: 0.5}
  end

  defp receptor_match?(%Virion{surface_signature: nil}, _lineage), do: true

  defp receptor_match?(%Virion{surface_signature: sig}, %Lineage{} = lineage) do
    phenotype = Phenotype.from_genome(lineage.genome)
    sig in receptor_signal_keys(phenotype) or phenotype.surface_tags == []
  end

  # Receptor signal_keys from any `:catalytic_site` co-located with a
  # `:surface_tag(phage_receptor)` are not currently tracked; as a proxy we
  # accept any phage_receptor surface_tag in the phenotype as a valid match
  # gate. Phase 16+ will refine this with co-located signal_key matching.
  defp receptor_signal_keys(_phenotype), do: []

  defp compute_infection_probability(virion_abundance, n_recipient, n_total) do
    denom = max(n_total, 1)
    raw = @p_infect_base * virion_abundance * n_recipient / denom
    raw |> max(0.0) |> min(@p_infect_max)
  end

  defp consume_one_virion(%Phase{phage_pool: pool} = phase, phage_id) do
    case Map.get(pool, phage_id) do
      nil ->
        phase

      %Virion{abundance: 0} ->
        %{phase | phage_pool: Map.delete(pool, phage_id)}

      %Virion{abundance: 1} ->
        %{phase | phage_pool: Map.delete(pool, phage_id)}

      %Virion{} = virion ->
        %{
          phase
          | phage_pool: Map.put(pool, phage_id, %{virion | abundance: virion.abundance - 1})
        }
    end
  end

  defp find_lineage(lineages, id), do: Enum.find(lineages, fn l -> l.id == id end)

  defp replace_lineage(lineages, id, replacement) do
    Enum.map(lineages, fn l -> if l.id == id, do: replacement, else: l end)
  end
end
