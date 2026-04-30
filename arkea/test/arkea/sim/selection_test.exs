defmodule Arkea.Sim.SelectionTest do
  @moduledoc """
  Phase 5 selection criterion test (IMPLEMENTATION-PLAN.md §5, Phase 5).

  Verifies that Michaelis-Menten metabolic kinetics produce ecologically
  meaningful selection: lineages specialised for their biotope's chemistry
  dominate lineages that lack the required substrate affinities.

  ## Test scenario

  Two lineages compete in two biotopes with contrasting metabolite profiles:

    - **Lineage A (glucose specialist with metabolic cost)**:
      `substrate_binding` targeting `:glucose` + `energy_coupling` giving
      `energy_cost > 0`. In glucose-rich Biotope 1, ATP yield > cost → grows.
      In glucose-free Biotope 2, ATP yield = 0 but cost > 0 → shrinks rapidly.

    - **Lineage B (anaerobe baseline, no metabolic cost)**:
      `substrate_binding` targeting `:no3` (ATP coefficient = 0.0, as
      NO₃⁻ is an electron acceptor, not an ATP source). No `energy_coupling`
      domain → `energy_cost = 0.0`. Gets zero ATP in both biotopes from NO₃.
      In Biotope 2 (no glucose), B declines only via dilution (net = 0 → delta
      = 0 → dilution alone drives slow decrease), whereas A crashes from
      negative delta.

  ## Selection mechanism for Biotope 2

  Since NO₃ has ATP coefficient 0.0 (Block 6 — accettore anaerobico, non
  fonte diretta di ATP in Phase 5), Lineage B does not win by gaining energy
  from NO₃. The selection pressure is **differential survival**: A crashes
  fast (atp_yield=0 but energy_cost>0 → large negative delta per tick), while
  B declines slowly (atp_yield=0, energy_cost=0 → delta=0, only dilution).
  After 50 ticks, B retains more abundance than A → B "wins" in Biotope 2.

  This models real anaerobic survival: organisms that shed energetically costly
  aerobic machinery survive starvation in anoxic environments better than
  those that pay the cost of maintaining unused oxidative phosphorylation
  components.

  ## NOTE on NO₃ ATP yield

  In real denitrification, NO₃⁻ + organic C → N₂ + CO₂ yields ~4–5 ATP/mol
  (Strohm et al. 2007). Phase 5 approximation sets this to 0.0 as a first-pass
  simplification (Phase 5 does not yet model coupled donor/acceptor reactions).
  The coefficient will be refined in a future phase when electron-donor/acceptor
  coupling is modelled. This test is calibrated for the Phase 5 approximation.
  """

  use ExUnit.Case, async: true

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Tick

  @moduletag :sim
  @moduletag timeout: 60_000

  # ---------------------------------------------------------------------------
  # Genome builders

  # Genome A: glucose specialist with energy cost.
  # - substrate_binding → glucose (first parameter codon = 0 →
  #   target_metabolite_id = rem(0,13) = 0 → :glucose)
  #   km derived from all-zero codons: norm=0 → km = 0.01 (very high affinity)
  # - energy_coupling → atp_cost = norm * 5.0
  #   with codons at value 12: raw_sum ≈ 12*20 * ~weight, norm ≈ 0.5 → atp_cost ≈ 2.5
  defp genome_a do
    # :substrate_binding type_tag [0,0,0] (sum=0, rem(0,11)=0)
    # parameter_codons: first = 0 (→ glucose), rest = 0 (low km)
    glucose_binding = Domain.new([0, 0, 0], [0 | List.duplicate(0, 19)])
    assert glucose_binding.type == :substrate_binding
    assert glucose_binding.params.target_metabolite_id == 0

    # :energy_coupling type_tag [0,1,3] (sum=4, rem(4,11)=4)
    # parameter_codons all at 12: norm ≈ 0.48 → atp_cost ≈ 2.4
    energy = Domain.new([0, 1, 3], List.duplicate(12, 20))
    assert energy.type == :energy_coupling
    assert energy.params.atp_cost > 1.0

    gene = Gene.from_domains([glucose_binding, energy])
    Genome.new([gene])
  end

  # Genome B: NO₃ specialist with no energy cost.
  # - substrate_binding → no3 (first parameter codon = 8 →
  #   target_metabolite_id = rem(8,13) = 8 → :no3)
  # - No energy_coupling → energy_cost = 0.0
  defp genome_b do
    # :substrate_binding type_tag [0,0,0]
    # parameter_codons: first = 8 (→ no3), rest = 5
    no3_binding = Domain.new([0, 0, 0], [8 | List.duplicate(5, 19)])
    assert no3_binding.type == :substrate_binding
    assert no3_binding.params.target_metabolite_id == 8

    gene = Gene.from_domains([no3_binding])
    Genome.new([gene])
  end

  # ---------------------------------------------------------------------------
  # Test helper: run N ticks on a state and return the final state

  defp run_ticks(state, n) do
    Enum.reduce(1..n, state, fn _, acc ->
      {new_state, _events} = Tick.tick(acc)
      new_state
    end)
  end

  defp abundance_of(state, lineage_id, phase_name) do
    case Enum.find(state.lineages, fn l -> l.id == lineage_id end) do
      nil -> 0
      l -> Map.get(l.abundance_by_phase, phase_name, 0)
    end
  end

  # ---------------------------------------------------------------------------
  # Test 1: glucose specialist wins in glucose-rich oxygenated biotope

  test "aerobe (glucose + energy cost) outcompetes NO₃-specialist in glucose-rich biotope" do
    # Biotope 1: glucose-rich, oxygen present, no NO₃.
    # Lineage A gets ATP from glucose → positive delta → grows.
    # Lineage B has NO₃ affinity but no NO₃ in pool, AND no glucose affinity.
    # Both have no glucose for B (only NO₃-binding). B gets 0 ATP.
    # But A has energy_cost > 0 AND glucose ATP > energy_cost → net positive.
    # B has 0 ATP but also 0 energy_cost → delta = 0 → only dilution.
    # After 50 ticks: A > B in abundance.
    phase_name = :water_column

    lineage_a =
      Lineage.new_founder(
        genome_a(),
        %{phase_name => 200},
        0
      )

    lineage_b =
      Lineage.new_founder(
        genome_b(),
        %{phase_name => 200},
        0
      )

    phase =
      Phase.new(phase_name, dilution_rate: 0.05)
      |> Phase.update_metabolite(:glucose, 1000.0)
      |> Phase.update_metabolite(:oxygen, 500.0)

    state =
      BiotopeState.new_from_opts(
        id: Arkea.UUID.v4(),
        archetype: :eutrophic_pond,
        phases: [phase],
        dilution_rate: 0.05,
        lineages: [lineage_a, lineage_b],
        # Continuous glucose inflow keeps the pool replenished
        metabolite_inflow: %{glucose: 20.0, oxygen: 10.0}
      )

    final = run_ticks(state, 50)

    abundance_a = abundance_of(final, lineage_a.id, phase_name)
    abundance_b = abundance_of(final, lineage_b.id, phase_name)

    assert abundance_a > abundance_b,
           "Expected glucose-specialist A (#{abundance_a}) > NO₃-specialist B (#{abundance_b}) " <>
             "in glucose-rich biotope after 50 ticks"
  end

  # ---------------------------------------------------------------------------
  # Test 2: NO₃-specialist survives better than glucose-specialist in anoxic biotope

  test "NO₃-specialist survives better than glucose-specialist (high cost) in anoxic NO₃-rich biotope" do
    # Biotope 2: anoxic, no glucose, only NO₃ present.
    # Lineage A: glucose affinity + energy_cost > 0.
    #   → atp_yield = 0 (no glucose), but energy_cost × 5 > 0
    #   → net = (0 - cost*5) * sigma < 0
    #   → delta strongly negative → crashes rapidly
    #
    # Lineage B: NO₃ affinity + energy_cost = 0.
    #   → atp_yield = 0 (NO₃ coeff = 0.0 in Phase 5 approximation)
    #   → net = (0 - 0) * sigma = 0 → delta = 0
    #   → only dilution (5% per tick), declining slowly
    #
    # After 50 ticks: B retains significantly more abundance than A.
    phase_name = :sediment

    lineage_a =
      Lineage.new_founder(
        genome_a(),
        %{phase_name => 200},
        0
      )

    lineage_b =
      Lineage.new_founder(
        genome_b(),
        %{phase_name => 200},
        0
      )

    phase =
      Phase.new(phase_name, dilution_rate: 0.05)
      |> Phase.update_metabolite(:no3, 1000.0)

    state =
      BiotopeState.new_from_opts(
        id: Arkea.UUID.v4(),
        archetype: :eutrophic_pond,
        phases: [phase],
        dilution_rate: 0.05,
        lineages: [lineage_a, lineage_b],
        # NO₃ inflow, no glucose
        metabolite_inflow: %{no3: 10.0}
      )

    final = run_ticks(state, 50)

    abundance_a = abundance_of(final, lineage_a.id, phase_name)
    abundance_b = abundance_of(final, lineage_b.id, phase_name)

    assert abundance_b > abundance_a,
           "Expected NO₃-specialist B (#{abundance_b}) to survive better than " <>
             "glucose-specialist A (#{abundance_a}) in anoxic NO₃-rich biotope after 50 ticks. " <>
             "Selection mechanism: A crashes from negative delta (energy_cost with no substrate); " <>
             "B declines only from dilution (net=0, delta=0, no energy_cost)."
  end

  # ---------------------------------------------------------------------------
  # Sanity: verify phenotype properties of the two genomes

  test "genome_a has glucose affinity and positive energy_cost" do
    alias Arkea.Sim.Phenotype
    phenotype = Phenotype.from_genome(genome_a())

    assert Map.has_key?(phenotype.substrate_affinities, :glucose),
           "Genome A should have :glucose in substrate_affinities"

    assert phenotype.energy_cost > 1.0,
           "Genome A energy_cost should be > 1.0, got #{phenotype.energy_cost}"
  end

  test "genome_b has no3 affinity and zero energy_cost" do
    alias Arkea.Sim.Phenotype
    phenotype = Phenotype.from_genome(genome_b())

    assert Map.has_key?(phenotype.substrate_affinities, :no3),
           "Genome B should have :no3 in substrate_affinities"

    assert phenotype.energy_cost == 0.0,
           "Genome B energy_cost should be 0.0 (no energy_coupling domain)"
  end
end
