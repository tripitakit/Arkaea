defmodule Arkea.Sim.Tick do
  @moduledoc """
  Pure tick function for `Arkea.Sim.BiotopeState` (IMPLEMENTATION-PLAN.md §4.1).

  The pipeline after Phase 7 has 7 steps:

    1. `step_metabolism/1`   — Phase 5: Michaelis-Menten uptake from phase pools
    2. `step_signaling/1`    — Phase 7: QS signal production into phase signal pools
    3. `step_expression/1`   — Phase 3/7: genome → phenotype → growth deltas (+ QS boost)
    4. `step_cell_events/1`  — Phase 4: growth + stochastic fission
    5. `step_hgt/1`          — Phase 6: conjugation + prophage induction
    6. `step_environment/1`  — Phase 2/5: dilution of lineage abundances and phase pools
    7. `step_pruning/1`      — Phase 4: zero-abundance removal + cap

  ## Discipline

  This module is **strictly pure**. No I/O, no message sends, no PubSub calls,
  no DB access. All side-effects happen in `Arkea.Sim.Biotope.Server`
  **after** the tick returns `{new_state, events}`.

  ## Event type

  Events are `%{type: atom(), payload: map()}`. Phase 4 emits:

    - `%{type: :lineage_born, payload: %{lineage_id: id, parent_id: pid, tick: n}}`
    - `%{type: :lineage_extinct, payload: %{lineage_id: id, tick: n}}`

  ## Growth model (Phase 3)

  `step_expression/1` now derives `growth_delta_by_lineage` from each lineage's
  genome via `Arkea.Sim.Phenotype.from_genome/1`. The linear Phase 3 model:

      delta = round(base_growth_rate * 100) - round(energy_cost * 10)

  `step_cell_events/1` then applies those deltas via `Lineage.apply_growth/2`,
  which clamps results at 0 (DESIGN.md Block 4 invariant: no negative abundance).

  Phase 5 will replace the linear model with Michaelis-Menten kinetics driven
  by per-phase metabolite pools.

  ## Dilution model (Phase 2)

  `step_environment/1` multiplies each `abundance_by_phase[phase_name]` by
  `(1.0 - rate)`, where `rate` is the `dilution_rate` of the matching
  `Phase` in `state.phases`, falling back to `state.dilution_rate` when the
  phase is not found. The float is floored to a non_neg_integer, preserving
  the `abundance_by_phase :: %{atom() => non_neg_integer()}` invariant.
  Dilution is **monotonically decreasing**: abundance after ≤ abundance before.

  ## Stochastic fission (Phase 4)

  `step_cell_events/1` now also runs `spawn_mutants/2` after applying growth
  deltas. For each lineage with a non-nil genome:

    1. Compute the phenotype (Phase 3 path) → `repair_efficiency`.
    2. Compute `mutation_probability(abundance, repair_efficiency)`.
    3. Sample a float from the RNG.
    4. If float < probability: generate a mutation, apply it, create a child
       lineage with `Lineage.new_child/4` and abundance 1 in the lineage's
       primary phase.  The parent's abundance in that phase is decremented by 1
       (abundance conservation).
    5. At most one child per lineage per tick.

  ## Pruning (Phase 4)

  `step_pruning/1` removes lineages with total abundance = 0, then enforces the
  lineage cap (default 100; configurable via `config :arkea, :lineage_cap`).
  When over the cap, the least-abundant lineages are removed first.
  """

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome.Mutation.Applicator
  alias Arkea.Sim.Bacteriocin
  alias Arkea.Sim.Biomass
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.HGT
  alias Arkea.Sim.HGT.Channel.Transformation
  alias Arkea.Sim.HGT.Phage
  alias Arkea.Sim.Intergenic
  alias Arkea.Sim.Metabolism
  alias Arkea.Sim.Mutator
  alias Arkea.Sim.Phenotype
  alias Arkea.Sim.Signaling
  alias Arkea.Sim.Xenobiotic

  @type event :: %{type: atom(), payload: map()}

  @lineage_cap Application.compile_env(:arkea, :lineage_cap, 100)

  # Phase 18 — biofilm dilution discount.
  # Fraction of the per-tick dilution rate that a biofilm-capable
  # lineage avoids. With a 5 % phase dilution and `@biofilm_dilution_relief
  # = 0.5`, a biofilm-capable lineage washes out at 2.5 % per tick
  # while a planktonic neighbour washes out at 5 %. The 50 % discount
  # is at the high end of biological plausibility (some EPS matrices
  # provide near-total residence retention) but matches the
  # qualitative selective pressure we want to surface in Phase 18.
  @biofilm_dilution_relief 0.5

  # Phase 18 — Poisson mixing event probability.
  # At ~10⁻⁴ per tick, a 5-min tick interval gives roughly one
  # mixing event per ~70 hours of wall-clock simulation — rare but
  # non-zero, matching the cadence of natural disturbance regimes
  # (storms, sediment turnover, host re-population) that re-mix
  # microbial spatial structure.
  @mixing_event_probability 1.0e-4

  @doc """
  Run one simulation tick.

  Pure: takes a `BiotopeState.t()`, returns `{new_state, [event()]}`.
  Increments `tick_count` by 1.
  """
  @spec tick(BiotopeState.t()) :: {BiotopeState.t(), [event()]}
  def tick(%BiotopeState{} = state) do
    new_state =
      state
      |> step_metabolism()
      |> step_xenobiotic()
      |> step_biomass()
      |> step_signaling()
      |> step_bacteriocin()
      |> step_expression()
      |> step_cell_events()
      |> step_dna_damage()
      |> step_hgt()
      |> step_phage_infection()
      |> step_environment()
      |> step_lysis()
      |> step_mixing_event()
      |> step_pruning()
      |> increment_tick()

    events = derive_events(state, new_state)
    {new_state, events}
  end

  @doc """
  Step 1 — Metabolic balance: Michaelis-Menten uptake from phase pools (Phase 5).

  For each phase, computes the total substrate uptake across all resident
  lineages using `Arkea.Sim.Metabolism.compute_uptake/3`. The consumed amounts
  are subtracted from `Phase.metabolite_pool` and the per-lineage ATP yield
  index is accumulated in `BiotopeState.atp_yield_by_lineage`.

  ## Pipeline per phase

  1. For each lineage with `abundance > 0` in this phase and a non-nil genome:
     - Derive `substrate_affinities` from the phenotype (atom-keyed, Phase 5).
     - Compute per-lineage uptake via `Metabolism.compute_uptake/3`.
     - Accumulate uptake per metabolite (total consumed from pool by all lineages).
     - Accumulate `atp_yield = Metabolism.atp_yield(uptake)` per lineage.
  2. Reduce the pool: `new_conc = max(conc - total_consumed, 0.0)`.

  ## Discipline

  Pure. No I/O. `atp_yield_by_lineage` is reset at the start of each call,
  so callers always see exactly the yields produced by this tick's chemistry.
  """
  @spec step_metabolism(BiotopeState.t()) :: BiotopeState.t()
  def step_metabolism(%BiotopeState{lineages: lineages, phases: phases} = state) do
    phenotypes =
      Map.new(lineages, fn l ->
        ph = if l.genome != nil, do: Phenotype.from_genome(l.genome), else: nil
        {l.id, ph}
      end)

    {new_phases, atp_yields, uptake_by_lineage} =
      Enum.reduce(phases, {[], %{}, %{}}, fn phase, {acc_phases, acc_yields, acc_uptake} ->
        {updated_phase, phase_yields, phase_uptake} = process_phase(phase, lineages, phenotypes)
        merged_yields = Map.merge(acc_yields, phase_yields, fn _k, a, b -> a + b end)
        merged_uptake = merge_uptake_maps(acc_uptake, phase_uptake)
        {acc_phases ++ [updated_phase], merged_yields, merged_uptake}
      end)

    %{
      state
      | phases: new_phases,
        atp_yield_by_lineage: atp_yields,
        uptake_by_lineage: uptake_by_lineage
    }
  end

  # Merge two `%{lineage_id => %{metabolite => float}}` maps additively.
  defp merge_uptake_maps(left, right) do
    Map.merge(left, right, fn _id, l_map, r_map ->
      Map.merge(l_map, r_map, fn _met, a, b -> a + b end)
    end)
  end

  @doc """
  Step 1.25 — Xenobiotic exposure and degradation (Phase 15 — DESIGN.md Block 8).

  For each phase:

  1. Sums fitness damage across all (drug, lineage) pairs by composing
     `Arkea.Sim.Xenobiotic.survival_factor/3` with the lineage's
     post-toxicity ATP yield. The result feeds back into
     `state.atp_yield_by_lineage` so later steps (biomass, expression)
     read the post-drug budget.
  2. Aggregates hydrolase-driven degradation across all lineages and
     subtracts it from `phase.xenobiotic_pool`. Drug at concentration
     0.0 is removed from the pool entirely.

  The pipeline runs after `step_metabolism/1` so that the toxicity
  factor and ATP yield are already populated; it runs before
  `step_biomass/1` so that biomass progress reflects the drug-adjusted
  budget.

  Pure: no I/O, no message sends.
  """
  @spec step_xenobiotic(BiotopeState.t()) :: BiotopeState.t()
  def step_xenobiotic(%BiotopeState{lineages: lineages, phases: phases} = state) do
    if all_pools_empty?(phases) do
      state
    else
      do_step_xenobiotic(state, lineages, phases)
    end
  end

  defp all_pools_empty?(phases) do
    Enum.all?(phases, fn p -> map_size(p.xenobiotic_pool) == 0 end)
  end

  defp do_step_xenobiotic(state, lineages, phases) do
    phenotypes = build_phenotype_map(lineages)
    primary_phase_for_lineage = primary_phase_index(lineages, phases)

    # 1. Apply binding-driven damage to atp_yield_by_lineage.
    new_yields = apply_drug_damage(state.atp_yield_by_lineage, phenotypes, primary_phase_for_lineage, phases)

    # 2. Aggregate hydrolase-driven degradation per phase.
    new_phases = degrade_phase_pools(phases, lineages, phenotypes)

    %{state | atp_yield_by_lineage: new_yields, phases: new_phases}
  end

  defp primary_phase_index(lineages, phases) do
    phase_names = Enum.map(phases, & &1.name)
    phase_by_name = Map.new(phases, fn p -> {p.name, p} end)

    Map.new(lineages, fn lineage ->
      inhabited =
        Enum.filter(phase_names, fn n -> Map.get(lineage.abundance_by_phase, n, 0) > 0 end)

      name =
        cond do
          inhabited != [] ->
            Enum.max_by(inhabited, fn n -> Map.get(lineage.abundance_by_phase, n, 0) end)

          phase_names != [] ->
            hd(phase_names)

          true ->
            nil
        end

      {lineage.id, Map.get(phase_by_name, name)}
    end)
  end

  defp apply_drug_damage(atp_yields, phenotypes, primary_phase_by_lineage, phases) do
    phase_pools = Map.new(phases, fn p -> {p.name, p.xenobiotic_pool} end)

    Map.new(atp_yields, fn {lineage_id, atp} ->
      phase = Map.get(primary_phase_by_lineage, lineage_id)
      phenotype = Map.get(phenotypes, lineage_id)

      cond do
        phase == nil or phenotype == nil ->
          {lineage_id, atp}

        true ->
          pool = Map.get(phase_pools, phase.name, %{})

          factor =
            Xenobiotic.survival_factor(
              pool,
              phenotype.target_classes,
              phenotype.efflux_capacity
            )

          {lineage_id, atp * factor}
      end
    end)
  end

  defp degrade_phase_pools(phases, lineages, phenotypes) do
    Enum.map(phases, fn phase -> degrade_phase_pool(phase, lineages, phenotypes) end)
  end

  defp degrade_phase_pool(%Phase{xenobiotic_pool: pool} = phase, _lineages, _phenotypes)
       when map_size(pool) == 0,
       do: phase

  defp degrade_phase_pool(%Phase{xenobiotic_pool: pool} = phase, lineages, phenotypes) do
    new_pool =
      Enum.reduce(pool, %{}, fn {xeno_id, conc}, acc ->
        case Xenobiotic.entry(xeno_id) do
          nil ->
            Map.put(acc, xeno_id, conc)

          %{degradable_by_hydrolase: false} ->
            Map.put(acc, xeno_id, conc)

          %{degradable_by_hydrolase: true} ->
            removed = total_degradation(lineages, phenotypes, phase.name, conc)
            new_conc = max(conc - removed, 0.0)

            if new_conc <= 0.0 do
              acc
            else
              Map.put(acc, xeno_id, new_conc)
            end
        end
      end)

    %{phase | xenobiotic_pool: new_pool}
  end

  defp total_degradation(lineages, phenotypes, phase_name, concentration) do
    Enum.reduce(lineages, 0.0, fn lineage, acc ->
      abundance = Lineage.abundance_in(lineage, phase_name)
      phenotype = Map.get(phenotypes, lineage.id)

      if abundance > 0 and phenotype != nil and phenotype.hydrolase_capacity > 0.0 do
        acc +
          Xenobiotic.degradation_amount(concentration, phenotype.hydrolase_capacity, abundance)
      else
        acc
      end
    end)
  end

  @doc """
  Step 1.5 — Biomass progression and decay (Phase 14 — DESIGN.md Block 8).

  Walks every lineage, derives the per-tick biomass delta from its
  primary phase's environment (osmotic stress, toxicity, elemental
  availability) and the metabolic budget produced by `step_metabolism/1`,
  and applies the result to `Lineage.biomass`.

  Lineages with `genome: nil` are skipped (delta-encoded descendants
  inherit the parent biomass and re-evaluate the next time their
  genome is reified).

  Pure: no I/O, no side effects.
  """
  @spec step_biomass(BiotopeState.t()) :: BiotopeState.t()
  def step_biomass(%BiotopeState{lineages: lineages, phases: phases} = state) do
    phase_by_name = Map.new(phases, fn p -> {p.name, p} end)

    new_lineages =
      Enum.map(lineages, fn lineage ->
        update_lineage_biomass(lineage, state, phase_by_name)
      end)

    %{state | lineages: new_lineages}
  end

  defp update_lineage_biomass(%Lineage{genome: nil} = lineage, _state, _phase_by_name),
    do: lineage

  defp update_lineage_biomass(%Lineage{} = lineage, state, phase_by_name) do
    phase_name = primary_phase_name(lineage, state)
    phase = Map.get(phase_by_name, phase_name)

    if phase == nil do
      lineage
    else
      phenotype = Phenotype.from_genome(lineage.genome)
      atp = Map.get(state.atp_yield_by_lineage, lineage.id, 0.0)
      abundance = max(Lineage.abundance_in(lineage, phase_name), 1)

      # Reuse the uptake captured by step_metabolism — the phase pool
      # has already been depleted by consumption, so a fresh
      # `compute_uptake/3` would see a near-empty pool and conclude
      # (incorrectly) that the cell is starved.
      uptake = Map.get(state.uptake_by_lineage, lineage.id, %{})

      tox = Metabolism.toxicity_factor(phase.metabolite_pool, phenotype.detoxify_targets)
      elemental = Metabolism.elemental_factor(uptake, phenotype.substrate_affinities, abundance)

      delta = Biomass.compute_delta(phenotype, atp, elemental, tox, phase)
      new_biomass = Biomass.apply_delta(lineage.biomass, delta)
      %{lineage | biomass: new_biomass}
    end
  end

  @doc """
  Step 1.75 — Bacteriocin warfare (Phase 17 — DESIGN.md Block 8).

  For every phase, accumulates per-producer bacteriocin secretion in
  `Phase.toxin_pool` and applies the resulting wall damage to non-immune
  resident lineages (via `Arkea.Sim.Bacteriocin.step/2`). Producers are
  determined generatively from the genome (a gene with co-occurring
  `:substrate_binding`, `:catalytic_site(:hydrolysis)`, and
  `:transmembrane_anchor`); immunity is conferred by sharing any
  `:surface_tag` with the producer.

  The damage routes through `Lineage.biomass.wall`, so a successful
  bacteriocin attack manifests as wall-deficit-driven lysis in
  `step_lysis/1` later in the same tick. This keeps the lethality
  pathway aligned with the Phase 14 osmotic-shock model and avoids
  introducing a parallel "bacteriocin death" mechanism.

  Pure: no I/O, no message sends.
  """
  @spec step_bacteriocin(BiotopeState.t()) :: BiotopeState.t()
  def step_bacteriocin(%BiotopeState{lineages: lineages, phases: phases} = state) do
    {new_lineages, new_phases} =
      Enum.reduce(phases, {lineages, []}, fn phase, {acc_lineages, acc_phases} ->
        {ls_out, ph_out} = Bacteriocin.step(acc_lineages, phase)
        {ls_out, acc_phases ++ [ph_out]}
      end)

    %{state | lineages: new_lineages, phases: new_phases}
  end

  @doc """
  Step 2 — QS signal production (Phase 7).

  For each phase, for each lineage with non-empty `qs_produces` and abundance > 0
  in that phase, adds signal molecules to `phase.signal_pool`.

  Production rule: for each `{sig_key, rate}` in `phenotype.qs_produces`:
    `amount = rate * abundance / 100.0`
    `signal_pool[sig_key] += amount`

  Signals are not normalised here; they decay naturally in `step_environment/1`
  via `Phase.dilute/1`. This step does not affect lineage abundances or growth
  deltas — it only populates the signal pool so that `step_expression/1` can
  read it.

  Pure. No I/O.
  """
  @spec step_signaling(BiotopeState.t()) :: BiotopeState.t()
  def step_signaling(%BiotopeState{lineages: lineages, phases: phases} = state) do
    phenotypes =
      Map.new(lineages, fn l ->
        ph = if l.genome != nil, do: Phenotype.from_genome(l.genome), else: nil
        {l.id, ph}
      end)

    new_phases = Enum.map(phases, &emit_signals_into_phase(&1, lineages, phenotypes))
    %{state | phases: new_phases}
  end

  @doc """
  Step 3 — Gene expression: derive growth deltas from ATP yield (Phase 5/7).

  Reads `atp_yield_by_lineage` populated by `step_metabolism/1` in the same
  tick and converts each lineage's metabolic power into integer growth deltas.

  ## Growth model (Phase 5/7)

  For each lineage with a non-nil genome:

      qs_boost = Signaling.qs_sigma_boost(phenotype, primary_signal_pool)  # 0.0..1.0
      sigma    = 0.5 + phenotype.dna_binding_affinity + qs_boost            # 0.5..2.5
      net      = (atp_yield - phenotype.energy_cost * 5.0) * sigma
      delta    = round(net) |> max(-200) |> min(500)

  - `atp_yield` — dimensionless ATP index from `step_metabolism/1`. Zero when
    no substrate is available or the lineage lacks substrate-binding domains.
    Zero yield with non-zero energy cost → negative delta → lineage shrinks.
    This is the fundamental selection pressure: no substrate, no growth.
  - `energy_cost * 5.0` — scales the `0.0..5.0` cost field to the same order
    of magnitude as typical atp_yield values (0..50).
  - `dna_binding_affinity` as σ-factor scalar — Phase 5 component.
    A lineage with no `:dna_binding` domains gets sigma = 0.5 (half-speed).
  - `qs_boost` — Phase 7 QS sigma boost from `Signaling.qs_sigma_boost/2`.
    Derived from the primary-phase signal pool after `step_signaling/1`.
    Adds 0.0..1.0 to sigma: `sigma = 0.5 + dna_binding_affinity + qs_boost`.
  - Delta clamped to `-200..500` to bound extinction and burst growth.

  ## Lineages with `genome: nil`

  Preserved unchanged (delta-encoded descendants keep their prior delta).

  ## Invariants

  - Pure: no I/O, no side effects.
  - Deterministic: same state → same output.
  - Does not modify `lineages` — only updates `growth_delta_by_lineage`.
  """
  @spec step_expression(BiotopeState.t()) :: BiotopeState.t()
  def step_expression(
        %BiotopeState{
          lineages: lineages,
          phases: phases,
          atp_yield_by_lineage: yields
        } = state
      ) do
    phase_names = Enum.map(phases, & &1.name)
    phase_by_name = Map.new(phases, fn p -> {p.name, p} end)

    new_deltas =
      Map.new(lineages, fn lineage ->
        deltas =
          if lineage.genome != nil do
            phenotype = Phenotype.from_genome(lineage.genome)
            atp = Map.get(yields, lineage.id, 0.0)
            signal_pool = primary_phase_signal_pool(lineage, phase_names, phase_by_name)
            compute_growth_deltas_v5(phenotype, atp, phase_names, lineage.genome, signal_pool)
          else
            Map.get(state.growth_delta_by_lineage, lineage.id, %{})
          end

        {lineage.id, deltas}
      end)

    %{state | growth_delta_by_lineage: new_deltas}
  end

  @doc """
  Step 4 — Cell events: growth + stochastic fission (Phase 4).

  First applies growth deltas from `step_expression/1`. Then runs the stochastic
  fission pipeline (`spawn_mutants/2`) which may add new child lineages.
  Updates `state.rng_seed` with the advanced RNG state.

  Lineages with `genome: nil` are skipped by fission (no genome to mutate).
  At most one child lineage is created per parent per tick.
  """
  @spec step_cell_events(BiotopeState.t()) :: BiotopeState.t()
  def step_cell_events(%BiotopeState{lineages: lineages, growth_delta_by_lineage: deltas} = state) do
    # Apply growth deltas first
    grown =
      Enum.map(lineages, fn lineage ->
        delta = Map.get(deltas, lineage.id, %{})
        Lineage.apply_growth(lineage, delta)
      end)

    state_after_growth = %{state | lineages: grown}

    # Stochastic fission: may produce new child lineages
    rng = get_rng(state_after_growth)
    {updated_lineages, new_rng} = spawn_mutants(state_after_growth, rng)

    %{state_after_growth | lineages: updated_lineages, rng_seed: new_rng}
  end

  @doc """
  Step 4 — Horizontal gene transfer (Phase 6).

  Runs two HGT sub-steps in sequence:

  1. **Conjugation** (`HGT.step/4`) — for each phase, stochastically transfers
     conjugative plasmids from donor lineages to recipient lineages. New
     transconjugant lineages are appended; recipient abundances are decremented
     by 1 to conserve population (DESIGN.md Block 5).

  2. **Prophage induction** (`HGT.induction_step/4`) — for each lineage
     carrying integrated prophages, rolls a stress-driven lytic burst that
     reduces abundance by 50% on induction.

  Pure: reads and updates `state.rng_seed`; no I/O, no messages.
  """
  @spec step_hgt(BiotopeState.t()) :: BiotopeState.t()
  def step_hgt(%BiotopeState{lineages: lineages, phases: phases, tick_count: tick} = state) do
    rng = get_rng(state)

    # Step 4a: conjugation — run per phase, accumulate new child lineages
    {conjugated_lineages, new_children, rng1} =
      Enum.reduce(phases, {lineages, [], rng}, fn phase, {acc_lineages, acc_children, acc_rng} ->
        {updated, children, next_rng} = HGT.step(phase.name, acc_lineages, tick, acc_rng)
        {updated, acc_children ++ children, next_rng}
      end)

    all_lineages = conjugated_lineages ++ new_children

    # Step 4b: natural transformation (Phase 13) — competent recipients
    # take up DNA fragments from the phase dna_pool, gated by R-M, with
    # positional homologous recombination producing transformant children.
    {transformed_lineages, phases_after_transformation, transformant_children, rng2} =
      run_transformation(all_lineages, phases, tick, rng1)

    lineages_after_transformation = transformed_lineages ++ transformant_children

    # Step 4c: prophage induction — stress-triggered lytic burst that
    # produces free virions in `phase.phage_pool` and DNA fragments in
    # `phase.dna_pool`. Phase 12: also drops the lysed cassette from the
    # host genome (Phage.lytic_burst).
    phenotypes = build_phenotype_map(lineages_after_transformation)

    {induced_lineages, induced_phases, rng3} =
      HGT.induction_step(
        lineages_after_transformation,
        phases_after_transformation,
        state.atp_yield_by_lineage,
        phenotypes,
        tick,
        rng2
      )

    %{state | lineages: induced_lineages, phases: induced_phases, rng_seed: rng3}
  end

  # Run natural transformation for every phase, threading lineages and
  # phases through the per-phase channel and returning the aggregate
  # transformant children alongside the updated phase list.
  defp run_transformation(lineages, phases, tick, rng) do
    Enum.reduce(phases, {lineages, [], [], rng}, fn phase,
                                                    {acc_lineages, acc_phases, acc_children,
                                                     acc_rng} ->
      {ls_out, p_out, children, rng_out} =
        Transformation.step(acc_lineages, phase, tick, acc_rng)

      {ls_out, acc_phases ++ [p_out], acc_children ++ children, rng_out}
    end)
  end

  @doc """
  Step 5 — Phage infection (Phase 12 — DESIGN.md Block 8).

  For each phase, runs `Arkea.Sim.HGT.Phage.infection_step/4`: every free
  virion in the phage_pool attempts to infect any compatible recipient
  lineage in the same phase. The pipeline gates each entry through
  receptor matching, `HGT.Defense.restriction_check_virion/3`, and a
  lytic-vs-lysogenic decision derived from the cassette
  `repressor_strength`. Successful lysogenic integrations append a
  freshly generated child lineage; immediate lytic events shrink the
  recipient and append a chromosomal fragment to `phase.dna_pool`.

  Pure: reads and updates `state.rng_seed`; no I/O, no messages.
  """
  @spec step_phage_infection(BiotopeState.t()) :: BiotopeState.t()
  def step_phage_infection(
        %BiotopeState{lineages: lineages, phases: phases, tick_count: tick} = state
      ) do
    rng = get_rng(state)

    {updated_lineages, updated_phases, all_children, rng_out} =
      Enum.reduce(phases, {lineages, [], [], rng}, fn phase,
                                                      {acc_lineages, acc_phases, acc_children,
                                                       acc_rng} ->
        {ls_out, p_out, children, rng_out} =
          Phage.infection_step(acc_lineages, phase, tick, acc_rng)

        {ls_out, acc_phases ++ [p_out], acc_children ++ children, rng_out}
      end)

    %{
      state
      | lineages: updated_lineages ++ all_children,
        phases: updated_phases,
        rng_seed: rng_out
    }
  end

  @doc """
  Step 5 — Environmental effects: dilution of lineage abundances and phase pools.

  Phase 5 additions (beyond Phase 2 lineage dilution):

  1. **Phase pool dilution**: calls `Phase.dilute/1` on every phase, which
     applies the phase's `dilution_rate` to `metabolite_pool`, `signal_pool`,
     and `phage_pool`. This models the chemostat washout of dissolved substrates.

  2. **Metabolite inflow**: after dilution, adds `state.metabolite_inflow` to
     each phase's `metabolite_pool`. Inflow models continuous replenishment
     (fresh medium entering the chemostat). An empty `metabolite_inflow` map
     (the default) is a no-op.

  ## Lineage dilution (unchanged from Phase 2)

  For each lineage, multiplies each `abundance_by_phase[phase_name]` entry by
  `(1.0 - rate)`. The result is `floor`ed and clamped to `max(_, 0)` to
  preserve the `non_neg_integer()` type contract.

  **Invariant**: lineage abundances after this step are ≤ their values before
  (monotonic decrease from dilution). Phase metabolite concentrations are also
  ≤ pre-dilution values before inflow is applied.
  """
  @spec step_environment(BiotopeState.t()) :: BiotopeState.t()
  def step_environment(
        %BiotopeState{lineages: lineages, phases: phases, metabolite_inflow: inflow} = state
      ) do
    phase_rates = build_phase_rates(phases, state.dilution_rate)

    # Dilute lineage abundances. Phase 18: biofilm-capable lineages
    # enjoy a per-tick dilution discount (`@biofilm_dilution_relief`)
    # — the EPS matrix anchors cells to surfaces and shields them
    # from chemostat washout.
    diluted_lineages =
      Enum.map(lineages, fn lineage ->
        biofilm_relief =
          if lineage.genome != nil and Phenotype.from_genome(lineage.genome).biofilm_capable? do
            @biofilm_dilution_relief
          else
            0.0
          end

        new_abundances =
          Map.new(lineage.abundance_by_phase, fn {phase_name, count} ->
            base_rate = Map.get(phase_rates, phase_name, state.dilution_rate)
            effective_rate = max(base_rate * (1.0 - biofilm_relief), 0.0)
            new_count = max(floor(count * (1.0 - effective_rate)), 0)
            {phase_name, new_count}
          end)

        %{lineage | abundance_by_phase: new_abundances, fitness_cache: nil}
      end)

    # Phase 5: dilute phase pools, then replenish via inflow
    # Phase 12: free virions also age and undergo R-M-independent decay
    # (Phage.decay_step) on top of dilution.
    diluted_phases =
      phases
      |> Enum.map(&Phase.dilute/1)
      |> Enum.map(&Phage.decay_step/1)

    replenished_phases = apply_inflow(diluted_phases, inflow)

    %{state | lineages: diluted_lineages, phases: replenished_phases}
  end

  @doc """
  Step 4.5 — DNA-damage accumulation and decay (Phase 17 — DESIGN.md Block 8 SOS).

  For every lineage with a non-`nil` genome, advance `dna_damage` by

      Δdamage = µ_baseline × replications_this_tick × (1 - repair_efficiency)

  scaled up by `1.5` when SOS is already active (DinB-like
  self-amplification), then apply a fixed per-tick decay
  `@dna_damage_decay`. The result is clamped into
  `0..Lineage.dna_damage_max/0`.

  `replications_this_tick` is approximated by the population gain in
  the lineage's primary phase (positive `growth_delta`) clamped at
  the current abundance; negative growth contributes zero damage. This
  collapses several real-world repair-vs-replication kinetics into a
  single forward-Euler step that is sufficient to surface the
  qualitative phenomenon: high-µ low-repair lineages slide into SOS
  faster than wild-types and trigger their resident prophages.

  Pure: no I/O, no message sends.
  """
  @spec step_dna_damage(BiotopeState.t()) :: BiotopeState.t()
  def step_dna_damage(%BiotopeState{lineages: lineages} = state) do
    deltas = state.growth_delta_by_lineage

    new_lineages =
      Enum.map(lineages, fn lineage ->
        update_lineage_dna_damage(lineage, deltas)
      end)

    %{state | lineages: new_lineages}
  end

  defp update_lineage_dna_damage(%Lineage{genome: nil} = lineage, _deltas), do: lineage

  defp update_lineage_dna_damage(%Lineage{} = lineage, deltas) do
    phenotype = Phenotype.from_genome(lineage.genome)
    delta_map = Map.get(deltas, lineage.id, %{})
    replications = positive_growth_total(delta_map)
    abundance = Lineage.total_abundance(lineage)

    increment =
      Mutator.dna_damage_increment(
        phenotype.repair_efficiency,
        replications,
        abundance,
        lineage.dna_damage
      )

    decayed = Mutator.decay_damage(lineage.dna_damage + increment)
    clamped = decayed |> max(0.0) |> min(Lineage.dna_damage_max())
    %{lineage | dna_damage: clamped}
  end

  defp positive_growth_total(delta_map) when is_map(delta_map) do
    Enum.reduce(delta_map, 0, fn {_phase, delta}, acc ->
      if is_integer(delta) and delta > 0, do: acc + delta, else: acc
    end)
  end

  @doc """
  Step 5.5 — Lysis on biomass deficit (Phase 14 — DESIGN.md Block 8.B.4).

  For each lineage, rolls a Bernoulli trial per phase against the
  lysis probability derived from the lineage's biomass profile (see
  `Arkea.Sim.Biomass.lysis_probability/1`). On a hit the lineage
  abundance in that phase is reduced by `floor(abundance × p)` —
  a population-level analogue of fractional lysis.

  Lysis is *not* an extinction event by itself; it is a continuous
  selection pressure. Lineages with intact biomass roll p ≈ 0 and are
  unaffected. Lineages whose biomass collapses can lose half or more
  of their abundance per tick.

  Pure: reads/updates `state.rng_seed`.
  """
  @spec step_lysis(BiotopeState.t()) :: BiotopeState.t()
  def step_lysis(%BiotopeState{lineages: lineages} = state) do
    rng = get_rng(state)

    {new_lineages, rng_out} =
      Enum.map_reduce(lineages, rng, fn lineage, acc_rng ->
        maybe_lyse(lineage, acc_rng)
      end)

    %{state | lineages: new_lineages, rng_seed: rng_out}
  end

  defp maybe_lyse(%Lineage{genome: nil} = lineage, rng), do: {lineage, rng}

  defp maybe_lyse(%Lineage{} = lineage, rng) do
    p = Biomass.lysis_probability(lineage.biomass)

    if p <= 0.0 do
      {lineage, rng}
    else
      {roll, rng1} = :rand.uniform_s(rng)

      if roll >= p do
        {lineage, rng1}
      else
        {apply_lysis(lineage, p), rng1}
      end
    end
  end

  defp apply_lysis(%Lineage{abundance_by_phase: abundances} = lineage, p) do
    new_abundances =
      Map.new(abundances, fn {phase_name, count} ->
        lost = floor(count * p)
        {phase_name, max(count - lost, 0)}
      end)

    %{lineage | abundance_by_phase: new_abundances, fitness_cache: nil}
  end

  @doc """
  Step 5.75 — Poisson mixing event (Phase 18 — DESIGN.md Block 8).

  Each tick rolls a Bernoulli trial against `@mixing_event_probability`.
  On a hit, the biotope's lineages and phase pools are *homogenised*
  across phases — the analogue of a storm, sediment turnover, or
  host bowel mixing event that erases spatial structure within a
  biotope. The redistribution reuses the same mathematical model as
  the player-triggered `:mixing_event` intervention.

  No-op when the biotope has fewer than 2 phases (mixing has no
  meaning) or when the trial misses. Pure: reads/updates
  `state.rng_seed`.
  """
  @spec step_mixing_event(BiotopeState.t()) :: BiotopeState.t()
  def step_mixing_event(%BiotopeState{phases: phases} = state) when length(phases) < 2,
    do: state

  def step_mixing_event(%BiotopeState{} = state) do
    rng = get_rng(state)
    {roll, rng_out} = :rand.uniform_s(rng)

    if roll >= @mixing_event_probability do
      %{state | rng_seed: rng_out}
    else
      apply_natural_mixing(%{state | rng_seed: rng_out})
    end
  end

  # Homogenise lineage abundances and phase pools across all phases —
  # analogue of `Arkea.Sim.Intervention.homogenize_phase_pools/1` but
  # entirely in-process (we cannot call `Intervention.apply/2` here
  # because the natural Poisson trigger has no actor / payload
  # context).
  defp apply_natural_mixing(%BiotopeState{lineages: lineages, phases: phases} = state) do
    redistributed_lineages = Enum.map(lineages, &redistribute_lineage_uniformly(&1, phases))
    homogenised_phases = homogenise_phase_pools(phases)
    %{state | lineages: redistributed_lineages, phases: homogenised_phases}
  end

  defp redistribute_lineage_uniformly(%Lineage{abundance_by_phase: ab} = lineage, phases) do
    phase_names = Enum.map(phases, & &1.name)
    total = Enum.sum(Map.values(ab))
    n_phases = length(phase_names)

    if n_phases == 0 or total == 0 do
      lineage
    else
      base = div(total, n_phases)
      remainder = rem(total, n_phases)

      new_abundance =
        phase_names
        |> Enum.with_index()
        |> Map.new(fn {name, idx} ->
          extra = if idx < remainder, do: 1, else: 0
          {name, base + extra}
        end)

      %{lineage | abundance_by_phase: new_abundance, fitness_cache: nil}
    end
  end

  defp homogenise_phase_pools(phases) do
    metabolite_mean = mean_pool(phases, & &1.metabolite_pool)
    signal_mean = mean_pool(phases, & &1.signal_pool)

    Enum.map(phases, fn phase ->
      %{phase | metabolite_pool: metabolite_mean, signal_pool: signal_mean}
    end)
  end

  defp mean_pool(phases, accessor) do
    keys =
      phases
      |> Enum.flat_map(fn p -> p |> accessor.() |> Map.keys() end)
      |> Enum.uniq()

    divisor = max(length(phases), 1)

    Map.new(keys, fn key ->
      total = Enum.sum(Enum.map(phases, fn p -> Map.get(accessor.(p), key, 0.0) end))
      {key, total / divisor}
    end)
  end

  @doc """
  Step 6 — Pruning: remove extinct lineages and enforce the lineage cap.

  Phase 4 implementation:

    1. Remove all lineages with `Lineage.total_abundance/1 == 0`.
    2. If `length(lineages) > @lineage_cap`, sort by total_abundance ascending
       and discard the least-abundant until the list is exactly `@lineage_cap`.

  The cap is configurable via `config :arkea, :lineage_cap` (default 100).
  """
  @spec step_pruning(BiotopeState.t()) :: BiotopeState.t()
  def step_pruning(%BiotopeState{lineages: lineages} = state) do
    # Step 1: remove zero-abundance lineages
    survivors = Enum.filter(lineages, fn l -> Lineage.total_abundance(l) > 0 end)

    # Step 2: enforce cap
    capped =
      if length(survivors) > @lineage_cap do
        survivors
        |> Enum.sort_by(&Lineage.total_abundance/1, :desc)
        |> Enum.take(@lineage_cap)
      else
        survivors
      end

    %{state | lineages: capped}
  end

  @doc """
  Derive typed events from the old and new states.

  Phase 4 returns:

    - `:lineage_born` for every lineage id present in `new_state` but absent
      from `old_state`.
    - `:lineage_extinct` for every lineage id present in `old_state` but absent
      from `new_state`.

  Phase 6 adds:

    - `:hgt_transfer` for every new lineage whose parent carried fewer plasmids,
      indicating a successful conjugation event (transconjugant detected).
  """
  @spec derive_events(BiotopeState.t(), BiotopeState.t()) :: [event()]
  def derive_events(%BiotopeState{} = old_state, %BiotopeState{} = new_state) do
    old_ids = MapSet.new(old_state.lineages, & &1.id)
    new_ids = MapSet.new(new_state.lineages, & &1.id)
    old_by_id = Map.new(old_state.lineages, fn l -> {l.id, l} end)

    born_lineages =
      Enum.filter(new_state.lineages, fn l -> not MapSet.member?(old_ids, l.id) end)

    born_events =
      Enum.map(born_lineages, fn l ->
        %{
          type: :lineage_born,
          payload: %{
            lineage_id: l.id,
            parent_id: l.parent_id,
            tick: new_state.tick_count
          }
        }
      end)

    extinct_events =
      old_state.lineages
      |> Enum.filter(fn l -> not MapSet.member?(new_ids, l.id) end)
      |> Enum.map(fn l ->
        %{
          type: :lineage_extinct,
          payload: %{lineage_id: l.id, tick: new_state.tick_count}
        }
      end)

    hgt_events =
      Enum.flat_map(born_lineages, fn l ->
        detect_hgt_transfer(l, old_by_id, new_state.tick_count)
      end)

    born_events ++ extinct_events ++ hgt_events
  end

  # ---------------------------------------------------------------------------
  # Private helpers

  # Emit a :hgt_transfer event if the new lineage gained plasmids vs its parent.
  defp detect_hgt_transfer(%{parent_id: nil}, _old_by_id, _tick), do: []
  defp detect_hgt_transfer(%{genome: nil}, _old_by_id, _tick), do: []

  defp detect_hgt_transfer(new_l, old_by_id, tick) do
    gain = plasmid_count_gain(new_l.genome, Map.get(old_by_id, new_l.parent_id))

    if gain > 0 do
      [
        %{
          type: :hgt_transfer,
          payload: %{
            lineage_id: new_l.id,
            parent_id: new_l.parent_id,
            plasmids_gained: gain,
            tick: tick
          }
        }
      ]
    else
      []
    end
  end

  defp plasmid_count_gain(_genome, nil), do: 0

  defp plasmid_count_gain(new_genome, parent) do
    parent_count = if parent.genome != nil, do: length(parent.genome.plasmids), else: 0
    max(length(new_genome.plasmids) - parent_count, 0)
  end

  defp increment_tick(%BiotopeState{tick_count: n} = state) do
    %{state | tick_count: n + 1}
  end

  # Build phase_name => dilution_rate map for O(1) lookup during dilution.
  defp build_phase_rates(phases, fallback) do
    Map.new(phases, fn phase ->
      rate = if phase.dilution_rate > 0.0, do: phase.dilution_rate, else: fallback
      {phase.name, rate}
    end)
  end

  # Phase 5/6/7 growth model: ATP-driven deltas with σ-factor scalar + QS boost + plasmid burden.
  #
  # sigma = 0.5 + dna_binding_affinity + qs_boost  (0.5..2.5 before intergenic modifiers)
  # qs_boost = Signaling.qs_sigma_boost(phenotype, signal_pool)  → 0.0..1.0
  # net   = (atp_yield - energy_cost * 5.0) * sigma
  #
  # Phase 6 plasmid replication burden:
  #   plasmid_gene_count = total genes across all plasmids
  #   plasmid_burden     = plasmid_gene_count * 0.3 ATP per tick
  #   net_adjusted       = net - plasmid_burden
  #
  # delta = round(net_adjusted) clamped to -200..500
  #
  # When atp_yield == 0.0 (no substrate), net is negative proportional to
  # energy_cost — the lineage shrinks under metabolic burden without gain.
  # Plasmid-carrying lineages face additional burden (San Millán & MacLean 2018).
  # The QS boost rewards coordinated signalling: lineages that receive matching
  # signals get a higher sigma, amplifying their growth response to ATP yield.
  #
  # Intergenic runtime semantics:
  # - `sigma_promoter` adds a modest basal sigma bonus
  # - `multi_sigma_operator` amplifies QS-derived sigma boosts
  # - `metabolite_riboswitch` relieves part of the ATP burden during starvation
  defp compute_growth_deltas_v5(
         %Phenotype{} = phenotype,
         atp_yield,
         phase_names,
         genome,
         signal_pool
       ) do
    expression_mods = Intergenic.expression_modifiers(genome, atp_yield, phenotype.energy_cost)
    qs_boost = Signaling.qs_sigma_boost(phenotype, signal_pool) * expression_mods.qs_multiplier
    sigma = 0.5 + phenotype.dna_binding_affinity + expression_mods.sigma_bonus + qs_boost

    net =
      (atp_yield - phenotype.energy_cost * 5.0 + expression_mods.energy_relief) * sigma

    # Phase 16: plasmid replication cost scales with copy_number.
    # Burden = Σ (genes × copy_number × 0.3 ATP/gene/copy/tick).
    # High-copy plasmids amplify the burden; the gene-dosage benefit
    # (also proportional to copy_number) lives elsewhere — Phase 17
    # will couple it through `:catalytic_site` kcat scaling.
    plasmid_burden =
      Enum.sum_by(genome.plasmids, fn plasmid ->
        length(plasmid.genes) * plasmid.copy_number * 0.3
      end)

    net_adjusted = net - plasmid_burden
    delta = round(net_adjusted) |> max(-200) |> min(500)
    Map.new(phase_names, fn name -> {name, delta} end)
  end

  # Accumulate signal contributions from all lineages into one phase's signal_pool.
  defp emit_signals_into_phase(phase, lineages, phenotypes) do
    new_pool =
      Enum.reduce(lineages, phase.signal_pool, fn lineage, pool ->
        emit_lineage_signals(lineage, phase.name, phenotypes, pool)
      end)

    %{phase | signal_pool: new_pool}
  end

  # Emit signal contributions for one lineage into the pool (or return pool unchanged).
  defp emit_lineage_signals(lineage, phase_name, phenotypes, pool) do
    abundance = Lineage.abundance_in(lineage, phase_name)
    phenotype = Map.get(phenotypes, lineage.id)

    if abundance > 0 and phenotype != nil and phenotype.qs_produces != [] do
      Signaling.produce_signals(phenotype, abundance, pool)
    else
      pool
    end
  end

  # Return the signal_pool of the primary phase for a lineage.
  # Primary phase = the phase with the highest abundance for this lineage,
  # constrained to phases present in the state. Falls back to %{} if none found.
  defp primary_phase_signal_pool(lineage, phase_names, phase_by_name) do
    inhabited =
      Enum.filter(phase_names, fn name ->
        Map.get(lineage.abundance_by_phase, name, 0) > 0
      end)

    primary_name =
      if inhabited != [] do
        Enum.max_by(inhabited, fn name -> Map.get(lineage.abundance_by_phase, name, 0) end)
      else
        List.first(phase_names)
      end

    case Map.get(phase_by_name, primary_name) do
      nil -> %{}
      phase -> phase.signal_pool
    end
  end

  # Process one phase: compute per-lineage uptake, reduce the metabolite pool,
  # and accumulate ATP yields per lineage.
  # Returns {updated_phase, %{lineage_id => atp_yield_float}}.
  defp process_phase(%Phase{} = phase, lineages, phenotypes) do
    {total_consumed, phase_yields, phase_uptake} =
      Enum.reduce(lineages, {%{}, %{}, %{}}, fn lineage, acc ->
        accumulate_lineage_uptake(lineage, phase, phenotypes, acc)
      end)

    # Phase 18: cross-feeding closure. Each unit of substrate
    # consumed releases stoichiometric by-products into the same
    # phase pool — the C/N/S/Fe/H₂ cycles close emergently when one
    # lineage's by-product is another's substrate. The release happens
    # *after* consumption so the donor can't immediately re-uptake
    # its own waste.
    byproducts = Metabolism.compute_byproducts(total_consumed)

    new_pool =
      phase.metabolite_pool
      |> Map.merge(total_consumed, fn _k, conc, consumed -> max(conc - consumed, 0.0) end)
      |> Map.merge(byproducts, fn _k, conc, produced -> conc + produced end)

    {%{phase | metabolite_pool: new_pool}, phase_yields, phase_uptake}
  end

  # Accumulate one lineage's metabolite uptake and ATP yield into the running
  # totals for a phase. Returns {updated_total_consumed, updated_phase_yields}.
  defp accumulate_lineage_uptake(lineage, phase, phenotypes, {acc_consumed, acc_yields, acc_uptake}) do
    abundance = Map.get(lineage.abundance_by_phase, phase.name, 0)
    phenotype = Map.get(phenotypes, lineage.id)

    if abundance > 0 and phenotype != nil and map_size(phenotype.substrate_affinities) > 0 do
      uptake =
        Metabolism.compute_uptake(
          phenotype.substrate_affinities,
          phase.metabolite_pool,
          abundance
        )

      # Phase 14: scale ATP yield by metabolite-toxicity survival
      # (catalase-like activities bypass per-target). Elemental
      # availability gates *biosynthesis* (Biomass.compute_delta), not
      # respiration: a P-limited cell can still oxidise its substrate,
      # it just cannot replicate DNA.
      tox = Metabolism.toxicity_factor(phase.metabolite_pool, phenotype.detoxify_targets)
      atp = Metabolism.atp_yield(uptake) * tox

      new_consumed = Map.merge(acc_consumed, uptake, fn _k, total, more -> total + more end)
      new_yields = Map.update(acc_yields, lineage.id, atp, fn prev -> prev + atp end)
      new_uptake = Map.update(acc_uptake, lineage.id, uptake, fn prev_uptake ->
        Map.merge(prev_uptake, uptake, fn _met, a, b -> a + b end)
      end)
      {new_consumed, new_yields, new_uptake}
    else
      {acc_consumed, acc_yields, acc_uptake}
    end
  end

  # Apply metabolite inflow to all phases after dilution.
  # Inflow keys that are absent from a phase's pool are added from zero.
  # No-op when inflow is the empty map.
  defp apply_inflow(phases, inflow) when map_size(inflow) == 0, do: phases

  defp apply_inflow(phases, inflow) do
    Enum.map(phases, fn phase ->
      new_pool =
        Map.merge(phase.metabolite_pool, inflow, fn _k, conc, delta -> conc + delta end)

      %{phase | metabolite_pool: new_pool}
    end)
  end

  # Return the RNG state, initialising from the biotope id if nil.
  defp get_rng(%BiotopeState{rng_seed: nil, id: id}), do: Mutator.init_seed(id)
  defp get_rng(%BiotopeState{rng_seed: rng}), do: rng

  # Build a %{lineage_id => Phenotype.t() | nil} map for all lineages.
  # Used by step_hgt/1 to compute prophage induction stress.
  defp build_phenotype_map(lineages) do
    Map.new(lineages, fn l ->
      ph = if l.genome != nil, do: Phenotype.from_genome(l.genome), else: nil
      {l.id, ph}
    end)
  end

  # Stochastic fission: for each lineage with genome != nil, maybe produce a
  # child mutant. Returns {updated_lineages, new_rng}.
  defp spawn_mutants(%BiotopeState{lineages: lineages, tick_count: tick} = state, rng) do
    {updated_lineages, new_rng, new_children} =
      Enum.reduce(lineages, {[], rng, []}, &reduce_spawn(&1, &2, state, tick))

    final_lineages = Enum.reverse(updated_lineages) ++ Enum.reverse(new_children)
    {final_lineages, new_rng}
  end

  defp reduce_spawn(lineage, {acc_lineages, acc_rng, acc_children}, state, tick) do
    if lineage.genome == nil do
      {[lineage | acc_lineages], acc_rng, acc_children}
    else
      {lineage_out, acc_rng2, maybe_child} = maybe_spawn_child(lineage, state, acc_rng, tick)
      children = if maybe_child, do: [maybe_child | acc_children], else: acc_children
      {[lineage_out | acc_lineages], acc_rng2, children}
    end
  end

  # For one lineage: compute SOS-aware mutation probability, roll the
  # dice, and if successful generate and apply a mutation → child lineage.
  # Returns {parent_lineage_possibly_updated, new_rng, child_or_nil}.
  defp maybe_spawn_child(parent, state, rng, tick) do
    phenotype = Phenotype.from_genome(parent.genome)
    abundance = Lineage.total_abundance(parent)

    prob =
      Mutator.mutation_probability(abundance, phenotype.repair_efficiency, parent.dna_damage)

    {roll, rng1} = :rand.uniform_s(rng)

    if roll < prob do
      attempt_spawn(parent, phenotype, state, rng1, tick)
    else
      {parent, rng1, nil}
    end
  end

  # Attempt to generate a mutation and produce a child. On any failure (skip,
  # invalid mutation, applicator error) returns the parent unchanged. Phase 17
  # error-catastrophe gate: when the per-cell mutation rate × genome size
  # exceeds the Eigen threshold, the offspring carries one or more lethal
  # mutations and never gets seeded — only the parent decrement happens.
  defp attempt_spawn(parent, phenotype, state, rng, tick) do
    case Mutator.generate(parent.genome, rng) do
      {:skip, rng1} ->
        {parent, rng1, nil}

      {:ok, mutation, rng1} ->
        case Applicator.apply(parent.genome, mutation) do
          {:error, _} ->
            {parent, rng1, nil}

          {:ok, child_genome} ->
            mu_per_cell =
              0.01 *
                (1.0 - phenotype.repair_efficiency) *
                if(Mutator.sos_active?(parent.dna_damage), do: Mutator.sos_mutation_amplifier(),
                   else: 1.0)

            genome_size = max(child_genome.gene_count, 1)
            p_lethal = Mutator.error_catastrophe_lethality(mu_per_cell, genome_size)

            # Skip the RNG consumption when p_lethal is exactly zero
            # (no catastrophe possible) so that the deterministic
            # simulation traces of low-mutator scenarios — including
            # the canary `cronache_test.exs` — keep their RNG path
            # stable. Only the high-µ × large-genome corner pays the
            # extra roll.
            {lethal?, rng2} =
              if p_lethal == 0.0 do
                {false, rng1}
              else
                {roll, rng_next} = :rand.uniform_s(rng1)
                {roll < p_lethal, rng_next}
              end

            primary_phase = primary_phase_name(parent, state)

            if lethal? do
              # Error-catastrophe: child is non-vital, parent still
              # invests the replication cost (5 cell-equivalents).
              updated_parent = decrement_abundance(parent, primary_phase, 5)
              {updated_parent, rng2, nil}
            else
              child_abundances = %{primary_phase => 5}
              child = Lineage.new_child(parent, child_genome, child_abundances, tick + 1)
              updated_parent = decrement_abundance(parent, primary_phase, 5)
              {updated_parent, rng2, child}
            end
        end
    end
  end

  # Find the primary phase name for a lineage: the phase with the highest
  # abundance (tiebreak: first phase in state.phases list).
  defp primary_phase_name(lineage, state) do
    phase_names = Enum.map(state.phases, & &1.name)

    # Prefer phases that the lineage actually inhabits
    inhabited =
      Enum.filter(phase_names, fn name ->
        Map.get(lineage.abundance_by_phase, name, 0) > 0
      end)

    if inhabited != [] do
      Enum.max_by(inhabited, fn name ->
        Map.get(lineage.abundance_by_phase, name, 0)
      end)
    else
      # Lineage has no abundance in any known phase; use first phase name
      hd(phase_names)
    end
  end

  # Decrement abundance in a phase by `amount`, clamped at 0.
  defp decrement_abundance(lineage, phase_name, amount) do
    current = Map.get(lineage.abundance_by_phase, phase_name, 0)
    new_count = max(current - amount, 0)
    new_abundances = Map.put(lineage.abundance_by_phase, phase_name, new_count)
    %{lineage | abundance_by_phase: new_abundances}
  end
end
