defmodule Arkea.Genome.Mutation.Applicator do
  @moduledoc """
  Pure function `apply/2` that applies any of the five mutation types to a
  genome (Phase 4 — IMPLEMENTATION-PLAN.md §5, Phase 4 deliverable).

  ## Phase 1 grammar invariant

  `Gene.from_codons/1` requires the codon count to be an exact positive
  multiple of 23 (the fixed Phase 1 domain width: 3 type-tag + 20 parameters).
  Every mutation in this module operates at **domain granularity** (23-codon
  boundaries) to preserve this invariant.  After modifying a gene's codons the
  module re-parses it with `Gene.reparse/1` so that `gene.domains` remains
  consistent with `gene.codons`.

  The mutated gene keeps its original `id` — gene identity is stable across
  mutations (the id tracks provenance, not sequence).

  ## Error values

  - `{:error, :invalid_target}` — `gene_id` not found in the genome.
  - `{:error, :gene_too_short}` — deletion or translocation source would leave
    fewer than one domain (< 23 codons) in the gene.
  """

  alias Arkea.Genome
  alias Arkea.Genome.Gene
  alias Arkea.Genome.Mutation.Duplication
  alias Arkea.Genome.Mutation.Indel
  alias Arkea.Genome.Mutation.Inversion
  alias Arkea.Genome.Mutation.Substitution
  alias Arkea.Genome.Mutation.Translocation

  @domain_size 23

  @doc """
  Apply a mutation to a genome.

  Returns `{:ok, new_genome}` on success or `{:error, reason}` on failure.
  The original genome is never mutated (pure).
  """
  @spec apply(Genome.t(), Arkea.Genome.Mutation.t()) ::
          {:ok, Genome.t()} | {:error, atom()}
  def apply(%Genome{} = genome, %Substitution{} = m) do
    find_and_update_gene(genome, m.gene_id, fn gene ->
      new_codons = List.replace_at(gene.codons, m.position, m.new_codon)
      reparse_gene(gene, new_codons)
    end)
  end

  def apply(%Genome{} = genome, %Indel{kind: :insertion} = m) do
    find_and_update_gene(genome, m.gene_id, fn gene ->
      {before, after_} = Enum.split(gene.codons, m.position)
      new_codons = before ++ m.codons ++ after_
      reparse_gene(gene, new_codons)
    end)
  end

  def apply(%Genome{} = genome, %Indel{kind: :deletion} = m) do
    find_and_update_gene(genome, m.gene_id, fn gene ->
      n_codons = length(gene.codons)

      if n_codons - length(m.codons) < @domain_size do
        {:error, :gene_too_short}
      else
        {before, rest} = Enum.split(gene.codons, m.position)
        after_ = Enum.drop(rest, length(m.codons))
        new_codons = before ++ after_
        reparse_gene(gene, new_codons)
      end
    end)
  end

  def apply(%Genome{} = genome, %Duplication{} = m) do
    find_and_update_gene(genome, m.gene_id, fn gene ->
      # range_end is inclusive
      copied = Enum.slice(gene.codons, m.range_start..m.range_end)
      {before, after_} = Enum.split(gene.codons, m.insert_at)
      new_codons = before ++ copied ++ after_
      reparse_gene(gene, new_codons)
    end)
  end

  def apply(%Genome{} = genome, %Inversion{} = m) do
    find_and_update_gene(genome, m.gene_id, fn gene ->
      before = Enum.take(gene.codons, m.range_start)
      segment = Enum.slice(gene.codons, m.range_start..m.range_end)
      after_ = Enum.drop(gene.codons, m.range_end + 1)
      new_codons = before ++ Enum.reverse(segment) ++ after_
      reparse_gene(gene, new_codons)
    end)
  end

  def apply(%Genome{} = genome, %Translocation{} = m) do
    with {:ok, source_gene} <- find_gene(genome, m.source_gene_id),
         {:ok, dest_gene} <- find_gene(genome, m.dest_gene_id) do
      apply_translocation(genome, m, source_gene, dest_gene)
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers

  # Core logic for Translocation, extracted to keep apply/2 depth ≤ 2.
  defp apply_translocation(genome, m, source_gene, dest_gene) do
    {rs, re} = m.source_range
    n_source = length(source_gene.codons)

    if n_source - (re - rs + 1) < @domain_size do
      {:error, :gene_too_short}
    else
      build_translocated_genome(genome, m, source_gene, dest_gene, rs, re)
    end
  end

  defp build_translocated_genome(genome, m, source_gene, dest_gene, rs, re) do
    moved = Enum.slice(source_gene.codons, rs..re)
    new_src_codons = Enum.take(source_gene.codons, rs) ++ Enum.drop(source_gene.codons, re + 1)
    {dst_before, dst_after} = Enum.split(dest_gene.codons, m.dest_position)
    new_dst_codons = dst_before ++ moved ++ dst_after

    with {:ok, new_src} <- reparse_gene(source_gene, new_src_codons),
         {:ok, new_dst} <- reparse_gene(dest_gene, new_dst_codons) do
      {:ok, replace_two_genes(genome, m.source_gene_id, new_src, m.dest_gene_id, new_dst)}
    end
  end

  defp replace_two_genes(genome, src_id, new_src, dst_id, new_dst) do
    new_chromosome =
      Enum.map(genome.chromosome, fn g ->
        cond do
          g.id == src_id -> new_src
          g.id == dst_id -> new_dst
          true -> g
        end
      end)

    rebuild_genome(genome, new_chromosome)
  end

  # Find a gene by id, returning {:ok, gene} | {:error, :invalid_target}.
  defp find_gene(%Genome{chromosome: chr}, gene_id) do
    case Enum.find(chr, fn g -> g.id == gene_id end) do
      nil -> {:error, :invalid_target}
      gene -> {:ok, gene}
    end
  end

  # Find a gene in the chromosome, apply `fun` to it, replace it in the genome.
  # `fun` receives a `Gene.t()` and must return `{:ok, Gene.t()} | {:error, atom()}`.
  @spec find_and_update_gene(Genome.t(), binary(), (Gene.t() ->
                                                      {:ok, Gene.t()} | {:error, atom()})) ::
          {:ok, Genome.t()} | {:error, atom()}
  defp find_and_update_gene(%Genome{chromosome: chr} = genome, gene_id, fun) do
    case Enum.find_index(chr, fn g -> g.id == gene_id end) do
      nil ->
        {:error, :invalid_target}

      idx ->
        gene = Enum.at(chr, idx)

        case fun.(gene) do
          {:ok, new_gene} ->
            new_chr = List.replace_at(chr, idx, new_gene)
            {:ok, rebuild_genome(genome, new_chr)}

          {:error, _} = err ->
            err
        end
    end
  end

  # Re-parse a gene with new codons, preserving the original gene id.
  # Returns {:ok, gene} | {:error, atom()}.
  defp reparse_gene(%Gene{} = gene, new_codons) do
    case Gene.from_codons(new_codons) do
      {:ok, parsed} ->
        {:ok,
         %{
           parsed
           | id: gene.id,
             promoter_block: gene.promoter_block,
             regulatory_block: gene.regulatory_block,
             intergenic_blocks: gene.intergenic_blocks
         }}

      {:error, _} = err ->
        err
    end
  end

  # Rebuild the genome with a new chromosome, recomputing gene_count.
  defp rebuild_genome(%Genome{plasmids: p, prophages: pr}, new_chromosome) do
    Genome.new(new_chromosome, plasmids: p, prophages: pr)
  end
end
