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
  # Phase 26 / 1.13 + 1.14 — mutation-event detection.

  # Helper: build a single-domain gene with a chosen type_tag.
  # `type_tag` sum picks the domain category from
  # `Arkea.Genome.Domain.Type.@types`; the parameter codons are
  # constant-`10` so each gene has the same `Phenotype.from_genome/1`
  # baseline modulo the type flip.
  defp single_typed_gene(type_tag) do
    Gene.from_domains([Domain.new(type_tag, List.duplicate(10, 20))])
  end

  describe "detect_mutation_events/4" do
    test "domain_flip fires when a substitution swaps a domain category" do
      # Start with a `:catalytic_site` gene (sum 1 → index 1).
      gene = single_typed_gene([0, 0, 1])
      genome = Genome.new([gene])

      # Substitute the third type-tag codon 1→2; new sum 2 →
      # `:transmembrane_anchor` (different category).
      mutation = %Substitution{
        gene_id: gene.id,
        position: 2,
        old_codon: 1,
        new_codon: 2
      }

      {:ok, new_genome} = Applicator.apply(genome, mutation)

      events =
        Applicator.detect_mutation_events(genome, new_genome, mutation,
          tick: 7,
          lineage_id: "L-1"
        )

      assert [event] = events
      assert event.type == :domain_flip
      assert event.tick == 7
      assert event.lineage_id == "L-1"
      assert event.gene_id == gene.id
      assert event.domain_index == 0
      assert event.from_type == :catalytic_site
      assert event.to_type == :transmembrane_anchor
    end

    test "no events when a substitution stays inside parameter_codons (drift only)" do
      gene = single_typed_gene([0, 0, 1])
      genome = Genome.new([gene])

      # Substitute a parameter codon (position 5, well past the
      # 3-codon type_tag) → category unchanged → no flip.
      mutation = %Substitution{
        gene_id: gene.id,
        position: 5,
        old_codon: 10,
        new_codon: 19
      }

      {:ok, new_genome} = Applicator.apply(genome, mutation)
      assert Applicator.detect_mutation_events(genome, new_genome, mutation) == []
    end

    test "gene_chimera_birth fires whenever a translocation succeeds" do
      g1 = gene_with_n_domains(2)
      g2 = gene_with_n_domains(2)
      genome = Genome.new([g1, g2])

      # Move 23 codons from g1 (2 domains → 1 domain after) into g2.
      mutation = %Translocation{
        source_gene_id: g1.id,
        dest_gene_id: g2.id,
        source_range: {0, 22},
        dest_position: 23
      }

      {:ok, new_genome} = Applicator.apply(genome, mutation)

      events =
        Applicator.detect_mutation_events(genome, new_genome, mutation,
          tick: 12,
          lineage_id: "L-2"
        )

      chimera = Enum.find(events, &(&1.type == :gene_chimera_birth))
      assert chimera, "expected a :gene_chimera_birth event from a successful translocation"
      assert chimera.source_gene_id == g1.id
      assert chimera.dest_gene_id == g2.id
      assert chimera.codons_moved == 23
      assert chimera.tick == 12
      assert chimera.lineage_id == "L-2"
    end

    test "detect on a parameter-only inversion returns []" do
      # Single-domain gene; inverting a 5-codon window inside the
      # `parameter_codons` (positions 5..9) keeps the type_tag
      # untouched ⇒ no domain_flip event.
      g = single_typed_gene([0, 0, 1])
      genome = Genome.new([g])

      mutation = %Inversion{gene_id: g.id, range_start: 5, range_end: 9}
      {:ok, new_genome} = Applicator.apply(genome, mutation)

      assert Applicator.detect_mutation_events(genome, new_genome, mutation) == []
    end

    test "default tick is 0 and lineage_id is nil when opts are omitted" do
      gene = single_typed_gene([0, 0, 1])
      genome = Genome.new([gene])

      mutation = %Substitution{
        gene_id: gene.id,
        position: 2,
        old_codon: 1,
        new_codon: 2
      }

      {:ok, new_genome} = Applicator.apply(genome, mutation)

      [event] = Applicator.detect_mutation_events(genome, new_genome, mutation)
      assert event.tick == 0
      assert event.lineage_id == nil
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
