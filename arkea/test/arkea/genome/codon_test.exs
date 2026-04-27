defmodule Arkea.Genome.CodonTest do
  @moduledoc """
  Property tests for Arkea.Genome.Codon.

  Invariants covered:
  - valid?/1 accepts exactly integers in 0..19
  - weighted_sum/1 is deterministic and non-negative for valid codon lists
  - to_atom/1 and from_atom/1 are inverses on the valid domain
  - validate/2 correctly checks codon range and list length constraints
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Arkea.Generators
  alias Arkea.Genome.Codon

  # ---------------------------------------------------------------------------
  # Plain unit tests

  test "symbol count is 20" do
    assert Codon.symbol_count() == 20
    assert length(Codon.symbols()) == 20
  end

  test "weights count is 20" do
    assert length(Codon.weights()) == 20
  end

  test "valid?/1 accepts boundary codons 0 and 19" do
    assert Codon.valid?(0)
    assert Codon.valid?(19)
  end

  test "valid?/1 rejects boundary violations" do
    refute Codon.valid?(-1)
    refute Codon.valid?(20)
    refute Codon.valid?(1.0)
    refute Codon.valid?(:ala)
    refute Codon.valid?(nil)
  end

  test "weighted_sum of empty list is 0.0" do
    assert Codon.weighted_sum([]) == 0.0
  end

  test "to_atom and from_atom round-trip for fixed examples" do
    assert Codon.from_atom(:ala) == 0
    assert Codon.to_atom(0) == :ala
    assert Codon.from_atom(:val) == 19
    assert Codon.to_atom(19) == :val
  end

  # ---------------------------------------------------------------------------
  # Property: codon range

  property "valid?/1 is true iff integer in 0..19" do
    check all(value <- StreamData.integer(), max_runs: 200) do
      expected = value >= 0 and value <= 19
      assert Codon.valid?(value) == expected
    end
  end

  property "valid?/1 rejects all non-integers" do
    non_integer_gen =
      StreamData.one_of([
        StreamData.float(),
        StreamData.binary(),
        StreamData.atom(:alphanumeric),
        StreamData.list_of(StreamData.integer(0..19), max_length: 5),
        StreamData.constant(nil),
        StreamData.constant(true)
      ])

    check all(value <- non_integer_gen, max_runs: 100) do
      refute Codon.valid?(value)
    end
  end

  # ---------------------------------------------------------------------------
  # Property: weighted_sum determinism and non-negativity

  property "weighted_sum is deterministic: same list produces same result" do
    check all(codons <- Generators.codon_list(0..30), max_runs: 100) do
      result1 = Codon.weighted_sum(codons)
      result2 = Codon.weighted_sum(codons)
      assert result1 == result2
    end
  end

  property "weighted_sum is non-negative for any valid codon list" do
    check all(codons <- Generators.codon_list(0..50), max_runs: 200) do
      assert Codon.weighted_sum(codons) >= 0.0
    end
  end

  # ---------------------------------------------------------------------------
  # Property: to_atom / from_atom round-trip

  property "from_atom(to_atom(c)) == c for all valid codons" do
    check all(codon <- Generators.codon(), max_runs: 50) do
      assert Codon.from_atom(Codon.to_atom(codon)) == codon
    end
  end

  property "to_atom(from_atom(sym)) == sym for all 20 symbols" do
    check all(sym <- StreamData.member_of(Codon.symbols()), max_runs: 50) do
      assert Codon.to_atom(Codon.from_atom(sym)) == sym
    end
  end

  # ---------------------------------------------------------------------------
  # Property: validate/2

  property "validate/2 with :any accepts any valid codon list" do
    check all(codons <- Generators.codon_list(0..40), max_runs: 100) do
      assert Codon.validate(codons, :any) == :ok
    end
  end

  property "validate/2 with explicit range accepts when length is exactly in range" do
    check all(
            len <- StreamData.integer(1..30),
            codons <- StreamData.list_of(Generators.codon(), length: len),
            max_runs: 100
          ) do
      assert Codon.validate(codons, len..len) == :ok
    end
  end

  property "validate/2 rejects list with out-of-range codon" do
    invalid_codon_gen =
      StreamData.one_of([
        StreamData.integer(20..100),
        StreamData.integer(-100..-1)
      ])

    check all(
            bad_codon <- invalid_codon_gen,
            good_codons <- Generators.codon_list(0..10),
            max_runs: 100
          ) do
      codons = [bad_codon | good_codons]
      assert {:error, :invalid_codon} = Codon.validate(codons)
    end
  end

  property "validate/2 returns :not_a_list for non-list input" do
    check all(
            value <- StreamData.one_of([StreamData.integer(), StreamData.binary()]),
            max_runs: 100
          ) do
      assert {:error, :not_a_list} = Codon.validate(value)
    end
  end
end
