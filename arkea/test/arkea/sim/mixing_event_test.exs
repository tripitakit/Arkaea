defmodule Arkea.Sim.MixingEventTest do
  @moduledoc """
  Tests for Phase 18 Poisson mixing event (DESIGN.md Block 8 Phase 18).
  """
  use ExUnit.Case, async: true

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Tick

  @param_codons List.duplicate(10, 20)

  defp simple_genome do
    Genome.new([Gene.from_domains([Domain.new([0, 0, 1], @param_codons)])])
  end

  defp build_state_with_uneven_distribution do
    phase_a = Phase.new(:surface, dilution_rate: 0.0)
    phase_b = Phase.new(:sediment, dilution_rate: 0.0)
    phase_c = Phase.new(:water_column, dilution_rate: 0.0)

    # All cells in :surface, none elsewhere.
    lineage =
      Lineage.new_founder(simple_genome(), %{surface: 900, sediment: 0, water_column: 0}, 0)

    BiotopeState.new_from_opts(
      id: Arkea.UUID.v4(),
      archetype: :eutrophic_pond,
      phases: [phase_a, phase_b, phase_c],
      dilution_rate: 0.0,
      lineages: [lineage]
    )
  end

  describe "step_mixing_event/1" do
    test "single-phase biotope is left untouched" do
      phase = Phase.new(:surface, dilution_rate: 0.0)

      lineage = Lineage.new_founder(simple_genome(), %{surface: 100}, 0)

      state =
        BiotopeState.new_from_opts(
          id: Arkea.UUID.v4(),
          archetype: :eutrophic_pond,
          phases: [phase],
          dilution_rate: 0.0,
          lineages: [lineage]
        )

      assert Tick.step_mixing_event(state) == state
    end

    test "multi-phase biotope: a fired event redistributes lineages uniformly" do
      state = build_state_with_uneven_distribution()

      # Force the event by setting an RNG seed that produces a roll
      # below `@mixing_event_probability` (1e-4). We iterate over a
      # bounded set of seeds until we find a state where the event
      # fires; the deterministic nature of `:rand.uniform_s/1` lets
      # us search the seed space in test code.
      seed_with_event_fire =
        Enum.find(0..200_000, fn n ->
          rng = :rand.seed_s(:exsss, {n, n + 1, n + 2})
          {roll, _} = :rand.uniform_s(rng)
          roll < 1.0e-4
        end)

      assert seed_with_event_fire != nil,
             "could not find an RNG seed that triggers the event in 0..200_000"

      forced_rng =
        :rand.seed_s(
          :exsss,
          {seed_with_event_fire, seed_with_event_fire + 1, seed_with_event_fire + 2}
        )

      state_with_seed = %{state | rng_seed: forced_rng}
      mixed = Tick.step_mixing_event(state_with_seed)

      [lineage] = mixed.lineages
      counts = Map.values(lineage.abundance_by_phase)

      # 900 cells across 3 phases → 300 each (no remainder).
      assert Enum.all?(counts, fn c -> c == 300 end)
    end

    test "missed Poisson roll leaves the state unchanged (apart from rng_seed)" do
      state = build_state_with_uneven_distribution()

      # Pick an RNG seed that produces a roll above the threshold.
      seed_no_event =
        Enum.find(0..100, fn n ->
          rng = :rand.seed_s(:exsss, {n, n + 1, n + 2})
          {roll, _} = :rand.uniform_s(rng)
          roll >= 1.0e-4
        end)

      assert seed_no_event != nil

      no_fire_rng =
        :rand.seed_s(:exsss, {seed_no_event, seed_no_event + 1, seed_no_event + 2})

      state_with_seed = %{state | rng_seed: no_fire_rng}
      result = Tick.step_mixing_event(state_with_seed)

      # Lineages and phases unchanged.
      assert result.lineages == state_with_seed.lineages
      assert result.phases == state_with_seed.phases
    end
  end
end
