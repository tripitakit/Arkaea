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
