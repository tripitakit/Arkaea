defmodule Arkea.Views.DomainLandscapeTest do
  use ExUnit.Case, async: true

  alias Arkea.Ecology.Lineage
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Views.DomainLandscape

  # type_tag [0,0,1] → rem(1,11) = 1 → :catalytic_site
  # type_tag [0,0,5] → rem(5,11) = 5 → :dna_binding
  # type_tag [0,0,0] → rem(0,11) = 0 → :substrate_binding

  defp catalytic_domain(weight \\ 10) do
    Domain.new([0, 0, 1], List.duplicate(weight, 20))
  end

  defp dna_binding_domain(weight \\ 7) do
    Domain.new([0, 0, 5], List.duplicate(weight, 20))
  end

  defp gene_with(domains), do: Gene.from_domains(domains)

  defp lineage(genome, abundances \\ %{phase_1: 100}) do
    Lineage.new_founder(genome, abundances, 0)
  end

  test "build/2 returns empty points when no lineage carries the requested type" do
    g = Genome.new([gene_with([dna_binding_domain()])])
    out = DomainLandscape.build([lineage(g)], :catalytic_site)

    assert out.domain_type == :catalytic_site
    assert out.point_count == 0
    assert out.points == []
  end

  test "build/2 surfaces every catalytic_site instance, one per matching domain" do
    # Two genes, one with two catalytic_site domains, the other with one.
    g =
      Genome.new([
        gene_with([catalytic_domain(10), dna_binding_domain(), catalytic_domain(15)]),
        gene_with([catalytic_domain(5)])
      ])

    out = DomainLandscape.build([lineage(g)], :catalytic_site)

    assert out.point_count == 3
    assert length(out.points) == 3
    assert Enum.all?(out.points, &(&1.replicon == :chromosome))
    assert Enum.all?(out.points, &(&1.replicon_index == 0))
  end

  test "each point carries lineage_id, abundance and the domain's params map" do
    g = Genome.new([gene_with([catalytic_domain(8)])])
    l = lineage(g, %{phase_1: 30, phase_2: 70})

    [pt] = DomainLandscape.build([l], :catalytic_site).points

    assert pt.lineage_id == l.id
    assert pt.abundance == 100
    assert is_map(pt.params)
    # :catalytic_site exposes :kcat (continuous param) and :reaction_class.
    assert Map.has_key?(pt.params, :kcat)
    assert Map.has_key?(pt.params, :reaction_class)
  end

  test "domain_index reflects the domain's position inside its gene" do
    g =
      Genome.new([
        gene_with([dna_binding_domain(), catalytic_domain(), catalytic_domain()])
      ])

    out = DomainLandscape.build([lineage(g)], :catalytic_site)

    indices = out.points |> Enum.map(& &1.domain_index) |> Enum.sort()
    assert indices == [1, 2]
  end

  test "lineages with genome: nil (delta-encoded) are skipped" do
    g = Genome.new([gene_with([catalytic_domain()])])
    full = lineage(g)
    delta_only = %{full | genome: nil}

    out = DomainLandscape.build([full, delta_only], :catalytic_site)

    assert out.point_count == 1
    assert hd(out.points).lineage_id == full.id
  end

  test "plasmid and prophage domains are surfaced with the right replicon tag" do
    chromo = gene_with([dna_binding_domain()])
    plasmid_gene = gene_with([catalytic_domain(11)])
    prophage_gene = gene_with([catalytic_domain(13)])

    g =
      Genome.new(
        [chromo],
        plasmids: [[plasmid_gene]],
        prophages: [[prophage_gene]]
      )

    out = DomainLandscape.build([lineage(g)], :catalytic_site)
    by_replicon = Enum.group_by(out.points, & &1.replicon)

    assert map_size(by_replicon) == 2
    assert length(Map.fetch!(by_replicon, :plasmid)) == 1
    assert length(Map.fetch!(by_replicon, :prophage)) == 1
    assert hd(Map.fetch!(by_replicon, :plasmid)).replicon_index == 0
    assert hd(Map.fetch!(by_replicon, :prophage)).replicon_index == 0
  end

  test "replicon_index increments across multiple plasmids / prophages" do
    chromo = gene_with([dna_binding_domain()])
    p0 = gene_with([catalytic_domain(9)])
    p1 = gene_with([catalytic_domain(12)])

    g =
      Genome.new(
        [chromo],
        plasmids: [[p0], [p1]]
      )

    out = DomainLandscape.build([lineage(g)], :catalytic_site)

    plasmid_pts =
      out.points
      |> Enum.filter(&(&1.replicon == :plasmid))
      |> Enum.sort_by(& &1.replicon_index)

    assert Enum.map(plasmid_pts, & &1.replicon_index) == [0, 1]
  end

  test "points across multiple lineages are aggregated into a single list" do
    g1 = Genome.new([gene_with([catalytic_domain(6)])])
    g2 = Genome.new([gene_with([catalytic_domain(7), catalytic_domain(8)])])
    l1 = lineage(g1, %{phase_1: 10})
    l2 = lineage(g2, %{phase_1: 25})

    out = DomainLandscape.build([l1, l2], :catalytic_site)

    assert out.point_count == 3

    counts =
      out.points
      |> Enum.frequencies_by(& &1.lineage_id)

    assert counts[l1.id] == 1
    assert counts[l2.id] == 2
    assert Enum.find(out.points, &(&1.lineage_id == l1.id)).abundance == 10
    assert Enum.find(out.points, &(&1.lineage_id == l2.id)).abundance == 25
  end
end
