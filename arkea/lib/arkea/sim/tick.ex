defmodule Arkea.Sim.Tick do
  @moduledoc """
  Pure tick function for `Arkea.Sim.BiotopeState` (IMPLEMENTATION-PLAN.md §4.1).

  The pipeline mirrors the canonical 6-step order from DESIGN.md Block 11:

    1. `step_metabolism/1`   — stub (Phase 5)
    2. `step_expression/1`   — stub (Phase 5)
    3. `step_cell_events/1`  — implemented: growth via `growth_delta_by_lineage`
    4. `step_hgt/1`          — stub (Phase 6)
    5. `step_environment/1`  — implemented: dilution of lineage abundances
    6. `step_pruning/1`      — stub (Phase 4)

  ## Discipline

  This module is **strictly pure**. No I/O, no message sends, no PubSub calls,
  no DB access. All side-effects happen in `Arkea.Sim.Biotope.Server`
  **after** the tick returns `{new_state, events}`.

  ## Event type

  Events are `%{type: atom(), payload: map()}`. In Phase 2, `derive_events/2`
  always returns `[]`. Phase 4 will populate events for mutations, HGT, lysis,
  etc., feeding the `Arkea.Persistence.AuditLog`.

  ## Growth model (Phase 2)

  `BiotopeState.growth_delta_by_lineage` maps each lineage id to a
  `%{phase_name => integer()}` delta map. `step_cell_events/1` applies those
  deltas via `Lineage.apply_growth/2`, which clamps values at 0 (DESIGN.md
  Block 4 invariant: no negative abundance). Lineages with no entry in the
  delta map are left unchanged.

  Phase 5 will replace the static delta map with genome-derived kinetic rates
  computed by `step_expression/1`.

  ## Dilution model (Phase 2)

  `step_environment/1` multiplies each `abundance_by_phase[phase_name]` by
  `(1.0 - rate)`, where `rate` is the `dilution_rate` of the matching
  `Phase` in `state.phases`, falling back to `state.dilution_rate` when the
  phase is not found. The float is floored to a non_neg_integer, preserving
  the `abundance_by_phase :: %{atom() => non_neg_integer()}` invariant.
  Dilution is **monotonically decreasing**: abundance after ≤ abundance before.
  """

  alias Arkea.Ecology.Lineage
  alias Arkea.Sim.BiotopeState

  @type event :: %{type: atom(), payload: map()}

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
  Step 2 — Gene expression: σ-factor, riboswitch, regulator evaluation (stub for Phase 5).

  Will recompute `growth_delta_by_lineage` from genome-encoded expression levels.
  For Phase 2, returns state unchanged.
  """
  @spec step_expression(BiotopeState.t()) :: BiotopeState.t()
  def step_expression(%BiotopeState{} = state), do: state

  @doc """
  Step 3 — Cell events: aggregate growth per lineage per phase.

  Reads `state.growth_delta_by_lineage` and applies each lineage's delta via
  `Lineage.apply_growth/2`, which clamps results at 0 (non-negativity
  invariant from DESIGN.md Block 4).

  Lineages absent from `growth_delta_by_lineage` receive an empty delta map —
  their abundances are unchanged by growth in this step (dilution in step 5
  still applies).

  Phase 4 will add: stochastic division events, lysis, mutation → new child
  lineages forked into the lineage list.
  """
  @spec step_cell_events(BiotopeState.t()) :: BiotopeState.t()
  def step_cell_events(%BiotopeState{lineages: lineages, growth_delta_by_lineage: deltas} = state) do
    grown =
      Enum.map(lineages, fn lineage ->
        delta = Map.get(deltas, lineage.id, %{})
        Lineage.apply_growth(lineage, delta)
      end)

    %{state | lineages: grown}
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
  Step 6 — Pruning: remove lineages below the abundance threshold (stub for Phase 4).

  Will remove lineages where `Lineage.total_abundance/1 < threshold` and record
  extinction events in the phylogenetic history (DESIGN.md Block 4, cap policy).
  For Phase 2, returns state unchanged.
  """
  @spec step_pruning(BiotopeState.t()) :: BiotopeState.t()
  def step_pruning(%BiotopeState{} = state), do: state

  @doc """
  Derive typed events from the old and new states.

  Returns `[]` in Phase 2. Phase 4 will return a list of typed event maps
  (mutations, HGT events, extinctions, lysis events) consumed by
  `Arkea.Persistence.AuditLog`.
  """
  @spec derive_events(BiotopeState.t(), BiotopeState.t()) :: [event()]
  def derive_events(%BiotopeState{}, %BiotopeState{}), do: []

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
end
