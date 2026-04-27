defmodule Arkea.Genome.GeneTest do
  @moduledoc """
  Property tests for Arkea.Genome.Gene.

  Invariants covered:
  - from_domains/1 produces a gene where codons == concat of each domain's type_tag ++ parameter_codons
  - from_codons/1 succeeds iff length(codons) is a multiple of 23 in 23..207
  - from_codons/1 produces gene.codons == input codons (source of truth)
  - reparse/1 reconstructs the same domains as the original parse
  - Gene round-trip: from_domains -> codons -> from_codons -> domains produces equal domains
  - valid?/1 and validate/1 agree on all generated genes
  - domain_count == length(codons) / 23 for Phase 1 genes
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Arkea.Generators
  alias Arkea.Genome.Codon
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene

  # ---------------------------------------------------------------------------
  # Plain unit tests

  test "min codons is 23 (1 domain), max is 207 (9 domains)" do
    assert Gene.codons_range() == 23..207
    assert Gene.phase1_domain_codon_length() == 23
    assert Gene.phase1_param_codons_length() == 20
  end

  test "from_domains/1 raises on empty list" do
    assert_raise ArgumentError, fn -> Gene.from_domains([]) end
  end

  test "from_codons/1 returns error for non-list" do
    assert Gene.from_codons("not a list") == {:error, :not_a_list}
  end

  test "from_codons/1 returns error for non-multiple-of-23 length" do
    assert {:error, :codon_count_not_phase1_aligned} =
             Gene.from_codons(Enum.map(1..24, fn _ -> 0 end))
  end

  test "from_codons/1 returns error for codons below minimum length" do
    # 22 codons < 23 minimum
    codons = Enum.map(1..22, fn _ -> 0 end)
    assert {:error, _} = Gene.from_codons(codons)
  end

  test "from_codons/1 returns error for out-of-range codons" do
    # 23 codons but with a codon value of 20 (out of range)
    codons = List.duplicate(0, 22) ++ [20]
    assert {:error, :invalid_codon} = Gene.from_codons(codons)
  end

  test "valid?/1 rejects non-Gene struct" do
    refute Gene.valid?(%{codons: []})
    refute Gene.valid?(nil)
  end

  # ---------------------------------------------------------------------------
  # Property: from_codons source of truth

  property "Gene.from_codons/1 produces gene.codons == input codons" do
    # codons is the canonical source of truth in a Gene struct. The from_codons
    # constructor must faithfully preserve the input codon sequence.
    check all(
            n <- StreamData.integer(1..9),
            codons <- StreamData.list_of(Generators.codon(), length: n * 23),
            max_runs: 150
          ) do
      {:ok, gene} = Gene.from_codons(codons)
      assert gene.codons == codons
    end
  end

  # ---------------------------------------------------------------------------
  # Property: from_domains codons correctness

  property "Gene.from_domains/1 produces codons == concat of each domain's type_tag ++ params" do
    # The codon sequence of a gene built from domains must be the exact
    # concatenation of each domain's (type_tag ++ parameter_codons).
    check all(
            n <- StreamData.integer(1..9),
            domains <- StreamData.list_of(Generators.domain_phase1(), length: n),
            max_runs: 150
          ) do
      gene = Gene.from_domains(domains)

      expected_codons =
        Enum.flat_map(domains, fn %Domain{type_tag: tag, parameter_codons: pc} ->
          tag ++ pc
        end)

      assert gene.codons == expected_codons
    end
  end

  # ---------------------------------------------------------------------------
  # Property: gene round-trip

  property "from_domains -> from_codons round-trip reconstructs equal domains" do
    # Phase 1 gene round-trip invariant: building a gene from Phase1-compatible
    # domains and then re-parsing the resulting codon sequence via from_codons
    # must yield domains with identical type_tag and parameter_codons.
    check all(
            n <- StreamData.integer(1..9),
            domains <- StreamData.list_of(Generators.domain_phase1(), length: n),
            max_runs: 100
          ) do
      gene = Gene.from_domains(domains)
      {:ok, reparsed} = Gene.from_codons(gene.codons)

      Enum.zip(domains, reparsed.domains)
      |> Enum.each(fn {orig, reparsed_domain} ->
        assert orig.type_tag == reparsed_domain.type_tag
        assert orig.parameter_codons == reparsed_domain.parameter_codons
        assert orig.type == reparsed_domain.type
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Property: reparse consistency

  property "reparse/1 produces the same domains as the original parse" do
    # After any mutation that modifies codons, reparse/1 refreshes the domain
    # views. For an unmodified gene, reparse must be idempotent.
    check all(gene <- Generators.gene(), max_runs: 100) do
      {:ok, reparsed} = Gene.reparse(gene)

      Enum.zip(gene.domains, reparsed.domains)
      |> Enum.each(fn {orig, rep} ->
        assert orig.type_tag == rep.type_tag
        assert orig.parameter_codons == rep.parameter_codons
        assert orig.type == rep.type
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Property: valid? / validate consistency

  property "Gene.valid?/1 == (Gene.validate/1 == :ok) for all generated genes" do
    check all(gene <- Generators.gene(), max_runs: 150) do
      assert Gene.valid?(gene) == (Gene.validate(gene) == :ok)
    end
  end

  # ---------------------------------------------------------------------------
  # Property: domain count

  property "domain_count == codon_count / 23 for Phase 1 genes" do
    check all(gene <- Generators.gene(), max_runs: 150) do
      expected_domain_count = div(Gene.codon_count(gene), 23)
      assert Gene.domain_count(gene) == expected_domain_count
    end
  end

  # ---------------------------------------------------------------------------
  # Property: gene has at least one domain

  property "all generated genes have at least one domain" do
    check all(gene <- Generators.gene(), max_runs: 100) do
      assert Gene.domain_count(gene) >= 1
    end
  end

  # ---------------------------------------------------------------------------
  # Property: all codons are valid

  property "all codons in a generated gene are in 0..19" do
    check all(gene <- Generators.gene(), max_runs: 150) do
      assert Enum.all?(gene.codons, &Codon.valid?/1)
    end
  end

  # ---------------------------------------------------------------------------
  # Property: gene id is always a binary

  property "gene.id is always a binary (UUID) for all generated genes" do
    check all(gene <- Generators.gene(), max_runs: 100) do
      assert is_binary(gene.id)
    end
  end

  # ---------------------------------------------------------------------------
  # Property: promoter and regulatory blocks are nil in Phase 1

  property "promoter_block and regulatory_block are nil for Phase 1 genes" do
    check all(gene <- Generators.gene(), max_runs: 100) do
      assert is_nil(gene.promoter_block)
      assert is_nil(gene.regulatory_block)
    end
  end
end
