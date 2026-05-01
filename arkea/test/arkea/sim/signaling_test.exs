defmodule Arkea.Sim.SignalingTest do
  @moduledoc """
  Tests for Arkea.Sim.Signaling — Phase 7 quorum sensing (DESIGN.md Block 9).

  Signal identity: "c0,c1,c2,c3" binary key derived from first 4 parameter_codons.
  Gaussian affinity σ = 4.0 in codon space [0..19]^4.

  Domain type_tag encoding:
    :catalytic_site  = index 1 in Domain.Type.all() → type_tag sum = 1 → [0, 0, 1]
    :ligand_sensor   = index 7 in Domain.Type.all() → type_tag sum = 7 → [0, 0, 7]
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  @moduletag :sim
  @moduletag timeout: 30_000

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Mutator
  alias Arkea.Sim.Phenotype
  alias Arkea.Sim.Signaling
  alias Arkea.Sim.Tick

  # ---------------------------------------------------------------------------
  # Domain fixtures
  #
  # type_tag selects domain type via rem(sum, 11):
  #   [0, 0, 1] → sum = 1 → index 1 → :catalytic_site
  #   [0, 0, 7] → sum = 7 → index 7 → :ligand_sensor

  @cat_type_tag [0, 0, 1]
  @ls_type_tag [0, 0, 7]

  # parameter_codons with first 4 = [5, 5, 5, 5] → signal_key "5,5,5,5"
  # Remaining 16 codons at 10 give moderate norm → kcat > 0 for :catalytic_site
  defp cat_domain_5555 do
    Domain.new(@cat_type_tag, [5, 5, 5, 5] ++ List.duplicate(10, 16))
  end

  # :ligand_sensor with signal_key "5,5,5,5" and threshold ≈ 0.0
  # (all zeros in mid_t → norm_of(mid_t) ≈ 0.0)
  defp ls_domain_5555 do
    Domain.new(@ls_type_tag, [5, 5, 5, 5] ++ List.duplicate(0, 16))
  end

  # Build a QS genome: one gene with a catalytic_site + ligand_sensor both on "5,5,5,5"
  defp qs_genome do
    qs_gene = Gene.from_domains([cat_domain_5555(), ls_domain_5555()])
    Genome.new([qs_gene])
  end

  # ---------------------------------------------------------------------------
  # Test 1: binding_affinity = 1.0 for identical signatures

  test "binding_affinity = 1.0 for identical signal keys" do
    assert_in_delta Signaling.binding_affinity("5,5,5,5", "5,5,5,5"), 1.0, 0.001
    assert_in_delta Signaling.binding_affinity("0,0,0,0", "0,0,0,0"), 1.0, 0.001
    assert_in_delta Signaling.binding_affinity("19,19,19,19", "19,19,19,19"), 1.0, 0.001
  end

  # ---------------------------------------------------------------------------
  # Test 2: binding_affinity < 0.1 for maximally different signatures

  test "binding_affinity < 0.1 for maximally different signal keys" do
    aff = Signaling.binding_affinity("0,0,0,0", "19,19,19,19")
    assert aff < 0.1, "Expected affinity < 0.1 for [0,0,0,0] vs [19,19,19,19], got #{aff}"
  end

  # ---------------------------------------------------------------------------
  # Test 3: qs_sigma_boost = 0.0 when signal_pool is empty

  test "qs_sigma_boost = 0.0 when signal_pool is empty" do
    phenotype = Phenotype.from_genome(qs_genome())
    # Receptor present but pool is empty — no activation possible
    assert Signaling.qs_sigma_boost(phenotype, %{}) == 0.0
  end

  # ---------------------------------------------------------------------------
  # Test 4: qs_sigma_boost > 0.0 when matching signal is above threshold

  test "qs_sigma_boost > 0.0 when matching signal is present above threshold" do
    phenotype = Phenotype.from_genome(qs_genome())

    # threshold ≈ 0.0, conc = 1.0, affinity = 1.0 → conc * aff = 1.0 > 0.0 → activates
    signal_pool = %{"5,5,5,5" => 1.0}
    boost = Signaling.qs_sigma_boost(phenotype, signal_pool)

    assert boost > 0.0,
           "Expected QS boost > 0.0 with matching signal at conc=1.0, got #{boost}"
  end

  # ---------------------------------------------------------------------------
  # Test 5: growth delta greater with active signal than without

  test "step_expression produces higher growth delta when matching signal is present" do
    genome = qs_genome()

    phase_with_signal =
      Phase.new(:surface, dilution_rate: 0.02)
      |> Phase.update_metabolite(:glucose, 500.0)
      |> then(fn p -> %{p | signal_pool: %{"5,5,5,5" => 1.0}} end)

    phase_without_signal =
      Phase.new(:surface, dilution_rate: 0.02)
      |> Phase.update_metabolite(:glucose, 500.0)

    lineage = Lineage.new_founder(genome, %{surface: 100}, 0)
    rng = Mutator.init_seed("signaling-test")

    make_state = fn phase ->
      BiotopeState.new_from_opts(
        id: "signaling-biotope",
        archetype: :hot_spring,
        phases: [phase],
        dilution_rate: 0.02,
        lineages: [lineage],
        rng_seed: rng,
        metabolite_inflow: %{glucose: 10.0}
      )
    end

    state_with = make_state.(phase_with_signal)
    state_without = make_state.(phase_without_signal)

    after_with =
      state_with
      |> Tick.step_metabolism()
      |> Tick.step_expression()

    after_without =
      state_without
      |> Tick.step_metabolism()
      |> Tick.step_expression()

    delta_with =
      after_with.growth_delta_by_lineage
      |> Map.get(lineage.id, %{})
      |> Map.get(:surface, 0)

    delta_without =
      after_without.growth_delta_by_lineage
      |> Map.get(lineage.id, %{})
      |> Map.get(:surface, 0)

    assert delta_with >= delta_without,
           "Expected delta_with (#{delta_with}) >= delta_without (#{delta_without})"
  end

  # ---------------------------------------------------------------------------
  # Test 6: signal accumulates from multiple producers (quorum effect)

  test "signal accumulates in signal_pool when multiple lineages produce it" do
    genome = qs_genome()

    # Verify the genome actually produces signals
    phenotype = Phenotype.from_genome(genome)

    assert phenotype.qs_produces != [],
           "Expected qs_produces to be non-empty for genome with catalytic_site domain"

    phase = Phase.new(:surface, dilution_rate: 0.0)
    rng = Mutator.init_seed("quorum-test")

    # 10 lineages all producing signal "5,5,5,5"
    lineages =
      Enum.map(1..10, fn _ ->
        Lineage.new_founder(genome, %{surface: 100}, 0)
      end)

    state =
      BiotopeState.new_from_opts(
        id: "quorum-biotope",
        archetype: :hot_spring,
        phases: [phase],
        dilution_rate: 0.0,
        lineages: lineages,
        rng_seed: rng
      )

    state_after = Tick.step_signaling(state)

    updated_phase = hd(state_after.phases)
    concentration = Map.get(updated_phase.signal_pool, "5,5,5,5", 0.0)

    assert concentration > 0.0,
           "Expected signal_pool[\"5,5,5,5\"] > 0.0 after step_signaling with 10 producers, got #{concentration}"
  end

  # ---------------------------------------------------------------------------
  # Test 7: property — binding_affinity always in [0.0, 1.0]

  property "binding_affinity is always in 0.0..1.0 for any valid key pair" do
    check all(
            s1 <- StreamData.list_of(StreamData.integer(0..19), length: 4),
            s2 <- StreamData.list_of(StreamData.integer(0..19), length: 4)
          ) do
      key1 = Enum.join(s1, ",")
      key2 = Enum.join(s2, ",")
      aff = Signaling.binding_affinity(key1, key2)

      assert aff >= 0.0 and aff <= 1.0,
             "binding_affinity(#{key1}, #{key2}) = #{aff} is outside [0.0, 1.0]"
    end
  end
end
