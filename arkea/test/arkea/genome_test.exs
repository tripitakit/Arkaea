defmodule Arkea.GenomeTest do
  @moduledoc """
  Property tests for Arkea.Genome.

  Invariants covered:
  - gene_count(g) == length(all_genes(g)) for any genome built via new/2
  - add_plasmid mass conservation: new gene_count = old + length(plasmid)
  - valid?/1 and validate/1 agree on all generated genomes
  - all_genes returns chromosome ++ flatten(plasmids) ++ flatten(prophages)
  - Genome.new raises on empty chromosome
  - integrate_prophage mass conservation
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Arkea.Generators
  alias Arkea.Genome
  alias Arkea.Genome.Gene

  # ---------------------------------------------------------------------------
  # Plain unit tests

  test "new/2 raises on empty chromosome" do
    assert_raise ArgumentError, fn -> Genome.new([]) end
  end

  test "valid?/1 returns false for non-Genome struct" do
    refute Genome.valid?(%{chromosome: []})
    refute Genome.valid?(nil)
  end

  test "Phase 1 genomes have no plasmids or prophages" do
    genome = Generators.genome() |> Enum.take(1) |> hd()
    assert genome.plasmids == []
    assert genome.prophages == []
  end

  # ---------------------------------------------------------------------------
  # Property: gene_count cache consistency

  property "gene_count == length(all_genes(g)) for any constructed genome" do
    # Conservation invariant: gene_count is a cached integer that must always
    # equal the actual number of genes across chromosome + plasmids + prophages.
    # This is the Phase 1 equivalent of mass conservation at the gene level.
    check all(genome <- Generators.genome(), max_runs: 100) do
      assert Genome.gene_count(genome) == length(Genome.all_genes(genome))
    end
  end

  # ---------------------------------------------------------------------------
  # Property: valid? / validate consistency

  property "Genome.valid?/1 == (Genome.validate/1 == :ok) for all generated genomes" do
    check all(genome <- Generators.genome(), max_runs: 100) do
      assert Genome.valid?(genome) == (Genome.validate(genome) == :ok)
    end
  end

  # ---------------------------------------------------------------------------
  # Property: add_plasmid mass conservation

  property "add_plasmid increases gene_count by length(plasmid)" do
    # Mass conservation at the genome level: adding a plasmid of N genes must
    # increase gene_count by exactly N. No genes are lost or duplicated.
    check all({genome, plasmid} <- Generators.genome_with_plasmid(), max_runs: 100) do
      old_count = Genome.gene_count(genome)
      plasmid_genes = length(plasmid)
      new_genome = Genome.add_plasmid(genome, plasmid)

      assert Genome.gene_count(new_genome) == old_count + plasmid_genes
    end
  end

  property "add_plasmid result passes valid?/1" do
    check all({genome, plasmid} <- Generators.genome_with_plasmid(), max_runs: 100) do
      new_genome = Genome.add_plasmid(genome, plasmid)
      assert Genome.valid?(new_genome)
    end
  end

  # ---------------------------------------------------------------------------
  # Property: add_plasmid gene_count also consistent with all_genes

  property "after add_plasmid, gene_count == length(all_genes)" do
    check all({genome, plasmid} <- Generators.genome_with_plasmid(), max_runs: 100) do
      new_genome = Genome.add_plasmid(genome, plasmid)
      assert Genome.gene_count(new_genome) == length(Genome.all_genes(new_genome))
    end
  end

  # ---------------------------------------------------------------------------
  # Property: integrate_prophage mass conservation

  property "integrate_prophage increases gene_count by length(cassette)" do
    # Mass conservation invariant: integrating a prophage cassette of N genes
    # must increase gene_count by exactly N.
    check all(
            genome <- Generators.genome(),
            n <- StreamData.integer(1..3),
            cassette <- StreamData.list_of(Generators.gene(), length: n),
            max_runs: 100
          ) do
      old_count = Genome.gene_count(genome)
      new_genome = Genome.integrate_prophage(genome, cassette)
      assert Genome.gene_count(new_genome) == old_count + n
    end
  end

  property "integrate_prophage result is valid" do
    check all(
            genome <- Generators.genome(),
            n <- StreamData.integer(1..3),
            cassette <- StreamData.list_of(Generators.gene(), length: n),
            max_runs: 100
          ) do
      new_genome = Genome.integrate_prophage(genome, cassette)
      assert Genome.valid?(new_genome)
    end
  end

  # ---------------------------------------------------------------------------
  # Property: all_genes ordering

  property "all_genes returns chromosome genes first" do
    check all(genome <- Generators.genome(), max_runs: 100) do
      all = Genome.all_genes(genome)
      chromosome_genes = genome.chromosome

      prefix = Enum.take(all, length(chromosome_genes))
      assert prefix == chromosome_genes
    end
  end

  # ---------------------------------------------------------------------------
  # Property: chromosome is non-empty

  property "chromosome is never empty in any generated genome" do
    check all(genome <- Generators.genome(), max_runs: 100) do
      assert genome.chromosome != []
    end
  end

  # ---------------------------------------------------------------------------
  # Property: gene_count is positive

  property "gene_count >= 1 for all generated genomes" do
    check all(genome <- Generators.genome(), max_runs: 100) do
      assert Genome.gene_count(genome) >= 1
    end
  end

  # ---------------------------------------------------------------------------
  # Property: all genes in chromosome are valid

  property "all genes in chromosome are valid Gene structs" do
    check all(genome <- Generators.genome(), max_runs: 100) do
      assert Enum.all?(genome.chromosome, &Gene.valid?/1)
    end
  end
end
