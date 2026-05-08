defmodule Arkea.Views.PhenotypeDistributionTest do
  use ExUnit.Case, async: true

  alias Arkea.Persistence.TimeSeriesSample
  alias Arkea.Views.PhenotypeDistribution

  test "build/3 with no samples → empty domains, no points, nil mean" do
    model = PhenotypeDistribution.build([], "repair_efficiency", %{})

    assert model.trait == "repair_efficiency"
    assert model.points == []
    assert model.weighted_mean == nil
    assert model.total_abundance == 0
  end

  test "build/3 picks the most recent tick when samples span multiple ticks" do
    samples = [
      trait_sample("a", 10, %{"repair_efficiency" => 0.40}),
      trait_sample("a", 20, %{"repair_efficiency" => 0.30}),
      trait_sample("b", 20, %{"repair_efficiency" => 0.55})
    ]

    abundances = %{"a" => 100, "b" => 200}
    model = PhenotypeDistribution.build(samples, "repair_efficiency", abundances)

    assert model.tick == 20
    assert length(model.points) == 2
    # `a` at tick 20 has trait 0.30, not the tick-10 value 0.40.
    a_point = Enum.find(model.points, &(&1.id == "a"))
    assert a_point.x == 0.30
  end

  test "weighted_mean is the abundance-weighted mean of x" do
    samples = [
      trait_sample("a", 10, %{"repair_efficiency" => 0.20}),
      trait_sample("b", 10, %{"repair_efficiency" => 0.80})
    ]

    # Equal abundance → mean is plain arithmetic (0.50).
    model = PhenotypeDistribution.build(samples, "repair_efficiency", %{"a" => 100, "b" => 100})
    assert_in_delta model.weighted_mean, 0.50, 1.0e-9

    # b is 4x heavier → mean is pulled toward 0.80.
    # (0.20 × 100 + 0.80 × 400) / 500 = (20 + 320) / 500 = 0.68.
    model2 = PhenotypeDistribution.build(samples, "repair_efficiency", %{"a" => 100, "b" => 400})
    assert_in_delta model2.weighted_mean, 0.68, 1.0e-9
  end

  test "lineages with zero abundance are dropped (extinct)" do
    samples = [
      trait_sample("alive", 10, %{"repair_efficiency" => 0.40}),
      trait_sample("ghost", 10, %{"repair_efficiency" => 0.99})
    ]

    model = PhenotypeDistribution.build(samples, "repair_efficiency", %{"alive" => 50})
    assert length(model.points) == 1
    assert hd(model.points).id == "alive"
  end

  test "boolean traits map to 0.0 / 1.0" do
    samples = [
      trait_sample("a", 5, %{"biofilm_capable" => false}),
      trait_sample("b", 5, %{"biofilm_capable" => true})
    ]

    model = PhenotypeDistribution.build(samples, "biofilm_capable", %{"a" => 50, "b" => 80})
    xs = model.points |> Enum.map(& &1.x) |> Enum.sort()
    assert xs == [0.0, 1.0]
  end

  test "radius is √abundance — keeps markers legible across orders of magnitude" do
    samples = [
      trait_sample("small", 10, %{"repair_efficiency" => 0.20}),
      trait_sample("big", 10, %{"repair_efficiency" => 0.80})
    ]

    model =
      PhenotypeDistribution.build(samples, "repair_efficiency", %{"small" => 1, "big" => 10_000})

    small = Enum.find(model.points, &(&1.id == "small"))
    big = Enum.find(model.points, &(&1.id == "big"))

    assert_in_delta small.radius, 1.0, 1.0e-9
    assert_in_delta big.radius, 100.0, 1.0e-9
  end

  test "non-phenotype_trait samples are ignored" do
    samples = [
      %TimeSeriesSample{
        kind: "abundance",
        scope_id: "a",
        tick: 10,
        payload: %{"total" => 100}
      },
      trait_sample("a", 10, %{"repair_efficiency" => 0.42})
    ]

    model = PhenotypeDistribution.build(samples, "repair_efficiency", %{"a" => 100})
    assert length(model.points) == 1
  end

  test "trait absent from payload → lineage skipped" do
    samples = [
      trait_sample("a", 10, %{"repair_efficiency" => 0.40}),
      trait_sample("b", 10, %{"base_growth_rate" => 0.10})
    ]

    model = PhenotypeDistribution.build(samples, "repair_efficiency", %{"a" => 100, "b" => 100})
    assert length(model.points) == 1
    assert hd(model.points).id == "a"
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
