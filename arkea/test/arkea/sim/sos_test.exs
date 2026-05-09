defmodule Arkea.Sim.SosTest do
  @moduledoc """
  Property + unit tests for Phase 17 SOS response and error
  catastrophe (01-DESIGN.md Block 8).
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Arkea.Ecology.Lineage
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
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
    # The Eigen criterion is (1 − µ/L)^L > 1/σ; with σ = 2 the
    # critical per-cell µ is ≈ ln(2) ≈ 0.693, essentially independent
    # of L for moderate L. Tests pick µ values below / above that
    # threshold rather than the legacy `µ × L > 1` mental model.
    test "zero below the Eigen threshold" do
      assert Mutator.error_catastrophe_lethality(0.001, 50) == 0.0
      assert Mutator.error_catastrophe_lethality(0.3, 50) == 0.0
    end

    test "non-zero above the threshold" do
      result = Mutator.error_catastrophe_lethality(2.0, 100)
      assert result > 0.0
      assert result <= 1.0
    end

    test "saturates near 1 well above the Eigen threshold" do
      assert Mutator.error_catastrophe_lethality(10.0, 100) > 0.99
    end

    property "always in [0, 1] for valid inputs" do
      check all(
              mu <- StreamData.float(min: 0.0, max: 5.0),
              genome_size <- StreamData.integer(1..200),
              max_runs: 100
            ) do
        result = Mutator.error_catastrophe_lethality(mu, genome_size)
        assert result >= 0.0
        assert result <= 1.0
      end
    end
  end

  describe "Mutator.sos_threshold/1 (Phase 25.5 / 7.6)" do
    # type_tag [0,0,7] → rem(7,11) = 7 → :ligand_sensor.
    defp ligand_sensor_gene(weights, signal_key) when length(weights) == 20 do
      base = Domain.new([0, 0, 7], weights)
      sensor = %{base | params: Map.put(base.params, :signal_key, signal_key)}
      Gene.from_domains([sensor])
    end

    defp catalytic_gene do
      Gene.from_domains([Domain.new([0, 0, 1], List.duplicate(10, 20))])
    end

    defp founder(genome), do: Lineage.new_founder(genome, %{phase_1: 100}, 0)

    test "lineage with no :ligand_sensor → legacy default threshold" do
      lineage = founder(Genome.new([catalytic_gene()]))
      assert Mutator.sos_threshold(lineage) == Mutator.sos_active_threshold()
    end

    test "ligand_sensor without dna_damage signal_key → legacy default" do
      gene = ligand_sensor_gene(List.duplicate(10, 20), "qs_signal_xyz")
      lineage = founder(Genome.new([gene]))
      assert Mutator.sos_threshold(lineage) == Mutator.sos_active_threshold()
    end

    test "single SOS sensor → threshold scaled by Lineage.dna_damage_max/0" do
      # A ligand_sensor with parameter codons all = 5 → raw_sum bounded
      # → threshold normalised to a known fraction; the absolute value
      # is `threshold × dna_damage_max`, so we assert the multiplicative
      # relation rather than a hard-coded number.
      gene = ligand_sensor_gene(List.duplicate(5, 20), "dna_damage")
      [sensor_dom] = hd(gene.domains) |> List.wrap()
      lineage = founder(Genome.new([gene]))

      sensor_threshold_param = sensor_dom.params.threshold
      expected = sensor_threshold_param * Lineage.dna_damage_max()

      assert_in_delta Mutator.sos_threshold(lineage), expected, 1.0e-9
    end

    test "multiple SOS sensors → minimum threshold wins (most-sensitive sensor)" do
      low_sensor = ligand_sensor_gene(List.duplicate(2, 20), "dna_damage")
      high_sensor = ligand_sensor_gene(List.duplicate(18, 20), "dna_damage")

      lineage = founder(Genome.new([low_sensor, high_sensor]))

      [low_dom] = hd(low_sensor.domains) |> List.wrap()
      [high_dom] = hd(high_sensor.domains) |> List.wrap()

      expected =
        min(low_dom.params.threshold, high_dom.params.threshold) * Lineage.dna_damage_max()

      assert_in_delta Mutator.sos_threshold(lineage), expected, 1.0e-9
    end

    test "lineage with genome: nil → legacy default" do
      lineage = founder(Genome.new([catalytic_gene()]))
      delta_only = %{lineage | genome: nil}
      assert Mutator.sos_threshold(delta_only) == Mutator.sos_active_threshold()
    end
  end

  describe "Mutator.sos_active?/2 (Phase 25.5 / 7.6)" do
    test "respects the supplied threshold instead of the legacy default" do
      # Strict threshold (10× legacy default) — only severe damage activates.
      strict = Mutator.sos_active_threshold() * 10.0
      refute Mutator.sos_active?(0.5, strict)
      assert Mutator.sos_active?(strict + 0.01, strict)
    end

    test "1-arity form is equivalent to 2-arity with legacy default" do
      damage = 0.30

      assert Mutator.sos_active?(damage) ==
               Mutator.sos_active?(damage, Mutator.sos_active_threshold())
    end
  end
end
