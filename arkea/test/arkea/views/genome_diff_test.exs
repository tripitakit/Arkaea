defmodule Arkea.Views.GenomeDiffTest do
  use ExUnit.Case, async: true

  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Views.GenomeDiff

  @param_codons List.duplicate(10, 20)

  defp catalytic_gene, do: Gene.from_domains([Domain.new([0, 0, 1], @param_codons)])
  defp dna_binding_gene, do: Gene.from_domains([Domain.new([0, 0, 5], @param_codons)])
  defp transmembrane_gene, do: Gene.from_domains([Domain.new([0, 0, 2], @param_codons)])

  test "build/2 with two identical genomes → identical? true, all-shared partition" do
    g = Genome.new([catalytic_gene(), dna_binding_gene()])
    diff = GenomeDiff.build(g, g)

    assert diff.identical?
    assert length(diff.chromosome.shared) == 2
    assert diff.chromosome.a_only == []
    assert diff.chromosome.b_only == []
  end

  test "two genomes with the same codon sequences but distinct Gene.id → still identical" do
    # Each `from_domains/1` call mints a fresh UUID; if the diff used
    # gene.id we'd see two `a_only` and two `b_only` entries.
    a = Genome.new([catalytic_gene(), dna_binding_gene()])
    b = Genome.new([catalytic_gene(), dna_binding_gene()])

    diff = GenomeDiff.build(a, b)
    assert diff.identical?
    assert length(diff.chromosome.shared) == 2
  end

  test "a gene unique to A appears in chromosome.a_only" do
    a = Genome.new([catalytic_gene(), dna_binding_gene()])
    b = Genome.new([catalytic_gene()])

    diff = GenomeDiff.build(a, b)
    refute diff.identical?
    assert length(diff.chromosome.shared) == 1
    assert length(diff.chromosome.a_only) == 1
    assert diff.chromosome.b_only == []

    [unique] = diff.chromosome.a_only
    assert :dna_binding in unique.domain_types
  end

  test "plasmid identity uses {inc_group, sorted gene signatures}" do
    plasmid_genes = [transmembrane_gene(), transmembrane_gene()]
    plasmid = Genome.normalize_plasmid(plasmid_genes)

    a = Genome.new([catalytic_gene()], plasmids: [plasmid])
    b = Genome.new([catalytic_gene()], plasmids: [plasmid])

    diff = GenomeDiff.build(a, b)
    assert diff.identical?
    assert length(diff.plasmids.shared) == 1
    assert diff.plasmids.a_only == []
  end

  test "a plasmid unique to B appears in plasmids.b_only with copy_number/oriT side data" do
    plasmid_genes = [transmembrane_gene(), transmembrane_gene()]
    plasmid = Genome.normalize_plasmid(plasmid_genes)

    a = Genome.new([catalytic_gene()])
    b = Genome.new([catalytic_gene()], plasmids: [plasmid])

    diff = GenomeDiff.build(a, b)
    refute diff.identical?
    assert diff.plasmids.shared == []
    assert diff.plasmids.a_only == []
    assert length(diff.plasmids.b_only) == 1

    [b_plasmid] = diff.plasmids.b_only
    assert b_plasmid.gene_count == 2
    assert is_integer(b_plasmid.copy_number)
    assert is_boolean(b_plasmid.oriT_present)
  end

  test "phenotype_delta surfaces measurable differences across the headline scalars" do
    a = Genome.new([catalytic_gene()])

    b =
      Genome.new([
        catalytic_gene(),
        # Adds a strong dna_binding gene → raises dna_binding_affinity.
        Gene.from_domains([Domain.new([0, 0, 5], List.duplicate(19, 20))])
      ])

    diff = GenomeDiff.build(a, b)
    refute diff.identical?
    assert diff.phenotype_delta.dna_binding_affinity > 0.0
  end

  test "nil sides are treated as empty genomes" do
    g = Genome.new([catalytic_gene()])

    a_diff = GenomeDiff.build(nil, g)
    assert a_diff.chromosome.shared == []
    assert a_diff.chromosome.a_only == []
    assert length(a_diff.chromosome.b_only) == 1

    b_diff = GenomeDiff.build(g, nil)
    assert length(b_diff.chromosome.a_only) == 1
    assert b_diff.chromosome.b_only == []

    none_diff = GenomeDiff.build(nil, nil)
    assert none_diff.identical?
  end
end
