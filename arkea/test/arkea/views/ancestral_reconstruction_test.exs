defmodule Arkea.Views.AncestralReconstructionTest do
  use ExUnit.Case, async: true

  alias Arkea.Ecology.Lineage
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Views.AncestralReconstruction

  defp gene(weight) do
    Gene.from_domains([Domain.new([0, 0, 1], List.duplicate(weight, 20))])
  end

  defp two_gene_genome(w1, w2), do: Genome.new([gene(w1), gene(w2)])

  defp single_gene_genome(w), do: Genome.new([gene(w)])

  defp founder(genome, tick \\ 0) do
    Lineage.new_founder(genome, %{phase_1: 100}, tick)
  end

  defp child_of(parent, genome, tick) do
    Lineage.new_child(parent, genome, %{phase_1: 100}, tick)
  end

  describe "lineage_chain/2" do
    test "returns target → root order" do
      g0 = single_gene_genome(10)
      g1 = single_gene_genome(11)
      g2 = single_gene_genome(12)
      l0 = founder(g0, 0)
      l1 = child_of(l0, g1, 5)
      l2 = child_of(l1, g2, 10)

      ids =
        AncestralReconstruction.lineage_chain([l0, l1, l2], l2.id)
        |> Enum.map(& &1.id)

      assert ids == [l2.id, l1.id, l0.id]
    end

    test "returns :not_found for an unknown target" do
      l = founder(single_gene_genome(10))
      assert AncestralReconstruction.lineage_chain([l], "nope") == :not_found
    end

    test "stops at the first ancestor whose parent is not in the population" do
      l0 = founder(single_gene_genome(10), 0)
      l1 = child_of(l0, single_gene_genome(11), 5)

      # Pass only l1 — the parent l0 is missing from the population.
      chain = AncestralReconstruction.lineage_chain([l1], l1.id)
      assert Enum.map(chain, & &1.id) == [l1.id]
    end
  end

  describe "genome_trace/2" do
    test "surfaces per-ancestor genome composition" do
      g0 = two_gene_genome(10, 12)
      g1 = single_gene_genome(11)
      l0 = founder(g0, 0)
      l1 = child_of(l0, g1, 5)

      trace = AncestralReconstruction.genome_trace([l0, l1], l1.id)

      assert trace.target_id == l1.id
      assert trace.depth == 2
      [target_entry, parent_entry] = trace.ancestors

      assert target_entry.lineage_id == l1.id
      assert target_entry.generation == 0
      assert target_entry.gene_count == 1
      assert target_entry.genome_present?

      assert parent_entry.lineage_id == l0.id
      assert parent_entry.generation == 1
      assert parent_entry.gene_count == 2
    end

    test "marks delta-only ancestors as genome_present?: false" do
      g0 = single_gene_genome(10)
      l0 = founder(g0, 0)
      l1 = child_of(l0, single_gene_genome(11), 5)
      l1_delta_only = %{l1 | genome: nil}

      trace = AncestralReconstruction.genome_trace([l0, l1_delta_only], l1.id)
      [target_entry, _] = trace.ancestors

      refute target_entry.genome_present?
      assert target_entry.gene_count == nil
      assert target_entry.plasmid_count == 0
      assert target_entry.prophage_count == 0
    end

    test "returns :not_found when target id is unknown" do
      l = founder(single_gene_genome(10))
      assert AncestralReconstruction.genome_trace([l], "nope") == :not_found
    end
  end

  describe "gene_trace/3" do
    test "surfaces codon sequence + type for the gene at that chromosome position across ancestors" do
      g0 = two_gene_genome(10, 14)
      g1 = two_gene_genome(11, 14)
      g2 = two_gene_genome(12, 14)
      l0 = founder(g0, 0)
      l1 = child_of(l0, g1, 5)
      l2 = child_of(l1, g2, 10)

      result = AncestralReconstruction.gene_trace([l0, l1, l2], l2.id, 0)

      assert result.gene_chromosome_index == 0
      assert result.depth == 3

      assert Enum.all?(result.trace, &(&1.status == :present))
      assert Enum.all?(result.trace, &(&1.type == :catalytic_site))

      [t0, t1, t2] = result.trace
      # Generation 0 (target) → weight 12. Generation 2 (root) → weight 10.
      assert hd(t0.codons) in [12, 0]
      assert t0.generation == 0
      assert t1.generation == 1
      assert t2.generation == 2
      # Codon 3 onward is parameter region.
      assert Enum.at(t0.codons, 3) == 12
      assert Enum.at(t1.codons, 3) == 11
      assert Enum.at(t2.codons, 3) == 10
    end

    test "marks ancestor as :lost when its chromosome has fewer genes" do
      g0 = single_gene_genome(10)
      g1 = two_gene_genome(11, 14)
      l0 = founder(g0, 0)
      l1 = child_of(l0, g1, 5)

      result = AncestralReconstruction.gene_trace([l0, l1], l1.id, 1)

      [target, parent] = result.trace
      assert target.status == :present
      assert parent.status == :lost
      assert parent.codons == nil
      assert parent.type == nil
    end

    test "marks ancestor as :delta_only when genome is nil" do
      g1 = single_gene_genome(11)
      l0 = founder(single_gene_genome(10), 0)
      l1 = child_of(l0, g1, 5)
      l0_delta = %{l0 | genome: nil}

      result = AncestralReconstruction.gene_trace([l0_delta, l1], l1.id, 0)

      [target, parent] = result.trace
      assert target.status == :present
      assert parent.status == :delta_only
      assert parent.codons == nil
    end
  end
end
