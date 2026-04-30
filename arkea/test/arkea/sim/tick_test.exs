defmodule Arkea.Sim.TickTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Tick

  import Arkea.Generators, only: [biotope_state: 0, biotope_state: 1]

  @moduletag :sim

  # ---------------------------------------------------------------------------
  # Property: non-negativity of abundances after one tick

  property "abundance is non-negative after one tick for any input" do
    check all(state <- biotope_state()) do
      {new_state, _events} = Tick.tick(state)

      for lineage <- new_state.lineages,
          {_phase, count} <- lineage.abundance_by_phase do
        assert count >= 0,
               "negative abundance #{count} found in lineage #{lineage.id}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Property: dilution-only monotonicity (growth_rate == 0)

  property "abundance never increases when growth_delta is 0" do
    check all(state <- biotope_state(growth_rate: 0)) do
      {new_state, _events} = Tick.tick(state)

      for old_lineage <- state.lineages do
        new_lineage =
          Enum.find(new_state.lineages, fn l -> l.id == old_lineage.id end)

        for {phase_name, old_count} <- old_lineage.abundance_by_phase do
          new_count = Map.get(new_lineage.abundance_by_phase, phase_name, 0)

          assert new_count <= old_count,
                 "abundance increased from #{old_count} to #{new_count} in " <>
                   "phase #{phase_name} of lineage #{old_lineage.id} with zero growth"
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Property: tick is deterministic (pure function)

  property "tick is deterministic: same state always produces same result" do
    check all(state <- biotope_state()) do
      {result_a, events_a} = Tick.tick(state)
      {result_b, events_b} = Tick.tick(state)

      assert result_a == result_b,
             "tick returned different new states for the same input"

      assert events_a == events_b,
             "tick returned different events for the same input"
    end
  end

  # ---------------------------------------------------------------------------
  # Property: tick_count increments by exactly 1

  property "tick_count increments by 1 on every tick" do
    check all(state <- biotope_state()) do
      {new_state, _events} = Tick.tick(state)
      assert new_state.tick_count == state.tick_count + 1
    end
  end

  # ---------------------------------------------------------------------------
  # Property: events list is always a list (type contract)

  property "derive_events always returns a list" do
    check all(state <- biotope_state()) do
      {_new_state, events} = Tick.tick(state)
      assert is_list(events)
    end
  end

  # ---------------------------------------------------------------------------
  # Property: steps are composable and the full pipeline equals sequential steps

  property "step_cell_events followed by step_environment equals tick sub-pipeline" do
    check all(state <- biotope_state()) do
      # Apply steps manually in the same order as tick/1
      manual =
        state
        |> Tick.step_metabolism()
        |> Tick.step_expression()
        |> Tick.step_cell_events()
        |> Tick.step_hgt()
        |> Tick.step_environment()
        |> Tick.step_pruning()

      {ticked, _events} = Tick.tick(state)

      # tick/1 also increments tick_count, so we compare only the biological state
      assert manual.lineages == ticked.lineages,
             "manual pipeline and tick/1 disagree on lineages"

      assert manual.phases == ticked.phases,
             "manual pipeline and tick/1 disagree on phases"
    end
  end

  # ---------------------------------------------------------------------------
  # Unit: system reaches a stable fixed point (not necessarily the initial value)

  test "population converges to a stable fixed point after many ticks" do
    # With integer floor(), the discrete steady state differs from the
    # continuous equilibrium. For growth_delta d and dilution_rate r,
    # the fixed point a* satisfies: floor((a* + d) * (1 - r)) = a*
    # i.e. (a* + d)*(1-r) is in [a*, a*+1).
    # We simply verify that after sufficient ticks the population
    # stabilises (consecutive ticks do not change the count).

    phase_name = :surface
    dilution_rate = 0.1
    growth_delta = 10

    phases = [Phase.new(phase_name, dilution_rate: dilution_rate)]

    lineage =
      Lineage.new_founder(
        genome_fixture(),
        %{phase_name => 100},
        0
      )

    state =
      BiotopeState.new_from_opts(
        id: Arkea.UUID.v4(),
        archetype: :oligotrophic_lake,
        phases: phases,
        dilution_rate: dilution_rate,
        lineages: [lineage],
        growth_delta_by_lineage: %{lineage.id => %{phase_name => growth_delta}}
      )

    # Run until convergence (or max 200 ticks)
    {final_state, _} =
      Enum.reduce_while(1..200, {state, -1}, fn _, {acc, prev} ->
        {new_acc, _} = Tick.tick(acc)
        lineage_now = hd(new_acc.lineages)
        count = Map.fetch!(lineage_now.abundance_by_phase, phase_name)

        if count == prev do
          {:halt, {new_acc, count}}
        else
          {:cont, {new_acc, count}}
        end
      end)

    final_lineage = hd(final_state.lineages)
    final_count = Map.fetch!(final_lineage.abundance_by_phase, phase_name)

    # The fixed point must be non-negative (by the clamp invariant)
    assert final_count >= 0

    # Verify it is actually a fixed point: one more tick changes nothing
    {after_one_more, _} = Tick.tick(final_state)
    count_after = Map.fetch!(hd(after_one_more.lineages).abundance_by_phase, phase_name)

    assert count_after == final_count,
           "population has not converged: #{final_count} → #{count_after}"
  end

  # ---------------------------------------------------------------------------
  # Unit: stub steps return state unchanged

  test "step_metabolism returns state unchanged" do
    state = simple_state()
    assert Tick.step_metabolism(state) == state
  end

  test "step_expression returns state unchanged" do
    state = simple_state()
    assert Tick.step_expression(state) == state
  end

  test "step_hgt returns state unchanged" do
    state = simple_state()
    assert Tick.step_hgt(state) == state
  end

  test "step_pruning returns state unchanged" do
    state = simple_state()
    assert Tick.step_pruning(state) == state
  end

  # ---------------------------------------------------------------------------
  # Unit: step_cell_events clamps at zero

  test "step_cell_events clamps abundance at zero when delta is strongly negative" do
    phase_name = :surface
    initial_abundance = 10

    lineage =
      Lineage.new_founder(
        genome_fixture(),
        %{phase_name => initial_abundance},
        0
      )

    state =
      BiotopeState.new_from_opts(
        id: Arkea.UUID.v4(),
        archetype: :oligotrophic_lake,
        phases: [Phase.new(phase_name)],
        dilution_rate: 0.05,
        lineages: [lineage],
        growth_delta_by_lineage: %{lineage.id => %{phase_name => -1_000_000}}
      )

    new_state = Tick.step_cell_events(state)
    result_lineage = hd(new_state.lineages)
    assert Map.fetch!(result_lineage.abundance_by_phase, phase_name) == 0
  end

  # ---------------------------------------------------------------------------
  # Unit: step_environment uses per-phase dilution_rate

  test "step_environment applies per-phase dilution_rate" do
    phase_a = Phase.new(:surface, dilution_rate: 0.5)
    phase_b = Phase.new(:sediment, dilution_rate: 0.1)

    lineage =
      Lineage.new_founder(
        genome_fixture(),
        %{surface: 100, sediment: 100},
        0
      )

    state =
      BiotopeState.new_from_opts(
        id: Arkea.UUID.v4(),
        archetype: :eutrophic_pond,
        phases: [phase_a, phase_b],
        dilution_rate: 0.05,
        lineages: [lineage]
      )

    new_state = Tick.step_environment(state)
    result = hd(new_state.lineages)

    # floor(100 * 0.5) = 50
    assert Map.fetch!(result.abundance_by_phase, :surface) == 50
    # floor(100 * 0.9) = 90
    assert Map.fetch!(result.abundance_by_phase, :sediment) == 90
  end

  # ---------------------------------------------------------------------------
  # Private helpers

  defp genome_fixture do
    domain = Domain.new([0, 0, 0], List.duplicate(0, 20))
    gene = Gene.from_domains([domain])
    Genome.new([gene])
  end

  defp simple_state do
    phase = Phase.new(:surface)

    lineage =
      Lineage.new_founder(
        genome_fixture(),
        %{surface: 100},
        0
      )

    BiotopeState.new_from_opts(
      id: Arkea.UUID.v4(),
      archetype: :oligotrophic_lake,
      phases: [phase],
      dilution_rate: 0.05,
      lineages: [lineage]
    )
  end
end
