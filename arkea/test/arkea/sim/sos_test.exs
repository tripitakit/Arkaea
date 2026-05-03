defmodule Arkea.Sim.SosTest do
  @moduledoc """
  Property + unit tests for Phase 17 SOS response and error
  catastrophe (DESIGN.md Block 8).
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Arkea.Sim.Mutator

  describe "Mutator.sos_active?/1" do
    test "false at zero damage" do
      refute Mutator.sos_active?(0.0)
    end

    test "false at exactly threshold-minus-epsilon" do
      refute Mutator.sos_active?(Mutator.sos_active_threshold() - 1.0e-9)
    end

    test "true at and above threshold" do
      assert Mutator.sos_active?(Mutator.sos_active_threshold())
      assert Mutator.sos_active?(Mutator.sos_active_threshold() + 0.1)
    end
  end

  describe "Mutator.mutation_probability/3" do
    test "matches the 2-arg form when damage = 0" do
      legacy = Mutator.mutation_probability(100, 0.5)
      sos_aware = Mutator.mutation_probability(100, 0.5, 0.0)
      assert sos_aware == legacy
    end

    test "exceeds the 2-arg form when SOS is active" do
      legacy = Mutator.mutation_probability(100, 0.5)
      sos = Mutator.mutation_probability(100, 0.5, 1.0)
      assert sos > legacy
      assert sos / legacy >= 2.0
    end

    test "stays clamped at @max_probability under extreme damage" do
      result = Mutator.mutation_probability(10_000, 0.0, 5.0)
      assert result <= 0.95
    end
  end

  describe "Mutator.dna_damage_increment/4" do
    test "zero replications yield zero increment" do
      assert Mutator.dna_damage_increment(0.5, 0, 200, 0.0) == 0.0
    end

    test "zero abundance yields zero increment" do
      assert Mutator.dna_damage_increment(0.5, 100, 0, 0.0) == 0.0
    end

    test "increment is per-cell-rate scaled" do
      # Two scenarios with the same growth_rate (0.3) should produce
      # the same per-cell increment regardless of population size.
      small = Mutator.dna_damage_increment(0.5, 30, 100, 0.0)
      large = Mutator.dna_damage_increment(0.5, 300, 1_000, 0.0)
      assert_in_delta small, large, 1.0e-9
    end

    test "low repair efficiency yields higher damage" do
      mutator = Mutator.dna_damage_increment(0.1, 100, 1_000, 0.0)
      wild_type = Mutator.dna_damage_increment(0.9, 100, 1_000, 0.0)
      assert mutator > wild_type
    end

    test "active SOS compounds the increment" do
      pre_sos = Mutator.dna_damage_increment(0.5, 100, 1_000, 0.0)
      post_sos = Mutator.dna_damage_increment(0.5, 100, 1_000, 1.0)
      assert post_sos == pre_sos * 1.5
    end
  end

  describe "Mutator.decay_damage/1" do
    test "decays at the fixed rate" do
      assert Mutator.decay_damage(1.0) == 1.0 - Mutator.dna_damage_decay()
    end

    test "clamped at zero" do
      assert Mutator.decay_damage(0.01) == 0.0
    end
  end

  describe "Mutator.error_catastrophe_lethality/2" do
    test "zero below the Eigen threshold" do
      assert Mutator.error_catastrophe_lethality(0.001, 50) == 0.0
    end

    test "non-zero above the threshold" do
      result = Mutator.error_catastrophe_lethality(0.05, 100)
      assert result > 0.0
      assert result <= 1.0
    end

    test "saturates near 1 at extreme µ × genome_size" do
      assert Mutator.error_catastrophe_lethality(0.5, 100) > 0.99
    end

    property "always in [0, 1] for valid inputs" do
      check all(
              mu <- StreamData.float(min: 0.0, max: 0.5),
              genome_size <- StreamData.integer(1..200),
              max_runs: 100
            ) do
        result = Mutator.error_catastrophe_lethality(mu, genome_size)
        assert result >= 0.0
        assert result <= 1.0
      end
    end

    property "monotonic in genome size above the threshold" do
      check all(
              mu <- StreamData.float(min: 0.05, max: 0.30),
              max_runs: 50
            ) do
        small = Mutator.error_catastrophe_lethality(mu, 50)
        large = Mutator.error_catastrophe_lethality(mu, 200)
        assert large >= small
      end
    end
  end
end
