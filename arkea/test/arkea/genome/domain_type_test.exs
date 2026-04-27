defmodule Arkea.Genome.Domain.TypeTest do
  @moduledoc """
  Property tests for Arkea.Genome.Domain.Type.

  Invariants covered:
  - from_type_tag/1 is deterministic: same 3-codon input -> same output
  - from_type_tag/1 always returns one of the 11 valid types
  - The mapping is total over the valid 3-codon input space
  - Uniformity smoke test: all 11 types appear in a large sample
  - valid?/1 accepts exactly the 11 canonical type atoms
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Arkea.Generators
  alias Arkea.Genome.Domain.Type

  # ---------------------------------------------------------------------------
  # Plain unit tests

  test "all/0 returns exactly 11 types" do
    assert length(Type.all()) == 11
    assert Type.count() == 11
  end

  test "valid?/1 accepts all 11 canonical types" do
    for t <- Type.all() do
      assert Type.valid?(t)
    end
  end

  test "valid?/1 rejects non-types" do
    refute Type.valid?(:not_a_type)
    refute Type.valid?(nil)
    refute Type.valid?(42)
    refute Type.valid?("substrate_binding")
  end

  test "from_type_tag raises on wrong list length" do
    assert_raise ArgumentError, fn -> Type.from_type_tag([0, 1]) end
    assert_raise ArgumentError, fn -> Type.from_type_tag([0, 1, 2, 3]) end
    assert_raise ArgumentError, fn -> Type.from_type_tag([]) end
  end

  test "from_type_tag raises on out-of-range codons" do
    assert_raise ArgumentError, fn -> Type.from_type_tag([0, 1, 20]) end
    assert_raise ArgumentError, fn -> Type.from_type_tag([-1, 0, 0]) end
  end

  # ---------------------------------------------------------------------------
  # Property: determinism

  property "from_type_tag is deterministic: same tag produces same type" do
    # Biological rationale: the genotype-to-domain-type mapping must be purely
    # functional — replaying the same codon sequence always produces the same
    # domain type. This is a prerequisite for deterministic tick computation.
    check all(tag <- Generators.type_tag(), max_runs: 200) do
      type1 = Type.from_type_tag(tag)
      type2 = Type.from_type_tag(tag)
      assert type1 == type2
    end
  end

  property "from_type_tag always returns a valid type" do
    # The mapping must be total over the valid codon domain: every 3-codon
    # sequence resolves to one of the 11 functional domain types without error.
    check all(tag <- Generators.type_tag(), max_runs: 200) do
      result = Type.from_type_tag(tag)
      assert Type.valid?(result)
    end
  end

  # ---------------------------------------------------------------------------
  # Uniformity smoke test (statistical coverage, not a property test)

  test "all 11 types appear in a sample of 1000 type_tags" do
    # Biological rationale: the rem(sum, 11) mapping should distribute roughly
    # uniformly across the 11 types for random codon inputs. This ensures
    # no type is systematically unreachable by mutation alone.
    all_types = Type.all()

    observed =
      Enum.reduce(1..1000, MapSet.new(), fn _, acc ->
        tag = Enum.map(1..3, fn _ -> :rand.uniform(20) - 1 end)
        MapSet.put(acc, Type.from_type_tag(tag))
      end)

    missing = Enum.reject(all_types, &MapSet.member?(observed, &1))

    assert missing == [],
           "Types not observed in 1000 samples: #{inspect(missing)}"
  end

  # ---------------------------------------------------------------------------
  # Property: mathematical correctness of rem-based mapping

  property "from_type_tag maps via rem(sum_of_3_codons, 11)" do
    check all(tag = [a, b, c] <- Generators.type_tag(), max_runs: 200) do
      expected_index = rem(a + b + c, 11)
      expected_type = Enum.at(Type.all(), expected_index)
      assert Type.from_type_tag(tag) == expected_type
    end
  end
end
