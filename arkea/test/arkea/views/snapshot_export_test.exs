defmodule Arkea.Views.SnapshotExportTest do
  use ExUnit.Case, async: true

  alias Arkea.Sim.BiotopeState
  alias Arkea.Views.SnapshotExport

  test "build/3 produces a JSON-serialisable map for an empty biotope" do
    state = empty_state()
    export = SnapshotExport.build(state)

    assert export.format_version == 1
    assert export.biotope.id == state.id
    assert is_list(export.phases)
    assert is_list(export.lineages)
    assert export.audit_log == []
    assert export.time_series == []

    # Encodable to JSON without raising.
    assert {:ok, _json} = Jason.encode(export)
  end

  test "phase metabolite_pool keys are stringified" do
    state = empty_state()
    export = SnapshotExport.build(state)
    phase = hd(export.phases)

    for {key, _value} <- phase.metabolite_pool do
      assert is_binary(key)
    end
  end

  defp empty_state do
    phases = [Arkea.Ecology.Phase.new(:water_column)]

    BiotopeState.new_from_opts(
      id: Arkea.UUID.v4(),
      archetype: :eutrophic_pond,
      x: 0.0,
      y: 0.0,
      phases: phases,
      dilution_rate: 0.05,
      tick_count: 0
    )
  end
end
