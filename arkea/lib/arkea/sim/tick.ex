defmodule Arkea.Sim.Tick do
  @moduledoc """
  Pure tick function for `Arkea.Sim.BiotopeState` (IMPLEMENTATION-PLAN.md §4.1).

  The pipeline mirrors the canonical 6-step order from DESIGN.md Block 11:

    1. `step_metabolism/1`   — stub (Phase 5)
    2. `step_expression/1`   — implemented (Phase 3): genome → phenotype → growth deltas
    3. `step_cell_events/1`  — implemented (Phase 4): growth + stochastic fission
    4. `step_hgt/1`          — stub (Phase 6)
    5. `step_environment/1`  — implemented: dilution of lineage abundances
    6. `step_pruning/1`      — implemented (Phase 4): zero-abundance removal + cap

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
  alias Arkea.Genome.Mutation.Applicator
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Mutator
  alias Arkea.Sim.Phenotype

  @type event :: %{type: atom(), payload: map()}

  @lineage_cap Application.compile_env(:arkea, :lineage_cap, 100)

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
      |> step_expression()
      |> step_cell_events()
      |> step_hgt()
      |> step_environment()
      |> step_pruning()
      |> increment_tick()

    events = derive_events(state, new_state)
    {new_state, events}
  end

  @doc """
  Step 1 — Metabolic balance (stub for Phase 5).

  Will implement proto-FBA and the 13-metabolite pool updates from Block 6.
  For Phase 2, returns state unchanged.
  """
  @spec step_metabolism(BiotopeState.t()) :: BiotopeState.t()
  def step_metabolism(%BiotopeState{} = state), do: state

  @doc """
  Step 2 — Gene expression: derive growth deltas from genome-encoded phenotypes.

  Iterates every lineage in the biotope state, computes an `Arkea.Sim.Phenotype`
  from its genome, and writes a `%{phase_name => integer()}` delta map into
  `growth_delta_by_lineage`. The updated map is consumed by `step_cell_events/1`
  in the same tick.

  ## Growth model (Phase 3)

  For each phase present in the lineage's `abundance_by_phase`:

      delta = round(base_growth_rate * 100) - round(energy_cost * 10)

  This linear model is intentionally simple. Phase 5 will replace it with a
  Michaelis-Menten kinetic model driven by the full metabolite pool.

  Deltas are clamped to `-100..500` to bound burst growth and extinction
  pressure within a single tick.

  ## Lineages with `genome: nil`

  Delta-encoded lineages (Phase 4+) have `genome: nil`. For Phase 3 these
  are passed through without overwriting their existing delta entry — a
  conservative no-op that preserves whatever value was set externally.

  ## Invariants

  - Pure: no I/O, no side effects.
  - Deterministic: same state → same output.
  - Does not modify `lineages` — only updates `growth_delta_by_lineage`.
  """
  @spec step_expression(BiotopeState.t()) :: BiotopeState.t()
  def step_expression(%BiotopeState{lineages: lineages, phases: phases} = state) do
    phase_names = Enum.map(phases, & &1.name)

    new_deltas =
      Map.new(lineages, fn lineage ->
        deltas =
          if lineage.genome != nil do
            phenotype = Phenotype.from_genome(lineage.genome)
            compute_growth_deltas(phenotype, phase_names)
          else
            Map.get(state.growth_delta_by_lineage, lineage.id, %{})
          end

        {lineage.id, deltas}
      end)

    %{state | growth_delta_by_lineage: new_deltas}
  end

  @doc """
  Step 3 — Cell events: growth + stochastic fission (Phase 4).

  First applies growth deltas (as in Phase 3). Then runs the stochastic
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
  Step 4 — Horizontal gene transfer (stub for Phase 6).

  Will implement probabilistic coniugazione/trasduzione/trasformazione between
  lineages in the same biotope per DESIGN.md Block 5.
  For Phase 2, returns state unchanged.
  """
  @spec step_hgt(BiotopeState.t()) :: BiotopeState.t()
  def step_hgt(%BiotopeState{} = state), do: state

  @doc """
  Step 5 — Environmental effects: dilution of lineage abundances.

  For each lineage, multiplies each `abundance_by_phase[phase_name]` entry by
  `(1.0 - rate)`. The rate is looked up from the matching `Phase` in
  `state.phases` by name, falling back to `state.dilution_rate`.

  The float product is `floor`ed to preserve the `non_neg_integer()` type
  contract of `abundance_by_phase`. The result is also clamped to `max(_, 0)`
  for safety against any floating-point underflow edge case.

  **Invariant**: every per-phase abundance after this step is ≤ the value
  before, i.e. dilution is strictly non-increasing (monotonicity).

  Phase 5 will also dilute `Phase.metabolite_pool`, `signal_pool`, and
  `phage_pool` (currently isolated inside `Phase.dilute/1`).
  """
  @spec step_environment(BiotopeState.t()) :: BiotopeState.t()
  def step_environment(%BiotopeState{lineages: lineages, phases: phases} = state) do
    phase_rates = build_phase_rates(phases, state.dilution_rate)

    diluted =
      Enum.map(lineages, fn lineage ->
        new_abundances =
          Map.new(lineage.abundance_by_phase, fn {phase_name, count} ->
            rate = Map.get(phase_rates, phase_name, state.dilution_rate)
            new_count = max(floor(count * (1.0 - rate)), 0)
            {phase_name, new_count}
          end)

        %{lineage | abundance_by_phase: new_abundances, fitness_cache: nil}
      end)

    %{state | lineages: diluted}
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
  """
  @spec derive_events(BiotopeState.t(), BiotopeState.t()) :: [event()]
  def derive_events(%BiotopeState{} = old_state, %BiotopeState{} = new_state) do
    old_ids = MapSet.new(old_state.lineages, & &1.id)
    new_ids = MapSet.new(new_state.lineages, & &1.id)

    born_events =
      new_state.lineages
      |> Enum.filter(fn l -> not MapSet.member?(old_ids, l.id) end)
      |> Enum.map(fn l ->
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

    born_events ++ extinct_events
  end

  # ---------------------------------------------------------------------------
  # Private helpers

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

  # Compute per-phase growth deltas from a phenotype.
  #
  # Linear model (Phase 3):
  #   delta = round(base_growth_rate * 100) - round(energy_cost * 10)
  #
  # Clamped to -100..500. The same delta applies to every phase because Phase 3
  # does not yet differentiate growth by environmental conditions — that is
  # Phase 5 (Michaelis-Menten, metabolite pools per phase).
  defp compute_growth_deltas(%Phenotype{} = phenotype, phase_names) do
    raw_delta =
      round(phenotype.base_growth_rate * 100) - round(phenotype.energy_cost * 10)

    delta = raw_delta |> max(-100) |> min(500)
    Map.new(phase_names, fn name -> {name, delta} end)
  end

  # Return the RNG state, initialising from the biotope id if nil.
  defp get_rng(%BiotopeState{rng_seed: nil, id: id}), do: Mutator.init_seed(id)
  defp get_rng(%BiotopeState{rng_seed: rng}), do: rng

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

  # For one lineage: compute mutation probability, roll the dice, and if
  # successful generate and apply a mutation → child lineage.
  # Returns {parent_lineage_possibly_updated, new_rng, child_or_nil}.
  defp maybe_spawn_child(parent, state, rng, tick) do
    phenotype = Phenotype.from_genome(parent.genome)
    abundance = Lineage.total_abundance(parent)
    prob = Mutator.mutation_probability(abundance, phenotype.repair_efficiency)

    {roll, rng1} = :rand.uniform_s(rng)

    if roll < prob do
      attempt_spawn(parent, state, rng1, tick)
    else
      {parent, rng1, nil}
    end
  end

  # Attempt to generate a mutation and produce a child. On any failure (skip,
  # invalid mutation, applicator error) returns the parent unchanged.
  defp attempt_spawn(parent, state, rng, tick) do
    case Mutator.generate(parent.genome, rng) do
      {:skip, rng1} ->
        {parent, rng1, nil}

      {:ok, mutation, rng1} ->
        case Applicator.apply(parent.genome, mutation) do
          {:error, _} ->
            {parent, rng1, nil}

          {:ok, child_genome} ->
            # Determine the primary phase (first phase by position)
            primary_phase = primary_phase_name(parent, state)

            # Seed the child with a small founder population (5 units) so
            # that it survives the dilution step in the same tick.
            # This is consistent with the lineage model: each lineage
            # represents a sub-population, not a single cell.
            child_abundances = %{primary_phase => 5}
            child = Lineage.new_child(parent, child_genome, child_abundances, tick + 1)

            # Decrement parent abundance in primary phase by 5 (conservation)
            updated_parent = decrement_abundance(parent, primary_phase, 5)

            {updated_parent, rng1, child}
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
