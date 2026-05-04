defmodule Arkea.Views.GenomeCanvasTest do
  use ExUnit.Case, async: true

  alias Arkea.Views.GenomeCanvas

  describe "build/1" do
    test "empty genome produces no genes and no plasmids" do
      layout = GenomeCanvas.build(%{chromosome: [], plasmids: []})

      assert layout.chromosome.genes == []
      assert layout.plasmids == []
      assert layout.viewbox =~ "0 0"
    end

    test "single-gene chromosome produces one full-circle arc with a domain crown" do
      genome = %{
        chromosome: [
          %{
            id: "g1",
            color: "#84cc16",
            domains: [
              %{type: :catalytic_site, label: "CAT", color: "#f59e0b"},
              %{type: :substrate_binding, label: "SB", color: "#38bdf8"}
            ]
          }
        ],
        plasmids: []
      }

      layout = GenomeCanvas.build(genome)
      [gene] = layout.chromosome.genes

      assert gene.id == "g1"
      assert length(gene.domains) == 2
      # The arc path is non-trivial SVG geometry
      assert gene.arc.path_d =~ "M "
      assert gene.arc.path_d =~ " A "
      # Domains carry their pre-computed concentric paths
      assert Enum.all?(gene.domains, &(&1.path_d =~ "M "))
    end

    test "multi-gene chromosome distributes genes around the ring monotonically" do
      genome = %{
        chromosome:
          for i <- 1..5 do
            %{id: "g#{i}", domains: [%{type: :catalytic_site}]}
          end,
        plasmids: []
      }

      layout = GenomeCanvas.build(genome)
      angles = Enum.map(layout.chromosome.genes, & &1.arc.start_angle)

      assert angles == Enum.sort(angles)
      assert length(layout.chromosome.genes) == 5
    end

    test "plasmids render as small circular layouts" do
      genome = %{
        chromosome: [%{id: "core", domains: []}],
        plasmids: [
          %{label: "Plasmid 1", genes: [%{id: "p1", domains: []}]},
          %{label: "Plasmid 2", genes: [%{id: "p2", domains: []}]}
        ]
      }

      layout = GenomeCanvas.build(genome)

      assert length(layout.plasmids) == 2
      assert Enum.map(layout.plasmids, & &1.label) == ["Plasmid 1", "Plasmid 2"]
      # Plasmid radii are smaller than chromosome
      assert Enum.all?(layout.plasmids, &(&1.r_outer < layout.chromosome.r_outer))
    end

    test "is deterministic across calls" do
      genome = %{
        chromosome: [
          %{id: "g1", domains: [%{type: :catalytic_site}]},
          %{id: "g2", domains: [%{type: :substrate_binding}]}
        ],
        plasmids: []
      }

      a = GenomeCanvas.build(genome)
      b = GenomeCanvas.build(genome)

      paths_a = Enum.map(a.chromosome.genes, & &1.arc.path_d)
      paths_b = Enum.map(b.chromosome.genes, & &1.arc.path_d)

      assert paths_a == paths_b
    end

    test "domains tile the gene's angular range without concentric stacking" do
      genome = %{
        chromosome: [
          %{
            id: "g1",
            domains: [
              %{type: :catalytic_site},
              %{type: :substrate_binding},
              %{type: :dna_binding}
            ]
          }
        ],
        plasmids: []
      }

      layout = GenomeCanvas.build(genome)
      [gene] = layout.chromosome.genes

      assert length(gene.domains) == 3

      # Sub-sweeps must be contiguous (each end matches the next start)
      # and together cover the gene's full angular span.
      [d1, d2, d3] = gene.domains
      epsilon = 1.0e-6

      assert abs(d1.start_angle - gene.arc.start_angle) < epsilon
      assert abs(d1.end_angle - d2.start_angle) < epsilon
      assert abs(d2.end_angle - d3.start_angle) < epsilon
      assert abs(d3.end_angle - gene.arc.end_angle) < epsilon

      # No concentric stacking: every domain must span the chromosome's
      # full radial thickness (i.e. the layout no longer carries
      # `r_outer` / `r_inner` per domain).
      assert Enum.all?(gene.domains, fn dom ->
               not Map.has_key?(dom, :r_outer) and not Map.has_key?(dom, :r_inner)
             end)
    end

    test "gene with empty domains keeps the fallback gene arc path" do
      genome = %{
        chromosome: [%{id: "g1", domains: []}],
        plasmids: []
      }

      layout = GenomeCanvas.build(genome)
      [gene] = layout.chromosome.genes

      assert gene.domains == []
      assert gene.arc.path_d =~ "M "
    end

    test "inter-gene gap is small and uniform regardless of gene count" do
      few = GenomeCanvas.build(%{chromosome: gene_list(3), plasmids: []})
      many = GenomeCanvas.build(%{chromosome: gene_list(20), plasmids: []})

      gap_few = inter_gene_gap(few.chromosome.genes)
      gap_many = inter_gene_gap(many.chromosome.genes)

      # Same fixed gap (0.012 rad ≈ 0.7°) regardless of how many genes
      # the ring carries — i.e. it does not collapse the chromosome into
      # a fan of widely-separated arcs.
      epsilon = 1.0e-6
      assert abs(gap_few - gap_many) < epsilon
      assert gap_few < 0.05
    end

    defp gene_list(n) do
      Enum.map(1..n, fn i -> %{id: "g#{i}", domains: [%{type: :catalytic_site}]} end)
    end

    defp inter_gene_gap([_]), do: 0.0

    defp inter_gene_gap(genes) do
      [g1, g2 | _] = genes
      g2.arc.start_angle - g1.arc.end_angle
    end
  end

  describe "domain_color/1" do
    test "returns a stable color per type" do
      types = [
        :substrate_binding,
        :catalytic_site,
        :transmembrane_anchor,
        :channel_pore,
        :energy_coupling,
        :dna_binding,
        :regulator_output,
        :ligand_sensor,
        :structural_fold,
        :surface_tag,
        :repair_fidelity
      ]

      colors = Enum.map(types, &GenomeCanvas.domain_color/1)
      assert length(Enum.uniq(colors)) == length(types)
      assert Enum.all?(colors, &String.starts_with?(&1, "#"))
    end

    test "unknown type falls back to a gray" do
      assert GenomeCanvas.domain_color(:something_else) == "#64748b"
    end
  end
end
