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

  describe "build_trait/3 (Phase 21 Top 5 #4)" do
    test "returns degenerate domains for empty inputs" do
      model = PopulationTrajectory.build_trait([], [], "repair_efficiency")
      assert model.trait == "repair_efficiency"
      assert model.tick_domain == {0, 0}
      assert {min_y, max_y} = model.value_domain
      assert min_y == 0.0
      assert max_y == 0.0
      assert model.lineages == []
      assert model.markers == []
    end

    test "ignores samples of other kinds" do
      mixed = [
        # Should be filtered out — wrong kind.
        sample("a", 0, 100),
        trait_sample("a", 5, %{"repair_efficiency" => 0.42}),
        trait_sample("a", 10, %{"repair_efficiency" => 0.40})
      ]

      model = PopulationTrajectory.build_trait(mixed, [], "repair_efficiency")
      assert length(model.lineages) == 1
      [series] = model.lineages
      assert series.id == "a"
      assert series.points == [{5, 0.42}, {10, 0.40}]
    end

    test "groups by lineage, derives value_domain from min and max across all series" do
      samples = [
        trait_sample("a", 0, %{"repair_efficiency" => 0.40}),
        trait_sample("a", 5, %{"repair_efficiency" => 0.05}),
        trait_sample("b", 0, %{"repair_efficiency" => 0.50}),
        trait_sample("b", 5, %{"repair_efficiency" => 0.55})
      ]

      model = PopulationTrajectory.build_trait(samples, [], "repair_efficiency")

      assert model.tick_domain == {0, 5}
      assert model.value_domain == {0.05, 0.55}
      # Two lineages, each with two points.
      assert length(model.lineages) == 2
      ids = Enum.map(model.lineages, & &1.id) |> Enum.sort()
      assert ids == ["a", "b"]
    end

    test "drops lineages whose payload lacks the requested trait" do
      samples = [
        trait_sample("a", 0, %{"repair_efficiency" => 0.40}),
        trait_sample("b", 0, %{"base_growth_rate" => 0.10})
      ]

      model = PopulationTrajectory.build_trait(samples, [], "repair_efficiency")

      assert length(model.lineages) == 1
      [series] = model.lineages
      assert series.id == "a"
    end

    test "boolean traits plot as 0.0 / 1.0 step values" do
      samples = [
        trait_sample("a", 0, %{"biofilm_capable" => false}),
        trait_sample("a", 5, %{"biofilm_capable" => true}),
        trait_sample("a", 10, %{"biofilm_capable" => true})
      ]

      model = PopulationTrajectory.build_trait(samples, [], "biofilm_capable")
      [series] = model.lineages
      assert series.points == [{0, 0.0}, {5, 1.0}, {10, 1.0}]
      assert series.min == 0.0
      assert series.max == 1.0
    end

    test "audit markers extended with Phase 21 stress events" do
      audit = [
        %AuditLog{event_type: "sos_active", occurred_at_tick: 8, payload: %{}},
        %AuditLog{event_type: "mutator_emergence", occurred_at_tick: 10, payload: %{}},
        %AuditLog{event_type: "biofilm_formation", occurred_at_tick: 12, payload: %{}},
        # Should still be ignored (not in marker list).
        %AuditLog{event_type: "lineage_born", occurred_at_tick: 14, payload: %{}}
      ]

      model = PopulationTrajectory.build_trait([], audit, "repair_efficiency")
      types = Enum.map(model.markers, & &1.type)
      assert "sos_active" in types
      assert "mutator_emergence" in types
      assert "biofilm_formation" in types
      refute "lineage_born" in types
    end

    test "trait_keys/0 enumerates the canonical phenotype scalars" do
      keys = PopulationTrajectory.trait_keys()
      assert "repair_efficiency" in keys
      assert "base_growth_rate" in keys
      assert "biofilm_capable" in keys
      assert "n_transmembrane" in keys
    end
  end

  defp sample(lineage_id, tick, total) do
    %TimeSeriesSample{
      kind: "abundance",
      scope_id: lineage_id,
      tick: tick,
      payload: %{"total" => total, "by_phase" => %{}}
    }
  end

  defp trait_sample(lineage_id, tick, payload) do
    %TimeSeriesSample{
      kind: "phenotype_trait",
      scope_id: lineage_id,
      tick: tick,
      payload: payload
    }
  end
end
