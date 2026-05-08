defmodule Arkea.Genome.OperonTest do
  use ExUnit.Case, async: true

  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Genome.Operon

  @param_codons List.duplicate(10, 20)

  defp gene(opts \\ []) do
    base = Gene.from_domains([Domain.new([0, 0, 1], @param_codons)])
    Map.merge(base, Map.new(opts))
  end

  defp genome(genes), do: Genome.new(genes)

  test "operons/1 with no operon_id annotations returns []" do
    g = genome([gene(), gene(), gene()])
    assert Operon.operons(g) == []
  end

  test "operons/1 groups genes that share an operon_id, in chromosome order" do
    op_id = "op-A"

    g1 = gene(operon_id: op_id)
    g2 = gene()
    g3 = gene(operon_id: op_id)
    g4 = gene(operon_id: op_id)

    g = genome([g1, g2, g3, g4])
    assert [op] = Operon.operons(g)

    assert op.id == op_id
    assert op.leader_gene_id == g1.id
    assert op.gene_ids == [g1.id, g3.id, g4.id]
    assert op.gene_count == 3
  end

  test "operons/1 returns one entry per distinct operon_id, in first-seen order" do
    g1 = gene(operon_id: "op-A")
    g2 = gene(operon_id: "op-B")
    g3 = gene(operon_id: "op-A")

    [a, b] = Operon.operons(genome([g1, g2, g3]))
    assert a.id == "op-A"
    assert a.gene_ids == [g1.id, g3.id]
    assert b.id == "op-B"
    assert b.gene_ids == [g2.id]
  end

  test "solo_genes/1 returns the genes without an operon_id, in chromosome order" do
    g1 = gene()
    g2 = gene(operon_id: "op-A")
    g3 = gene()

    solos = Operon.solo_genes(genome([g1, g2, g3]))
    assert Enum.map(solos, & &1.id) == [g1.id, g3.id]
  end

  test "containing/2 returns the operon entry that holds a gene id" do
    g1 = gene(operon_id: "op-A")
    g2 = gene(operon_id: "op-A")
    g3 = gene()

    assert %{id: "op-A", gene_ids: ids} = Operon.containing(genome([g1, g2, g3]), g2.id)
    assert g2.id in ids

    assert is_nil(Operon.containing(genome([g1, g2, g3]), g3.id))
    assert is_nil(Operon.containing(genome([g1, g2, g3]), Arkea.UUID.v4()))
  end

  test "same_operon?/3 is true for two members, false for solo / cross-operon pairs" do
    g1 = gene(operon_id: "op-A")
    g2 = gene(operon_id: "op-A")
    g3 = gene(operon_id: "op-B")
    g4 = gene()

    g = genome([g1, g2, g3, g4])
    assert Operon.same_operon?(g, g1.id, g2.id)
    refute Operon.same_operon?(g, g1.id, g3.id)
    refute Operon.same_operon?(g, g1.id, g4.id)
    refute Operon.same_operon?(g, g4.id, g4.id)
  end

  test "leader_gene/2 returns the leader struct" do
    g1 = gene(operon_id: "op-A")
    g2 = gene(operon_id: "op-A")
    g = genome([g1, g2])
    [op] = Operon.operons(g)

    leader = Operon.leader_gene(g, op)
    assert leader.id == g1.id
  end
end
