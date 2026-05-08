defmodule Arkea.Views.RegulatoryNetworkTest do
  use ExUnit.Case, async: true

  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Views.RegulatoryNetwork

  @param_codons List.duplicate(10, 20)

  defp catalytic_gene, do: Gene.from_domains([Domain.new([0, 0, 1], @param_codons)])
  defp dna_binding_gene, do: Gene.from_domains([Domain.new([0, 0, 5], @param_codons)])

  defp regulator_gene do
    Gene.from_domains([
      Domain.new([0, 0, 5], @param_codons),
      Domain.new([0, 0, 6], [0 | List.duplicate(10, 19)])
    ])
  end

  defp gene_with_riboswitch do
    %{catalytic_gene() | regulatory_block: [3, 10, 0, 0, 19]}
  end

  test "build/1 produces one :gene node per chromosome gene" do
    g = Genome.new([catalytic_gene(), dna_binding_gene()])
    model = RegulatoryNetwork.build(g)

    assert model.gene_count == 2
    gene_nodes = Enum.filter(model.nodes, &(&1.kind == :gene))
    assert length(gene_nodes) == 2
  end

  test "build/1 surfaces operon membership edges with leader flag" do
    g1 = %{catalytic_gene() | operon_id: "op-A"}
    g2 = %{dna_binding_gene() | operon_id: "op-A"}
    g = Genome.new([g1, g2])

    model = RegulatoryNetwork.build(g)
    assert model.operon_count == 1

    edges = Enum.filter(model.edges, &(&1.kind == :operon_member))
    assert length(edges) == 2

    leader_edges = Enum.filter(edges, & &1.payload.leader?)
    assert match?([%{from: leader_id}] when leader_id == g1.id, leader_edges)
  end

  test "build/1 emits regulator_output edges (genome → signal node)" do
    # A regulator + dna_binding gene; phenotype.regulatory_outputs
    # surfaces one entry; without a co-located ligand_sensor the
    # signal_key is nil → routed to "signal:none".
    g = Genome.new([regulator_gene()])
    model = RegulatoryNetwork.build(g)

    reg_edges = Enum.filter(model.edges, &(&1.kind == :regulator_output))
    assert length(reg_edges) == 1
    assert hd(reg_edges).mode == :activator
  end

  test "build/1 emits riboswitch edges (metabolite → gene)" do
    g = Genome.new([gene_with_riboswitch()])
    model = RegulatoryNetwork.build(g)

    edges = Enum.filter(model.edges, &(&1.kind == :riboswitch))
    assert length(edges) == 1
    [r] = edges
    # 3 % 13 = 3 → "met:3"
    assert r.from == "met:3"
    assert r.payload.metabolite_id == 3

    metabolites = Enum.filter(model.nodes, &(&1.kind == :metabolite))
    assert length(metabolites) == 1
    assert hd(metabolites).id == "met:3"
  end

  test "build/1 counts roll up correctly" do
    g =
      Genome.new([
        %{catalytic_gene() | operon_id: "op-X"},
        %{regulator_gene() | operon_id: "op-X"},
        gene_with_riboswitch()
      ])

    model = RegulatoryNetwork.build(g)
    assert model.gene_count == 3
    assert model.operon_count == 1
    assert model.regulator_count >= 1
    assert model.riboswitch_count == 1
  end

  test "build/1 with a chromosome of plain catalytic genes has no edges" do
    g = Genome.new([catalytic_gene(), catalytic_gene()])
    model = RegulatoryNetwork.build(g)

    assert model.gene_count == 2
    assert model.operon_count == 0
    assert model.regulator_count == 0
    assert model.riboswitch_count == 0
    assert model.edges == []
  end
end
