defmodule Arkea.Views.GeneTreeTest do
  use ExUnit.Case, async: true

  alias Arkea.Ecology.Lineage
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Views.GeneTree

  defp gene(weight) do
    Gene.from_domains([Domain.new([0, 0, 1], List.duplicate(weight, 20))])
  end

  defp genome_with(g), do: Genome.new([g])

  defp founder(g, tick), do: Lineage.new_founder(g, %{phase_1: 100}, tick)

  defp child_of(parent, g, tick),
    do: Lineage.new_child(parent, g, %{phase_1: 100}, tick)

  defp first_chromosome_gene(%Lineage{genome: nil}), do: nil
  defp first_chromosome_gene(%Lineage{genome: g}), do: hd(g.chromosome)

  describe "build/2 — clustering" do
    test "lineages with identical genes collapse into one cluster" do
      g1 = gene(10)

      l0 = founder(genome_with(g1), 0)
      l1 = child_of(l0, genome_with(g1), 5)

      view =
        GeneTree.build([l0, l1], gene_extractor: &first_chromosome_gene/1)

      assert view.cluster_count == 1
      [c] = view.clusters
      assert length(c.members) == 2
      assert Enum.all?(c.members, &(&1.p_distance == 0.0))
    end

    test "distinct genes form distinct clusters" do
      l_a = founder(genome_with(gene(0)), 0)
      l_b = founder(genome_with(gene(19)), 0)

      view = GeneTree.build([l_a, l_b], gene_extractor: &first_chromosome_gene/1)
      assert view.cluster_count == 2
      assert Enum.all?(view.clusters, &(length(&1.members) == 1))
    end

    test "max_distance threshold groups near-identical variants" do
      # Modify a single codon → p_distance = 1/23 ≈ 0.043 → groups at default 0.05.
      base_gene = gene(10)
      mutated_codons = List.replace_at(base_gene.codons, 5, 19)

      mutated_gene =
        case Gene.reparse(%{base_gene | codons: mutated_codons}) do
          {:ok, g} -> g
        end

      l_a = founder(genome_with(base_gene), 0)
      l_b = founder(genome_with(mutated_gene), 0)

      view_loose =
        GeneTree.build([l_a, l_b],
          gene_extractor: &first_chromosome_gene/1,
          max_distance: 0.1
        )

      assert view_loose.cluster_count == 1

      view_strict =
        GeneTree.build([l_a, l_b],
          gene_extractor: &first_chromosome_gene/1,
          max_distance: 0.0
        )

      assert view_strict.cluster_count == 2
    end

    test "lineages whose extractor returns nil go to unmatched_lineages" do
      l = founder(genome_with(gene(5)), 0)

      view =
        GeneTree.build([l], gene_extractor: fn _ -> nil end)

      assert view.cluster_count == 0
      assert view.unmatched_lineages == [l.id]
    end
  end

  describe "build/2 — topology" do
    test "single-member cluster is :singleton" do
      l = founder(genome_with(gene(7)), 0)
      view = GeneTree.build([l], gene_extractor: &first_chromosome_gene/1)
      [c] = view.clusters
      assert c.topology == :singleton
    end

    test "monophyletic cluster (all descendants of MRCA also in cluster) is :congruent" do
      g = gene(10)
      l0 = founder(genome_with(g), 0)
      l1 = child_of(l0, genome_with(g), 5)
      l2 = child_of(l1, genome_with(g), 10)

      view = GeneTree.build([l0, l1, l2], gene_extractor: &first_chromosome_gene/1)
      [c] = view.clusters
      assert c.topology == :congruent
      assert c.mrca_lineage_id == l0.id
    end

    test "disjoint sub-trees with the same gene flag :incongruent (HGT signal)" do
      shared_gene = gene(11)
      other_gene = gene(0)

      # Build a small species tree:
      #   l0 (founder, gene=other)
      #     ├── l1 (gene=shared)
      #     └── l2 (gene=other)
      #          └── l3 (gene=shared)
      l0 = founder(genome_with(other_gene), 0)
      l1 = child_of(l0, genome_with(shared_gene), 5)
      l2 = child_of(l0, genome_with(other_gene), 5)
      l3 = child_of(l2, genome_with(shared_gene), 10)

      view =
        GeneTree.build([l0, l1, l2, l3],
          gene_extractor: &first_chromosome_gene/1,
          max_distance: 0.0
        )

      shared_cluster =
        view.clusters
        |> Enum.find(&Enum.any?(&1.members, fn m -> m.lineage_id == l1.id end))

      assert shared_cluster.topology == :incongruent
      # MRCA of l1 + l3 = l0 (the only common ancestor in this small tree).
      assert shared_cluster.mrca_lineage_id == l0.id
      # Subtree of l0 contains 4 lineages, only 2 carry the shared gene.
      assert shared_cluster.mrca_descendants_count == 4
    end
  end
end
