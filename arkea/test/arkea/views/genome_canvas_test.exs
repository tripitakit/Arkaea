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

  describe "replicon distinction (Phase 26 / 8.9)" do
    test "chromosome layout carries replicon_kind: :chromosome" do
      layout = GenomeCanvas.build(%{chromosome: [%{id: "g1", domains: []}], plasmids: []})

      assert layout.chromosome.replicon_kind == :chromosome
    end

    test "plasmids carry replicon_kind: :plasmid" do
      layout =
        GenomeCanvas.build(%{
          chromosome: [%{id: "core", domains: []}],
          plasmids: [%{label: "Plasmid 1", genes: []}]
        })

      assert Enum.all?(layout.plasmids, &(&1.replicon_kind == :plasmid))
    end

    test "prophages render as a separate list with replicon_kind: :prophage and state" do
      layout =
        GenomeCanvas.build(%{
          chromosome: [%{id: "core", domains: []}],
          plasmids: [],
          prophages: [
            %{label: "Prophage 1", state: :lysogenic, genes: [%{id: "ph1", domains: []}]},
            %{label: "Prophage 2", state: :induced, genes: []}
          ]
        })

      assert length(layout.prophages) == 2
      assert Enum.all?(layout.prophages, &(&1.replicon_kind == :prophage))

      [p0, p1] = layout.prophages
      assert p0.label == "Prophage 1"
      assert p0.state == :lysogenic
      assert p1.label == "Prophage 2"
      assert p1.state == :induced
    end

    test "prophages and plasmids are positioned in distinct regions of the canvas" do
      layout =
        GenomeCanvas.build(%{
          chromosome: [%{id: "core", domains: []}],
          plasmids: [%{label: "Plasmid 1", genes: []}],
          prophages: [%{label: "Prophage 1", genes: []}]
        })

      [plasmid] = layout.plasmids
      [prophage] = layout.prophages
      # Prophages are placed in their own region (cy differs from plasmids).
      assert prophage.cy != plasmid.cy
    end

    test "missing prophages key defaults to []" do
      layout =
        GenomeCanvas.build(%{chromosome: [%{id: "core", domains: []}], plasmids: []})

      assert layout.prophages == []
    end
  end

  describe "rich_domain_tooltip/2 (Phase 26 / 8.10)" do
    test "catalytic_site surfaces reaction class + kcat + cofactor flag" do
      tip =
        GenomeCanvas.rich_domain_tooltip(:catalytic_site, %{
          reaction_class: :hydrolysis,
          kcat: 4.96,
          cofactor_required: true
        })

      assert tip =~ "catalytic_site"
      assert tip =~ "hydrolysis"
      assert tip =~ "kcat=4.96"
      assert tip =~ "+cofactor"
    end

    test "substrate_binding surfaces target + Km + breadth" do
      tip =
        GenomeCanvas.rich_domain_tooltip(:substrate_binding, %{
          target_metabolite_id: "glucose",
          km: 0.42,
          specificity_breadth: 0.18
        })

      assert tip =~ "substrate_binding"
      assert tip =~ "→glucose"
      assert tip =~ "Km=0.42"
      assert tip =~ "breadth=0.18"
    end

    test "dna_binding surfaces affinity + promoter specificity" do
      tip =
        GenomeCanvas.rich_domain_tooltip(:dna_binding, %{
          binding_affinity: 0.51,
          promoter_specificity: 0.62
        })

      assert tip =~ "affinity=0.51"
      assert tip =~ "spec=0.62"
    end

    test "ligand_sensor surfaces sensed metabolite + threshold + curve" do
      tip =
        GenomeCanvas.rich_domain_tooltip(:ligand_sensor, %{
          sensed_metabolite_id: "ammonia",
          threshold: 0.12,
          response_curve: :hill
        })

      assert tip =~ "senses ammonia"
      assert tip =~ "θ=0.12"
      assert tip =~ "hill"
    end

    test "missing params falls back to bare type name" do
      assert GenomeCanvas.rich_domain_tooltip(:surface_tag, %{}) ==
               "surface_tag"
    end

    test "unknown type returns just the type name" do
      assert GenomeCanvas.rich_domain_tooltip(:unknown, %{}) == "unknown"
    end

    test "cofactor flag false is omitted (only positive flags surface)" do
      tip =
        GenomeCanvas.rich_domain_tooltip(:catalytic_site, %{
          reaction_class: :oxidation,
          kcat: 1.0,
          cofactor_required: false
        })

      refute tip =~ "+cofactor"
      assert tip =~ "oxidation"
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
