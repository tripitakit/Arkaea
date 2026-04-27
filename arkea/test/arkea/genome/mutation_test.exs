defmodule Arkea.Genome.MutationTest do
  @moduledoc """
  Smoke tests and property tests for Arkea.Genome.Mutation.* sub-structs.

  Phase 1 scope: only struct validity is tested (valid?/1 accepts valid
  instances, rejects malformed ones). Application logic (apply/2) is Phase 4.

  Invariants covered:
  - Substitution.valid?/1 accepts structs with old_codon != new_codon
  - Substitution.valid?/1 rejects when old == new
  - Indel.valid?/1 accepts non-empty codon lists for both :insertion and :deletion
  - Duplication.valid?/1 accepts when range_end >= range_start
  - Inversion.valid?/1 accepts when range_end >= range_start
  - Translocation.valid?/1 accepts when source != dest gene_id
  - Translocation.valid?/1 rejects when source == dest
  - Mutation.valid?/1 delegates correctly to sub-struct validators
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Arkea.Generators
  alias Arkea.Genome.Codon
  alias Arkea.Genome.Mutation
  alias Arkea.Genome.Mutation.Duplication
  alias Arkea.Genome.Mutation.Indel
  alias Arkea.Genome.Mutation.Inversion
  alias Arkea.Genome.Mutation.Substitution
  alias Arkea.Genome.Mutation.Translocation

  # ---------------------------------------------------------------------------
  # Substitution smoke tests

  test "Substitution.valid?/1 accepts valid struct" do
    sub = %Substitution{gene_id: Arkea.UUID.v4(), position: 0, old_codon: 0, new_codon: 1}
    assert Substitution.valid?(sub)
    assert Mutation.valid?(sub)
  end

  test "Substitution.valid?/1 rejects when old_codon == new_codon" do
    sub = %Substitution{gene_id: Arkea.UUID.v4(), position: 0, old_codon: 5, new_codon: 5}
    refute Substitution.valid?(sub)
    refute Mutation.valid?(sub)
  end

  test "Substitution.valid?/1 rejects invalid codon values" do
    sub = %Substitution{gene_id: Arkea.UUID.v4(), position: 0, old_codon: 20, new_codon: 1}
    refute Substitution.valid?(sub)
  end

  test "Substitution.valid?/1 rejects non-binary gene_id" do
    refute Substitution.valid?(%Substitution{
             gene_id: 123,
             position: 0,
             old_codon: 0,
             new_codon: 1
           })
  end

  # ---------------------------------------------------------------------------
  # Indel smoke tests

  test "Indel.valid?/1 accepts insertion with valid codons" do
    indel = %Indel{
      gene_id: Arkea.UUID.v4(),
      position: 5,
      kind: :insertion,
      codons: [0, 1, 2]
    }

    assert Indel.valid?(indel)
    assert Mutation.valid?(indel)
  end

  test "Indel.valid?/1 accepts deletion with valid codons" do
    indel = %Indel{
      gene_id: Arkea.UUID.v4(),
      position: 0,
      kind: :deletion,
      codons: [19]
    }

    assert Indel.valid?(indel)
  end

  test "Indel.valid?/1 rejects empty codon list" do
    indel = %Indel{
      gene_id: Arkea.UUID.v4(),
      position: 0,
      kind: :insertion,
      codons: []
    }

    refute Indel.valid?(indel)
  end

  test "Indel.valid?/1 rejects invalid kind" do
    indel = %Indel{
      gene_id: Arkea.UUID.v4(),
      position: 0,
      kind: :mutation,
      codons: [0]
    }

    refute Indel.valid?(indel)
  end

  # ---------------------------------------------------------------------------
  # Duplication smoke tests

  test "Duplication.valid?/1 accepts valid struct where range_end >= range_start" do
    dup = %Duplication{
      gene_id: Arkea.UUID.v4(),
      range_start: 2,
      range_end: 10,
      insert_at: 20
    }

    assert Duplication.valid?(dup)
    assert Mutation.valid?(dup)
  end

  test "Duplication.valid?/1 accepts zero-length range (range_start == range_end)" do
    dup = %Duplication{
      gene_id: Arkea.UUID.v4(),
      range_start: 5,
      range_end: 5,
      insert_at: 10
    }

    assert Duplication.valid?(dup)
  end

  test "Duplication.valid?/1 rejects range_end < range_start" do
    refute Duplication.valid?(%Duplication{
             gene_id: Arkea.UUID.v4(),
             range_start: 10,
             range_end: 5,
             insert_at: 0
           })
  end

  # ---------------------------------------------------------------------------
  # Inversion smoke tests

  test "Inversion.valid?/1 accepts valid struct" do
    inv = %Inversion{gene_id: Arkea.UUID.v4(), range_start: 0, range_end: 10}
    assert Inversion.valid?(inv)
    assert Mutation.valid?(inv)
  end

  test "Inversion.valid?/1 accepts zero-length range" do
    inv = %Inversion{gene_id: Arkea.UUID.v4(), range_start: 3, range_end: 3}
    assert Inversion.valid?(inv)
  end

  test "Inversion.valid?/1 rejects range_end < range_start" do
    inv = %Inversion{gene_id: Arkea.UUID.v4(), range_start: 10, range_end: 9}
    refute Inversion.valid?(inv)
  end

  # ---------------------------------------------------------------------------
  # Translocation smoke tests

  test "Translocation.valid?/1 accepts valid struct with different source and dest" do
    trans = %Translocation{
      source_gene_id: Arkea.UUID.v4(),
      dest_gene_id: Arkea.UUID.v4(),
      source_range: {0, 5},
      dest_position: 10
    }

    assert Translocation.valid?(trans)
    assert Mutation.valid?(trans)
  end

  test "Translocation.valid?/1 rejects when source == dest" do
    id = Arkea.UUID.v4()

    trans = %Translocation{
      source_gene_id: id,
      dest_gene_id: id,
      source_range: {0, 5},
      dest_position: 10
    }

    refute Translocation.valid?(trans)
  end

  test "Translocation.valid?/1 rejects range_end < range_start" do
    trans = %Translocation{
      source_gene_id: Arkea.UUID.v4(),
      dest_gene_id: Arkea.UUID.v4(),
      source_range: {10, 5},
      dest_position: 0
    }

    refute Translocation.valid?(trans)
  end

  # ---------------------------------------------------------------------------
  # Mutation.valid?/1 rejects non-mutation values

  test "Mutation.valid?/1 rejects non-mutation structs" do
    refute Mutation.valid?(%{kind: :substitution})
    refute Mutation.valid?(nil)
    refute Mutation.valid?(42)
    refute Mutation.valid?("mutation")
  end

  # ---------------------------------------------------------------------------
  # Property: generated substitutions are always valid

  property "all generated Substitution structs pass Substitution.valid?/1" do
    check all(sub <- Generators.substitution(), max_runs: 200) do
      assert Substitution.valid?(sub)
      assert Mutation.valid?(sub)
    end
  end

  property "generated Substitution always has old_codon != new_codon" do
    check all(sub <- Generators.substitution(), max_runs: 200) do
      assert sub.old_codon != sub.new_codon
    end
  end

  # ---------------------------------------------------------------------------
  # Property: generated indels are always valid

  property "all generated Indel structs pass Indel.valid?/1" do
    check all(indel <- Generators.indel(), max_runs: 150) do
      assert Indel.valid?(indel)
      assert Mutation.valid?(indel)
    end
  end

  property "generated Indel always has non-empty valid codons list" do
    check all(indel <- Generators.indel(), max_runs: 150) do
      assert indel.codons != []
      assert Enum.all?(indel.codons, &Codon.valid?/1)
    end
  end

  # ---------------------------------------------------------------------------
  # Property: generated duplications are always valid

  property "all generated Duplication structs pass Duplication.valid?/1" do
    check all(dup <- Generators.duplication(), max_runs: 150) do
      assert Duplication.valid?(dup)
      assert Mutation.valid?(dup)
    end
  end

  property "generated Duplication always has range_end >= range_start" do
    check all(dup <- Generators.duplication(), max_runs: 150) do
      assert dup.range_end >= dup.range_start
    end
  end

  # ---------------------------------------------------------------------------
  # Property: generated inversions are always valid

  property "all generated Inversion structs pass Inversion.valid?/1" do
    check all(inv <- Generators.inversion(), max_runs: 150) do
      assert Inversion.valid?(inv)
      assert Mutation.valid?(inv)
    end
  end

  # ---------------------------------------------------------------------------
  # Property: generated translocations are always valid

  property "all generated Translocation structs pass Translocation.valid?/1" do
    check all(trans <- Generators.translocation(), max_runs: 150) do
      assert Translocation.valid?(trans)
      assert Mutation.valid?(trans)
    end
  end

  property "generated Translocation always has source_gene_id != dest_gene_id" do
    check all(trans <- Generators.translocation(), max_runs: 150) do
      assert trans.source_gene_id != trans.dest_gene_id
    end
  end
end
