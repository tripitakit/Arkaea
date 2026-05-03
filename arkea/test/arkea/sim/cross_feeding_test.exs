defmodule Arkea.Sim.CrossFeedingTest do
  @moduledoc """
  Tests for Phase 18 cross-feeding closure (DESIGN.md Block 8 Phase 18).

  The metabolite pool acts as a *closed* C/N/S/Fe/H₂ cycle: each
  consumed substrate releases a stoichiometric by-product back into
  the pool, allowing one lineage's waste to become another lineage's
  food. Without these tests the metabolic specialisation of Phase 6
  Block 6 stays purely consumptive — which is biologically wrong
  for any community.
  """
  use ExUnit.Case, async: true

  alias Arkea.Sim.Metabolism

  describe "Metabolism.byproducts/1" do
    test "glucose produces acetate, CO₂, and H₂" do
      products = Metabolism.byproducts(:glucose)

      assert Map.has_key?(products, :acetate)
      assert Map.has_key?(products, :co2)
      assert Map.has_key?(products, :h2)
      assert products.acetate > 0.0
    end

    test "acetate produces only CO₂ (terminal C oxidation)" do
      products = Metabolism.byproducts(:acetate)
      assert Map.keys(products) == [:co2]
    end

    test "lactate produces acetate, CO₂, and H₂ (syntrophic fermentation)" do
      products = Metabolism.byproducts(:lactate)
      assert Map.has_key?(products, :acetate)
      assert Map.has_key?(products, :h2)
    end

    test "sulfate reduction yields H₂S" do
      assert Map.has_key?(Metabolism.byproducts(:so4), :h2s)
    end

    test "sulfide oxidation yields SO₄ — the closing leg of the S cycle" do
      assert Map.has_key?(Metabolism.byproducts(:h2s), :so4)
    end

    test "ammonia oxidation yields NO₃ (nitrification)" do
      assert Map.has_key?(Metabolism.byproducts(:nh3), :no3)
    end

    test "nitrate reduction yields NH₃ (denitrification → ammonification)" do
      assert Map.has_key?(Metabolism.byproducts(:no3), :nh3)
    end

    test "methane oxidation yields CO₂ (methanotrophy)" do
      assert Map.has_key?(Metabolism.byproducts(:ch4), :co2)
    end

    test "CO₂ reduction yields CH₄ (autotrophic methanogenesis)" do
      assert Map.has_key?(Metabolism.byproducts(:co2), :ch4)
    end

    test "non-metabolic substrates (oxygen, iron, po4) have no byproduct" do
      assert Metabolism.byproducts(:oxygen) == %{}
      assert Metabolism.byproducts(:iron) == %{}
      assert Metabolism.byproducts(:po4) == %{}
    end
  end

  describe "Metabolism.compute_byproducts/1" do
    test "empty uptake yields empty byproducts" do
      assert Metabolism.compute_byproducts(%{}) == %{}
    end

    test "scales linearly in substrate consumption" do
      small = Metabolism.compute_byproducts(%{glucose: 10.0})
      large = Metabolism.compute_byproducts(%{glucose: 100.0})

      Enum.each(small, fn {product, value} ->
        assert_in_delta large[product], value * 10.0, 1.0e-9
      end)
    end

    test "multiple substrates accumulate independently" do
      products = Metabolism.compute_byproducts(%{glucose: 10.0, h2s: 10.0})

      assert Map.has_key?(products, :acetate)
      assert Map.has_key?(products, :so4)
    end

    test "two substrates that yield the same product compose additively" do
      products = Metabolism.compute_byproducts(%{glucose: 10.0, lactate: 10.0})

      acetate_from_glucose = 10.0 * Metabolism.byproducts(:glucose).acetate
      acetate_from_lactate = 10.0 * Metabolism.byproducts(:lactate).acetate

      assert_in_delta products.acetate, acetate_from_glucose + acetate_from_lactate, 1.0e-9
    end
  end
end
