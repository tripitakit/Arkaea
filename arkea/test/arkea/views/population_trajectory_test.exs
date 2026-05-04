defmodule Arkea.Views.PopulationTrajectoryTest do
  use ExUnit.Case, async: true

  alias Arkea.Persistence.AuditLog
  alias Arkea.Persistence.TimeSeriesSample
  alias Arkea.Views.PopulationTrajectory

  test "build/2 returns degenerate domains for empty inputs" do
    assert %{
             tick_domain: {0, 0},
             population_domain: {0, 0},
             lineages: [],
             markers: []
           } = PopulationTrajectory.build([], [])
  end

  test "groups abundance samples by lineage and orders by peak descending" do
    samples = [
      sample("a", 0, 100),
      sample("a", 5, 250),
      sample("a", 10, 200),
      sample("b", 0, 1000),
      sample("b", 5, 800),
      sample("b", 10, 500)
    ]

    model = PopulationTrajectory.build(samples, [])

    assert model.tick_domain == {0, 10}
    assert {0, 1000} = model.population_domain

    [first, second] = model.lineages
    assert first.id == "b"
    assert first.peak == 1000
    assert second.id == "a"
    assert second.peak == 250

    # Each lineage's points are sorted by tick.
    assert first.points == [{0, 1000}, {5, 800}, {10, 500}]
  end

  test "filters audit log entries to relevant marker types only" do
    audit = [
      %AuditLog{event_type: "intervention", occurred_at_tick: 5, payload: %{}},
      %AuditLog{event_type: "lineage_born", occurred_at_tick: 6, payload: %{}},
      %AuditLog{event_type: "mass_lysis", occurred_at_tick: 8, payload: %{}}
    ]

    model = PopulationTrajectory.build([], audit)

    types = Enum.map(model.markers, & &1.type)
    assert "intervention" in types
    assert "mass_lysis" in types
    refute "lineage_born" in types
  end

  defp sample(lineage_id, tick, total) do
    %TimeSeriesSample{
      kind: "abundance",
      scope_id: lineage_id,
      tick: tick,
      payload: %{"total" => total, "by_phase" => %{}}
    }
  end
end
