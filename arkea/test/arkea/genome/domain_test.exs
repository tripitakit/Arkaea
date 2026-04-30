defmodule Arkea.Genome.DomainTest do
  @moduledoc """
  Property tests for Arkea.Genome.Domain.

  Invariants covered:
  - Domain.new/2 always produces a domain that passes valid?/1
  - valid?/1 and validate/1 are consistent (valid? iff validate == :ok)
  - compute_params always sets :raw_sum key
  - raw_sum is non-negative (weighted sum of non-negative codons with positive weights)
  - Domain built from valid inputs has correct type derived from type_tag
  - codon_length == 3 + length(parameter_codons)
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Arkea.Generators
  alias Arkea.Genome.Codon
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Domain.Type

  # ---------------------------------------------------------------------------
  # Plain unit tests

  test "parameter_codons_range is 10..30" do
    assert Domain.parameter_codons_range() == 10..30
  end

  test "type_tag_length is 3" do
    assert Domain.type_tag_length() == 3
  end

  test "Domain.new/2 raises on empty type_tag" do
    assert_raise ArgumentError, fn -> Domain.new([], Enum.map(1..20, fn _ -> 0 end)) end
  end

  test "Domain.new/2 raises on too-short parameter_codons (< 10)" do
    assert_raise ArgumentError, fn -> Domain.new([0, 0, 0], Enum.map(1..9, fn _ -> 0 end)) end
  end

  test "Domain.new/2 raises on too-long parameter_codons (> 30)" do
    assert_raise ArgumentError, fn -> Domain.new([0, 0, 0], Enum.map(1..31, fn _ -> 0 end)) end
  end

  test "valid?/1 returns false for non-Domain struct" do
    refute Domain.valid?(%{type: :catalytic_site})
    refute Domain.valid?(nil)
    refute Domain.valid?(42)
  end

  # ---------------------------------------------------------------------------
  # Property: Domain.new always produces valid domains

  property "Domain.new/2 with valid inputs always produces a valid domain" do
    # Structural invariant: any domain constructed through the canonical builder
    # Domain.new/2 must pass Domain.valid?/1. This ensures the builder is
    # the single source of correctness — no domain can be in an invalid state
    # after construction.
    check all(
            tag <- Generators.type_tag(),
            params <- Generators.parameter_codons(),
            max_runs: 200
          ) do
      domain = Domain.new(tag, params)
      assert Domain.valid?(domain)
    end
  end

  # ---------------------------------------------------------------------------
  # Property: valid? and validate consistency

  property "valid?/1 == (validate/1 == :ok) for all generated domains" do
    # Architectural invariant: valid?/1 and validate/1 must agree on every
    # generated struct. validate/1 provides the error reason for debugging;
    # valid?/1 is the fast predicate. They must be logically equivalent.
    check all(domain <- Generators.domain(), max_runs: 200) do
      assert Domain.valid?(domain) == (Domain.validate(domain) == :ok)
    end
  end

  # ---------------------------------------------------------------------------
  # Property: params always has :raw_sum

  property "Domain.new/2 always sets :raw_sum in params" do
    check all(
            tag <- Generators.type_tag(),
            params <- Generators.parameter_codons(),
            max_runs: 150
          ) do
      domain = Domain.new(tag, params)
      assert Map.has_key?(domain.params, :raw_sum)
    end
  end

  property "raw_sum is non-negative for all generated domains" do
    # Biological rationale: parameter values are derived from a weighted sum of
    # codons, where codon indices are in 0..19 and all weights are positive.
    # The sum must therefore be >= 0.0 for any valid codon sequence.
    check all(domain <- Generators.domain(), max_runs: 150) do
      assert domain.params.raw_sum >= 0.0
    end
  end

  # ---------------------------------------------------------------------------
  # Property: type derived from type_tag

  property "domain.type == Type.from_type_tag(domain.type_tag)" do
    # The domain type must always be the deterministic function of its type_tag.
    check all(domain <- Generators.domain(), max_runs: 200) do
      assert domain.type == Type.from_type_tag(domain.type_tag)
    end
  end

  # ---------------------------------------------------------------------------
  # Property: codon_length

  property "codon_length == 3 + length(parameter_codons)" do
    check all(domain <- Generators.domain(), max_runs: 150) do
      expected = 3 + length(domain.parameter_codons)
      assert Domain.codon_length(domain) == expected
    end
  end

  # ---------------------------------------------------------------------------
  # Property: compute_params is deterministic

  property "compute_params is deterministic for same domain" do
    check all(domain <- Generators.domain(), max_runs: 100) do
      params1 = Domain.compute_params(domain)
      params2 = Domain.compute_params(domain)
      assert params1 == params2
    end
  end

  # ---------------------------------------------------------------------------
  # Property: domain type_tag length is always 3

  property "domain.type_tag always has exactly 3 codons" do
    check all(domain <- Generators.domain(), max_runs: 150) do
      assert length(domain.type_tag) == 3
    end
  end

  # ---------------------------------------------------------------------------
  # Property: parameter_codons length is in 10..30

  property "domain.parameter_codons length is in 10..30" do
    check all(domain <- Generators.domain(), max_runs: 150) do
      len = length(domain.parameter_codons)
      assert len >= 10 and len <= 30
    end
  end

  # ---------------------------------------------------------------------------
  # Property: all codons in domain are valid

  property "all codons in domain.type_tag and domain.parameter_codons are valid" do
    check all(domain <- Generators.domain(), max_runs: 150) do
      assert Enum.all?(domain.type_tag, &Codon.valid?/1)
      assert Enum.all?(domain.parameter_codons, &Codon.valid?/1)
    end
  end

  # ---------------------------------------------------------------------------
  # Phase 3 properties: type-specific params are present and in valid ranges

  property "compute_params returns :raw_sum plus type-specific keys for every domain type" do
    # Every domain type must produce both :raw_sum and its type-specific keys.
    # This is the core Phase 3 invariant: the generative system maps type + codons
    # to a typed parameter map.
    check all(domain <- Generators.domain(), max_runs: 200) do
      params = domain.params
      assert Map.has_key?(params, :raw_sum), "missing :raw_sum for #{domain.type}"

      assert type_specific_keys_present?(domain.type, params),
             "missing type-specific key(s) for #{domain.type}: #{inspect(params)}"
    end
  end

  property "type-specific float params are within their documented ranges" do
    check all(domain <- Generators.domain(), max_runs: 200) do
      assert type_specific_ranges_valid?(domain.type, domain.params),
             "out-of-range value for #{domain.type}: #{inspect(domain.params)}"
    end
  end

  property "target_metabolite_id and sensed_metabolite_id are in 0..12" do
    check all(domain <- Generators.domain(), max_runs: 200) do
      case domain.type do
        :substrate_binding ->
          assert domain.params.target_metabolite_id in 0..12

        :ligand_sensor ->
          assert domain.params.sensed_metabolite_id in 0..12

        _ ->
          :ok
      end
    end
  end

  property "catalytic_site reaction_class is a valid atom from the 6-class list" do
    reaction_classes = [:hydrolysis, :oxidation, :reduction, :isomerization, :ligation, :lyase]

    check all(domain <- Generators.domain(), max_runs: 150) do
      if domain.type == :catalytic_site do
        assert domain.params.reaction_class in reaction_classes
      end
    end
  end

  property "transmembrane_anchor n_passes is in 1..6" do
    check all(domain <- Generators.domain(), max_runs: 150) do
      if domain.type == :transmembrane_anchor do
        assert domain.params.n_passes in 1..6
      end
    end
  end

  property "structural_fold multimerization_n is in 1..8" do
    check all(domain <- Generators.domain(), max_runs: 150) do
      if domain.type == :structural_fold do
        assert domain.params.multimerization_n in 1..8
      end
    end
  end

  property "regulator_output mode is :activator or :repressor" do
    check all(domain <- Generators.domain(), max_runs: 150) do
      if domain.type == :regulator_output do
        assert domain.params.mode in [:activator, :repressor]
      end
    end
  end

  property "surface_tag tag_class is one of the 3 valid tag atoms" do
    tag_classes = [:pilus_receptor, :phage_receptor, :surface_antigen]

    check all(domain <- Generators.domain(), max_runs: 150) do
      if domain.type == :surface_tag do
        assert domain.params.tag_class in tag_classes
      end
    end
  end

  property "repair_fidelity repair_class is one of the 3 valid repair atoms" do
    repair_classes = [:mismatch, :proofreading, :error_prone]

    check all(domain <- Generators.domain(), max_runs: 150) do
      if domain.type == :repair_fidelity do
        assert domain.params.repair_class in repair_classes
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Phase 3 unit tests: specific domain type-specific param derivation

  test "substrate_binding domain has km in 0.01..100.0" do
    # [5, 0, 0] → sum=5 → rem(5,11)=5 → :energy_coupling — use explicit override
    # Build a substrate_binding via type_tag that maps to index 0.
    # Type 0 = :substrate_binding → type_tag sum rem 11 = 0 → [0, 0, 0]
    domain = Domain.new([0, 0, 0], List.duplicate(10, 20))
    assert domain.type == :substrate_binding
    assert domain.params.km >= 0.01 and domain.params.km <= 100.0
    assert domain.params.target_metabolite_id in 0..12
    assert domain.params.specificity_breadth >= 0.0 and domain.params.specificity_breadth <= 1.0
  end

  test "catalytic_site domain has kcat in 0.0..10.0" do
    # Type 1 = :catalytic_site → type_tag [0,0,1]
    domain = Domain.new([0, 0, 1], List.duplicate(10, 20))
    assert domain.type == :catalytic_site
    assert domain.params.kcat >= 0.0 and domain.params.kcat <= 10.0
    assert is_boolean(domain.params.cofactor_required)
  end

  test "energy_coupling domain has atp_cost in 0.0..5.0" do
    # Type 4 = :energy_coupling → type_tag sum rem 11 = 4 → [0,0,4]
    domain = Domain.new([0, 0, 4], List.duplicate(10, 20))
    assert domain.type == :energy_coupling
    assert domain.params.atp_cost >= 0.0 and domain.params.atp_cost <= 5.0
    assert domain.params.pmf_coupling >= 0.0 and domain.params.pmf_coupling <= 1.0
  end

  # ---------------------------------------------------------------------------
  # Private helpers for Phase 3 property assertions

  defp type_specific_keys_present?(:substrate_binding, params) do
    Map.has_key?(params, :target_metabolite_id) and
      Map.has_key?(params, :km) and
      Map.has_key?(params, :specificity_breadth)
  end

  defp type_specific_keys_present?(:catalytic_site, params) do
    Map.has_key?(params, :reaction_class) and
      Map.has_key?(params, :kcat) and
      Map.has_key?(params, :cofactor_required)
  end

  defp type_specific_keys_present?(:transmembrane_anchor, params) do
    Map.has_key?(params, :hydrophobicity) and Map.has_key?(params, :n_passes)
  end

  defp type_specific_keys_present?(:channel_pore, params) do
    Map.has_key?(params, :selectivity) and Map.has_key?(params, :gating_threshold)
  end

  defp type_specific_keys_present?(:energy_coupling, params) do
    Map.has_key?(params, :atp_cost) and Map.has_key?(params, :pmf_coupling)
  end

  defp type_specific_keys_present?(:dna_binding, params) do
    Map.has_key?(params, :promoter_specificity) and Map.has_key?(params, :binding_affinity)
  end

  defp type_specific_keys_present?(:regulator_output, params) do
    Map.has_key?(params, :mode) and Map.has_key?(params, :cooperativity)
  end

  defp type_specific_keys_present?(:ligand_sensor, params) do
    Map.has_key?(params, :sensed_metabolite_id) and
      Map.has_key?(params, :threshold) and
      Map.has_key?(params, :response_curve)
  end

  defp type_specific_keys_present?(:structural_fold, params) do
    Map.has_key?(params, :stability) and Map.has_key?(params, :multimerization_n)
  end

  defp type_specific_keys_present?(:surface_tag, params), do: Map.has_key?(params, :tag_class)

  defp type_specific_keys_present?(:repair_fidelity, params) do
    Map.has_key?(params, :repair_class) and Map.has_key?(params, :efficiency)
  end

  defp type_specific_ranges_valid?(:substrate_binding, p) do
    p.km >= 0.01 and p.km <= 100.0 and
      p.specificity_breadth >= 0.0 and p.specificity_breadth <= 1.0
  end

  defp type_specific_ranges_valid?(:catalytic_site, p) do
    p.kcat >= 0.0 and p.kcat <= 10.0 and is_boolean(p.cofactor_required)
  end

  defp type_specific_ranges_valid?(:transmembrane_anchor, p) do
    p.hydrophobicity >= 0.0 and p.hydrophobicity <= 1.0 and
      p.n_passes >= 1 and p.n_passes <= 6
  end

  defp type_specific_ranges_valid?(:channel_pore, p) do
    p.selectivity >= 0.0 and p.selectivity <= 1.0 and
      p.gating_threshold >= 0.0 and p.gating_threshold <= 1.0
  end

  defp type_specific_ranges_valid?(:energy_coupling, p) do
    p.atp_cost >= 0.0 and p.atp_cost <= 5.0 and
      p.pmf_coupling >= 0.0 and p.pmf_coupling <= 1.0
  end

  defp type_specific_ranges_valid?(:dna_binding, p) do
    p.promoter_specificity >= 0.0 and p.promoter_specificity <= 1.0 and
      p.binding_affinity >= 0.0 and p.binding_affinity <= 1.0
  end

  defp type_specific_ranges_valid?(:regulator_output, p) do
    p.mode in [:activator, :repressor] and
      p.cooperativity >= 1.0 and p.cooperativity <= 4.0
  end

  defp type_specific_ranges_valid?(:ligand_sensor, p) do
    p.threshold >= 0.0 and p.threshold <= 1.0 and
      p.response_curve in [:linear, :hill, :sigmoidal]
  end

  defp type_specific_ranges_valid?(:structural_fold, p) do
    p.stability >= 0.0 and p.stability <= 1.0 and
      p.multimerization_n >= 1 and p.multimerization_n <= 8
  end

  defp type_specific_ranges_valid?(:surface_tag, p) do
    p.tag_class in [:pilus_receptor, :phage_receptor, :surface_antigen]
  end

  defp type_specific_ranges_valid?(:repair_fidelity, p) do
    p.repair_class in [:mismatch, :proofreading, :error_prone] and
      p.efficiency >= 0.0 and p.efficiency <= 1.0
  end
end
