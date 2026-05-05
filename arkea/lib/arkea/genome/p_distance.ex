defmodule Arkea.Genome.PDistance do
  @moduledoc """
  Pairwise genetic distance between two `Arkea.Genome.t()` values
  (UI Phase D — phylogeny dendrogram).

  ## Definition

  We compute the **p-distance** (proportion of differing sites) over
  the codon alphabet, summing across the chromosome and all
  extra-chromosomal replicons (plasmids + prophages):

      p = mismatches / total_compared

  with `0.0 ≤ p ≤ 1.0`. When the two genomes are codon-identical the
  distance is zero; when no homologous codons can be aligned the
  distance is one.

  ## Alignment

  We pair genes positionally (`Genome.chromosome[0] ↔ chromosome[0]`,
  `plasmids[0] ↔ plasmids[0]`, …). Within each gene pair we align
  codons by index. Where one gene is longer than its counterpart, the
  excess codons count as full mismatches (penalises insertion /
  deletion bursts proportionally to their size). Where one genome
  carries an entire replicon the other lacks, every codon of that
  replicon counts as mismatch — the typical case after a single
  conjugation event between an empty-plasmid recipient and a
  plasmid-bearing donor.

  This is **not** a proper sequence-evolution model (Jukes-Cantor,
  Kimura, etc.); for short divergence times and small genomes the
  raw mismatch fraction is a good visual proxy, and is what the
  phylogeny dendrogram needs as edge length. If the simulation later
  exposes per-site rate heterogeneity we can swap in a JC69-corrected
  metric without changing the API.

  Pure: no I/O, no allocations beyond the input traversal.
  """

  alias Arkea.Genome
  alias Arkea.Genome.Gene

  @type t :: float()

  @doc """
  Distance between two genomes. Returns `0.0` when either argument
  is `nil` (one or both lineages are delta-encoded descendants
  without a reified genome — they inherit branch length 0 from the
  caller's perspective).
  """
  @spec distance(Genome.t() | nil, Genome.t() | nil) :: t()
  def distance(nil, _), do: 0.0
  def distance(_, nil), do: 0.0

  def distance(%Genome{} = a, %Genome{} = b) do
    {mm, total} =
      {0, 0}
      |> add_gene_list(a.chromosome, b.chromosome)
      |> add_replicon_list(a.plasmids, b.plasmids, & &1.genes)
      |> add_replicon_list(a.prophages, b.prophages, & &1.genes)

    cond do
      total == 0 -> 0.0
      true -> mm / total
    end
  end

  defp add_gene_list({mm, total}, list_a, list_b)
       when is_list(list_a) and is_list(list_b) do
    {paired_mm, paired_total} =
      list_a
      |> Enum.zip(list_b)
      |> Enum.reduce({0, 0}, fn {ga, gb}, {acc_mm, acc_total} ->
        {gm, gt} = compare_gene(ga, gb)
        {acc_mm + gm, acc_total + gt}
      end)

    extra_a = unpaired_codon_total(list_a, length(list_b))
    extra_b = unpaired_codon_total(list_b, length(list_a))

    {mm + paired_mm + extra_a + extra_b, total + paired_total + extra_a + extra_b}
  end

  defp add_replicon_list(acc, list_a, list_b, gene_extractor)
       when is_list(list_a) and is_list(list_b) do
    paired_acc =
      list_a
      |> Enum.zip(list_b)
      |> Enum.reduce(acc, fn {ra, rb}, a_in ->
        add_gene_list(a_in, gene_extractor.(ra), gene_extractor.(rb))
      end)

    len_a = length(list_a)
    len_b = length(list_b)

    extra =
      cond do
        len_a > len_b ->
          list_a |> Enum.drop(len_b) |> Enum.flat_map(gene_extractor) |> codon_total()

        len_b > len_a ->
          list_b |> Enum.drop(len_a) |> Enum.flat_map(gene_extractor) |> codon_total()

        true ->
          0
      end

    {paired_mm, paired_total} = paired_acc
    {paired_mm + extra, paired_total + extra}
  end

  defp compare_gene(%Gene{codons: ca}, %Gene{codons: cb}) do
    paired = Enum.zip(ca, cb)
    paired_mm = Enum.count(paired, fn {a, b} -> a != b end)
    paired_total = length(paired)

    extra = abs(length(ca) - length(cb))
    {paired_mm + extra, paired_total + extra}
  end

  defp compare_gene(_, _), do: {0, 0}

  defp unpaired_codon_total(genes, paired_count) do
    genes
    |> Enum.drop(paired_count)
    |> codon_total()
  end

  defp codon_total(genes) do
    Enum.reduce(genes, 0, fn
      %Gene{codons: c}, acc -> acc + length(c)
      _, acc -> acc
    end)
  end
end
