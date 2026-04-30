defmodule Arkea.Sim.EvolutionTest do
  @moduledoc """
  Phase 4 integration test: verifies that the full mutation → selection → diversity
  pipeline produces observable evolutionary divergence from a single seed lineage.

  DESIGN.md Block 4 states: "Every biotope maintains a lineage forest — each
  lineage with a full genome, abundance, fitness, parent pointer → reconstructible
  phylogeny." This test verifies that forest actually grows and diversifies.
  """

  use ExUnit.Case, async: true

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Mutator
  alias Arkea.Sim.Phenotype
  alias Arkea.Sim.Tick

  @moduletag :sim
  @moduletag timeout: 60_000

  # ---------------------------------------------------------------------------
  # Helper: build a genome with catalytic domains so phenotype.base_growth_rate
  # is positive, giving lineages a reason to grow (and thus to replicate).

  defp seed_genome do
    # :catalytic_site → type_tag sum rem(11) = 1 → [0, 0, 1]
    # High parameter_codons (value 15) → high kcat → high base_growth_rate
    catalytic_domain = Domain.new([0, 0, 1], List.duplicate(15, 20))
    # :repair_fidelity → type_tag sum rem(11) = 10 → need sum = 10 → [0, 1, 9]
    # Low efficiency parameters → low repair_efficiency → higher mutation rate
    repair_domain = Domain.new([0, 1, 9], List.duplicate(2, 20))
    # Third domain for variety
    binding_domain = Domain.new([0, 0, 0], List.duplicate(5, 20))

    gene = Gene.from_domains([catalytic_domain, repair_domain, binding_domain])
    Genome.new([gene])
  end

  # ---------------------------------------------------------------------------
  # Main evolution test

  test "100 ticks from single seed produce at least 3 distinct lineages with differing phenotypes" do
    genome = seed_genome()
    phase_name = :surface

    # Single seed lineage with abundant population
    seed_lineage =
      Lineage.new_founder(
        genome,
        %{phase_name => 500},
        0
      )

    phase = Phase.new(phase_name, dilution_rate: 0.02)

    state =
      BiotopeState.new_from_opts(
        id: Arkea.UUID.v4(),
        archetype: :oligotrophic_lake,
        phases: [phase],
        dilution_rate: 0.02,
        lineages: [seed_lineage],
        rng_seed: Mutator.init_seed("evolution-test-seed")
      )

    # Run 100 ticks via Tick.tick/1 directly (no GenServer, pure function)
    {final_state, _all_events} =
      Enum.reduce(1..100, {state, []}, fn _, {acc_state, acc_events} ->
        {new_state, events} = Tick.tick(acc_state)
        {new_state, acc_events ++ events}
      end)

    # --- Assertions ---

    # 1. tick_count == 100
    assert final_state.tick_count == 100,
           "tick_count should be exactly 100, got #{final_state.tick_count}"

    # 2. At least 3 distinct lineages (the seed + at least 2 mutant descendants)
    lineage_count = length(final_state.lineages)

    assert lineage_count >= 3,
           "Expected at least 3 lineages after 100 ticks, got #{lineage_count}. " <>
             "Mutation pipeline may not be active."

    # 3. No lineage has a negative abundance in any phase
    for lineage <- final_state.lineages,
        {phase_n, count} <- lineage.abundance_by_phase do
      assert count >= 0,
             "Negative abundance #{count} in phase #{phase_n} of lineage #{lineage.id}"
    end

    # 4. The top-3 lineages by abundance have at least one phenotype field
    #    differing by > 0.01 — confirming actual phenotypic divergence.
    top3 =
      final_state.lineages
      |> Enum.filter(fn l -> l.genome != nil end)
      |> Enum.sort_by(&Lineage.total_abundance/1, :desc)
      |> Enum.take(3)

    if length(top3) >= 2 do
      phenotypes = Enum.map(top3, fn l -> Phenotype.from_genome(l.genome) end)
      [p1 | rest_phenotypes] = phenotypes

      diverged =
        Enum.any?(rest_phenotypes, fn p ->
          abs(p.base_growth_rate - p1.base_growth_rate) > 0.01 or
            abs(p.repair_efficiency - p1.repair_efficiency) > 0.01 or
            abs(p.energy_cost - p1.energy_cost) > 0.001
        end)

      assert diverged,
             "Top lineages show no phenotypic divergence after 100 ticks. " <>
               "Phenotypes: #{inspect(phenotypes)}"
    end
  end

  # ---------------------------------------------------------------------------
  # Secondary test: pruning removes extinct lineages

  test "step_pruning removes all lineages with total_abundance == 0" do
    genome = seed_genome()
    phase_name = :surface
    phase = Phase.new(phase_name, dilution_rate: 0.0)

    alive =
      Lineage.new_founder(
        genome,
        %{phase_name => 50},
        0
      )

    # genome: nil lineages are allowed — they are delta-encoded descendants
    # We simulate an extinct lineage by giving it zero abundance
    extinct_genome =
      Genome.new([Gene.from_domains([Domain.new([0, 0, 0], List.duplicate(0, 20))])])

    extinct =
      Lineage.new_founder(
        extinct_genome,
        %{phase_name => 0},
        0
      )

    state =
      BiotopeState.new_from_opts(
        id: Arkea.UUID.v4(),
        archetype: :oligotrophic_lake,
        phases: [phase],
        dilution_rate: 0.0,
        lineages: [alive, extinct]
      )

    pruned = Tick.step_pruning(state)

    assert length(pruned.lineages) == 1,
           "step_pruning should remove the zero-abundance lineage"

    surviving = hd(pruned.lineages)
    assert surviving.id == alive.id
  end

  # ---------------------------------------------------------------------------
  # Secondary test: derive_events emits born/extinct events

  test "derive_events emits :lineage_born for new lineages and :lineage_extinct for removed ones" do
    genome = seed_genome()
    phase_name = :surface
    phase = Phase.new(phase_name, dilution_rate: 0.0)

    original =
      Lineage.new_founder(
        genome,
        %{phase_name => 100},
        0
      )

    child_genome = Genome.new([Gene.from_domains([Domain.new([0, 0, 1], List.duplicate(5, 20))])])
    child = Lineage.new_child(original, child_genome, %{phase_name => 1}, 1)

    old_state =
      BiotopeState.new_from_opts(
        id: Arkea.UUID.v4(),
        archetype: :oligotrophic_lake,
        phases: [phase],
        dilution_rate: 0.0,
        lineages: [original],
        tick_count: 1
      )

    new_state = %{
      old_state
      | lineages: [child],
        tick_count: 2
    }

    events = Tick.derive_events(old_state, new_state)

    born = Enum.filter(events, fn e -> e.type == :lineage_born end)
    extinct = Enum.filter(events, fn e -> e.type == :lineage_extinct end)

    assert length(born) == 1, "Expected 1 :lineage_born event"
    assert hd(born).payload.lineage_id == child.id

    assert length(extinct) == 1, "Expected 1 :lineage_extinct event"
    assert hd(extinct).payload.lineage_id == original.id
  end
end
