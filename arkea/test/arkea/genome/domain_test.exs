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
end
