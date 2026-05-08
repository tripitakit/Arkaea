defmodule Arkea.Views.MetabolicMapTest do
  use ExUnit.Case, async: true

  alias Arkea.Ecology.Phase
  alias Arkea.Sim.BiotopeState
  alias Arkea.Views.MetabolicMap

  defp build_state(phases) do
    BiotopeState.new_from_opts(
      id: Arkea.UUID.v4(),
      archetype: :eutrophic_pond,
      x: 0.0,
      y: 0.0,
      phases: phases,
      dilution_rate: 0.0,
      lineages: []
    )
  end

  defp phase_with_pool(name, pool) do
    Phase.new(name) |> Map.put(:metabolite_pool, pool)
  end

  test "build/1 produces one row per canonical metabolite (13)" do
    state = build_state([Phase.new(:surface)])
    model = MetabolicMap.build(state)

    assert length(model.rows) == 13
    assert length(model.metabolites) == 13
    assert model.metabolites == MetabolicMap.metabolite_order()
  end

  test "build/1 produces one cell per (metabolite × phase) pair" do
    state = build_state([Phase.new(:surface), Phase.new(:water_column), Phase.new(:sediment)])
    model = MetabolicMap.build(state)

    for row <- model.rows do
      assert length(row.cells) == 3
      phases = Enum.map(row.cells, & &1.phase)
      assert phases == [:surface, :water_column, :sediment]
    end
  end

  test "intensity is per-row normalised: max cell of a row → 1.0, zero cell → 0.0" do
    state =
      build_state([
        phase_with_pool(:surface, %{glucose: 100.0, h2s: 5.0}),
        phase_with_pool(:sediment, %{glucose: 25.0, h2s: 15.0})
      ])

    model = MetabolicMap.build(state)

    glucose_row = Enum.find(model.rows, &(&1.metabolite == :glucose))
    surface_glucose = Enum.find(glucose_row.cells, &(&1.phase == :surface))
    sediment_glucose = Enum.find(glucose_row.cells, &(&1.phase == :sediment))

    assert surface_glucose.intensity == 1.0
    assert_in_delta sediment_glucose.intensity, 0.25, 1.0e-9

    h2s_row = Enum.find(model.rows, &(&1.metabolite == :h2s))
    sediment_h2s = Enum.find(h2s_row.cells, &(&1.phase == :sediment))
    assert sediment_h2s.intensity == 1.0
  end

  test "h2s row colour scale survives a dominant glucose elsewhere" do
    # Sanity: per-row normalisation means the sulfur cycle doesn't
    # vanish under a glucose-rich biotope.
    state =
      build_state([
        phase_with_pool(:surface, %{glucose: 1000.0, h2s: 10.0}),
        phase_with_pool(:anoxic, %{glucose: 0.0, h2s: 30.0})
      ])

    model = MetabolicMap.build(state)
    h2s_row = Enum.find(model.rows, &(&1.metabolite == :h2s))
    intensities = h2s_row.cells |> Enum.map(& &1.intensity) |> Enum.sort()
    # Anoxic h2s (30) → 1.0; surface h2s (10) → 0.333.
    assert intensities |> List.last() == 1.0
    assert_in_delta intensities |> List.first(), 10.0 / 30.0, 1.0e-9
  end

  test "phases without a metabolite_pool render as zero cells" do
    state = build_state([Phase.new(:empty)])
    model = MetabolicMap.build(state)

    for row <- model.rows do
      [cell] = row.cells
      assert cell.value == 0.0
      assert cell.intensity == 0.0
    end

    assert model.biotope_max == 0.0
  end

  test "metabolite_label/1 carries chemistry-correct formatting" do
    assert MetabolicMap.metabolite_label(:co2) == "CO₂"
    assert MetabolicMap.metabolite_label(:ch4) == "CH₄"
    assert MetabolicMap.metabolite_label(:h2s) == "H₂S"
    assert MetabolicMap.metabolite_label(:so4) == "SO₄²⁻"
    assert MetabolicMap.metabolite_label(:iron) == "Fe²⁺/³⁺"
    assert MetabolicMap.metabolite_label(:po4) == "PO₄³⁻"
  end

  test "canonical metabolite list matches Arkea.Sim.Metabolism (regression guard)" do
    assert MetabolicMap.canonical_matches_metabolism?(),
           "view-layer canonical list drifted from Arkea.Sim.Metabolism — keep them in sync"
  end
end
