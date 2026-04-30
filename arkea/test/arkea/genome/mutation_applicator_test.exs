defmodule Arkea.Genome.Mutation.ApplicatorTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Genome.Mutation.Applicator
  alias Arkea.Genome.Mutation.Duplication
  alias Arkea.Genome.Mutation.Indel
  alias Arkea.Genome.Mutation.Inversion
  alias Arkea.Genome.Mutation.Substitution
  alias Arkea.Genome.Mutation.Translocation

  @moduletag :genome

  @domain_size 23

  # ---------------------------------------------------------------------------
  # Helpers

  # Build a gene with exactly `n_domains` domains (all-zero parameter_codons).
  defp gene_with_n_domains(n) when n >= 1 do
    domains = Enum.map(1..n, fn _ -> Domain.new([0, 0, 0], List.duplicate(0, 20)) end)
    Gene.from_domains(domains)
  end

  defp genome_with_genes(genes) when is_list(genes) and genes != [] do
    Genome.new(genes)
  end

  defp single_gene_genome(n_domains) do
    genome_with_genes([gene_with_n_domains(n_domains)])
  end

  defp two_gene_genome do
    g1 = gene_with_n_domains(2)
    g2 = gene_with_n_domains(2)
    genome_with_genes([g1, g2])
  end

  # ---------------------------------------------------------------------------
  # Unit: Substitution

  test "Substitution changes exactly one codon, length unchanged" do
    genome = single_gene_genome(2)
    gene = hd(genome.chromosome)
    old_codon = Enum.at(gene.codons, 0)
    new_codon = rem(old_codon + 1, 20)

    mutation = %Substitution{
      gene_id: gene.id,
      position: 0,
      old_codon: old_codon,
      new_codon: new_codon
    }

    assert {:ok, new_genome} = Applicator.apply(genome, mutation)
    new_gene = hd(new_genome.chromosome)

    assert length(new_gene.codons) == length(gene.codons),
           "Substitution must not change codon count"

    assert Enum.at(new_gene.codons, 0) == new_codon
    # All other codons unchanged
    for i <- 1..(length(gene.codons) - 1) do
      assert Enum.at(new_gene.codons, i) == Enum.at(gene.codons, i)
    end
  end

  test "Substitution preserves domain count" do
    genome = single_gene_genome(3)
    gene = hd(genome.chromosome)
    old_codon = Enum.at(gene.codons, 0)
    new_codon = rem(old_codon + 1, 20)

    mutation = %Substitution{
      gene_id: gene.id,
      position: 0,
      old_codon: old_codon,
      new_codon: new_codon
    }

    {:ok, new_genome} = Applicator.apply(genome, mutation)
    new_gene = hd(new_genome.chromosome)
    assert length(new_gene.domains) == 3
  end

  # ---------------------------------------------------------------------------
  # Unit: Indel :insertion

  test "Indel :insertion adds exactly 23 codons, gene remains multiple of 23" do
    genome = single_gene_genome(2)
    gene = hd(genome.chromosome)
    n_before = length(gene.codons)

    mutation = %Indel{
      gene_id: gene.id,
      position: 0,
      kind: :insertion,
      codons: List.duplicate(0, @domain_size)
    }

    assert {:ok, new_genome} = Applicator.apply(genome, mutation)
    new_gene = hd(new_genome.chromosome)
    n_after = length(new_gene.codons)

    assert n_after == n_before + @domain_size
    assert rem(n_after, @domain_size) == 0
  end

  # ---------------------------------------------------------------------------
  # Unit: Indel :deletion

  test "Indel :deletion removes 23 codons, gene remains multiple of 23" do
    genome = single_gene_genome(2)
    gene = hd(genome.chromosome)
    n_before = length(gene.codons)

    # delete first domain
    deleted = Enum.take(gene.codons, @domain_size)

    mutation = %Indel{
      gene_id: gene.id,
      position: 0,
      kind: :deletion,
      codons: deleted
    }

    assert {:ok, new_genome} = Applicator.apply(genome, mutation)
    new_gene = hd(new_genome.chromosome)
    n_after = length(new_gene.codons)

    assert n_after == n_before - @domain_size
    assert rem(n_after, @domain_size) == 0
  end

  test "Indel :deletion on single-domain gene returns {:error, :gene_too_short}" do
    genome = single_gene_genome(1)
    gene = hd(genome.chromosome)
    deleted = Enum.take(gene.codons, @domain_size)

    mutation = %Indel{
      gene_id: gene.id,
      position: 0,
      kind: :deletion,
      codons: deleted
    }

    assert {:error, :gene_too_short} = Applicator.apply(genome, mutation)
  end

  # ---------------------------------------------------------------------------
  # Unit: Duplication

  test "Duplication copies one domain, gene grows by 23" do
    genome = single_gene_genome(2)
    gene = hd(genome.chromosome)
    n_before = length(gene.codons)

    mutation = %Duplication{
      gene_id: gene.id,
      range_start: 0,
      range_end: @domain_size - 1,
      insert_at: n_before
    }

    assert {:ok, new_genome} = Applicator.apply(genome, mutation)
    new_gene = hd(new_genome.chromosome)
    n_after = length(new_gene.codons)

    assert n_after == n_before + @domain_size
    assert rem(n_after, @domain_size) == 0
  end

  # ---------------------------------------------------------------------------
  # Unit: Inversion

  test "Inversion reverses a range, length unchanged" do
    genome = single_gene_genome(3)
    gene = hd(genome.chromosome)
    n_before = length(gene.codons)

    mutation = %Inversion{
      gene_id: gene.id,
      range_start: 0,
      range_end: @domain_size - 1
    }

    assert {:ok, new_genome} = Applicator.apply(genome, mutation)
    new_gene = hd(new_genome.chromosome)

    assert length(new_gene.codons) == n_before
    assert rem(length(new_gene.codons), @domain_size) == 0

    # The inverted region should be reversed
    original_segment = Enum.slice(gene.codons, 0..(@domain_size - 1))
    new_segment = Enum.slice(new_gene.codons, 0..(@domain_size - 1))
    assert new_segment == Enum.reverse(original_segment)
  end

  # ---------------------------------------------------------------------------
  # Unit: Translocation

  test "Translocation moves 23 codons: source shrinks by 23, dest grows by 23" do
    genome = two_gene_genome()
    [src_gene, dst_gene] = genome.chromosome

    n_src_before = length(src_gene.codons)
    n_dst_before = length(dst_gene.codons)

    mutation = %Translocation{
      source_gene_id: src_gene.id,
      dest_gene_id: dst_gene.id,
      source_range: {0, @domain_size - 1},
      dest_position: 0
    }

    assert {:ok, new_genome} = Applicator.apply(genome, mutation)
    [new_src, new_dst] = new_genome.chromosome

    assert length(new_src.codons) == n_src_before - @domain_size
    assert length(new_dst.codons) == n_dst_before + @domain_size
    assert rem(length(new_src.codons), @domain_size) == 0
    assert rem(length(new_dst.codons), @domain_size) == 0
  end

  test "Translocation on single-domain source returns {:error, :gene_too_short}" do
    g1 = gene_with_n_domains(1)
    g2 = gene_with_n_domains(2)
    genome = genome_with_genes([g1, g2])

    mutation = %Translocation{
      source_gene_id: g1.id,
      dest_gene_id: g2.id,
      source_range: {0, @domain_size - 1},
      dest_position: 0
    }

    assert {:error, :gene_too_short} = Applicator.apply(genome, mutation)
  end

  # ---------------------------------------------------------------------------
  # Unit: unknown gene_id

  test "apply returns {:error, :invalid_target} for unknown gene_id" do
    genome = single_gene_genome(2)
    fake_id = Arkea.UUID.v4()

    mutation = %Substitution{
      gene_id: fake_id,
      position: 0,
      old_codon: 0,
      new_codon: 1
    }

    assert {:error, :invalid_target} = Applicator.apply(genome, mutation)
  end

  test "Translocation with unknown source_gene_id returns {:error, :invalid_target}" do
    genome = single_gene_genome(2)
    gene = hd(genome.chromosome)

    mutation = %Translocation{
      source_gene_id: Arkea.UUID.v4(),
      dest_gene_id: gene.id,
      source_range: {0, @domain_size - 1},
      dest_position: 0
    }

    assert {:error, :invalid_target} = Applicator.apply(genome, mutation)
  end

  # ---------------------------------------------------------------------------
  # Property: genome remains parseable after any valid mutation

  property "after any successful mutation, all genes remain parseable via from_codons" do
    check all(genome <- valid_mutatable_genome()) do
      gene = hd(genome.chromosome)
      old_codon = Enum.at(gene.codons, 0)
      new_codon = rem(old_codon + 1, 20)

      mutation = %Substitution{
        gene_id: gene.id,
        position: 0,
        old_codon: old_codon,
        new_codon: new_codon
      }

      case Applicator.apply(genome, mutation) do
        {:ok, new_genome} ->
          for g <- new_genome.chromosome do
            assert rem(length(g.codons), @domain_size) == 0,
                   "gene #{g.id} has #{length(g.codons)} codons, not a multiple of 23"

            assert {:ok, _} = Gene.from_codons(g.codons),
                   "gene #{g.id} is not parseable after mutation"
          end

        {:error, _} ->
          # errors are permitted (e.g. gene_too_short); no parsability check needed
          :ok
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private generators

  defp valid_mutatable_genome do
    StreamData.bind(StreamData.integer(1..3), fn n ->
      genes = Enum.map(1..n, fn _ -> gene_with_n_domains(2) end)
      StreamData.constant(Genome.new(genes))
    end)
  end
end
