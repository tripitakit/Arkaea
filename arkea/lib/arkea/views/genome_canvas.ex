defmodule Arkea.Views.GenomeCanvas do
  @moduledoc """
  Pure layout for the circular genome canvas (UI rewrite — phase U5).

  Given a genome (chromosome list of genes + plasmids list), produces SVG-ready
  geometry: arcs for each gene around a central circle, mini-rectangles for
  the domain crown inside each arc, and small circular layouts for plasmids.

  Output is pure data (atom-keyed maps) — no I/O, no rendering.

  ## Output shape

      %{
        viewbox: "0 0 W H",
        width: 600, height: 400,
        chromosome: %{
          cx, cy, r_outer, r_inner,
          genes: [%{
            id, index,
            arc: %{start_angle, end_angle, path_d, color, label, label_x, label_y, label_anchor},
            domains: [%{
              index, type, label, color,
              path_d (concentric mini-arc), tooltip,
              center_x, center_y    # for hit-testing fallback
            }]
          }]
        },
        plasmids: [%{
          cx, cy, r_outer, r_inner, label,
          genes: [...same shape as above, smaller radii]
        }]
      }
  """

  @canvas_w 600
  @canvas_h 480
  @chrom_cx 200
  @chrom_cy 200
  @chrom_r_outer 140
  @chrom_r_inner 95
  @plasmid_radius 60
  @plasmid_inner 30
  @plasmid_grid_x 380
  @plasmid_grid_y 80
  @plasmid_step 150

  @type domain_data :: %{type: atom(), label: String.t(), color: String.t()}

  @type gene_data :: %{
          id: binary(),
          domains: [domain_data()]
        }

  @type genome_data :: %{
          chromosome: [gene_data()],
          plasmids: [%{label: String.t(), genes: [gene_data()]}]
        }

  @type layout :: map()

  @spec build(genome_data()) :: layout()
  def build(genome) when is_map(genome) do
    chromosome = genome[:chromosome] || []
    plasmids = genome[:plasmids] || []

    %{
      width: @canvas_w,
      height: @canvas_h,
      viewbox: "0 0 #{@canvas_w} #{@canvas_h}",
      chromosome:
        layout_replicon(chromosome, @chrom_cx, @chrom_cy, @chrom_r_outer, @chrom_r_inner),
      plasmids: layout_plasmids(plasmids)
    }
  end

  def viewbox, do: "0 0 #{@canvas_w} #{@canvas_h}"

  defp layout_replicon([], cx, cy, r_outer, r_inner) do
    %{cx: cx, cy: cy, r_outer: r_outer, r_inner: r_inner, genes: []}
  end

  # Inter-gene gap, in radians. Small fixed value: a thin tick mark separates
  # consecutive genes regardless of gene count, so the chromosome reads as a
  # closed ring of segments rather than as a fan of isolated arcs.
  @gene_gap_rad 0.012

  defp layout_replicon(genes, cx, cy, r_outer, r_inner) do
    n = length(genes)
    full_circle = 2 * :math.pi()

    # Total angular space available for genes is the circle minus n × gap.
    # For n=1 we use the whole circle minus a tiny ε so the SVG arc remains
    # non-degenerate (start ≈ end would render as nothing).
    {sweep_per_gene, gap} =
      cond do
        n == 0 ->
          {0.0, 0.0}

        n == 1 ->
          {full_circle - 0.0001, 0.0}

        true ->
          s = (full_circle - n * @gene_gap_rad) / n
          {s, @gene_gap_rad}
      end

    laid_genes =
      genes
      |> Enum.with_index()
      |> Enum.map(fn {gene, index} ->
        # Start at 12 o'clock (-π/2). Each gene takes `sweep_per_gene` radians,
        # followed by a `gap` radians notch before the next gene starts.
        start = -:math.pi() / 2 + index * (sweep_per_gene + gap)
        endd = start + sweep_per_gene
        layout_gene(gene, index, cx, cy, r_outer, r_inner, start, endd)
      end)

    %{cx: cx, cy: cy, r_outer: r_outer, r_inner: r_inner, genes: laid_genes}
  end

  defp layout_gene(gene, index, cx, cy, r_outer, r_inner, start_angle, end_angle) do
    label_mid = (start_angle + end_angle) / 2
    label_r = r_outer + 12
    label_x = cx + label_r * :math.cos(label_mid)
    label_y = cy + label_r * :math.sin(label_mid)

    label_anchor =
      cond do
        :math.cos(label_mid) > 0.3 -> "start"
        :math.cos(label_mid) < -0.3 -> "end"
        true -> "middle"
      end

    # Click target: full gene wedge from r_inner to r_outer over the gene's
    # angular span. Renders only as transparent overlay when domains are
    # present (the gene's visual content IS its domain sub-arcs); used as
    # the visible filled wedge when the gene has no domains (fallback).
    full_path = ring_arc_path(cx, cy, r_outer, r_inner, start_angle, end_angle)

    domains = gene[:domains] || []

    laid_domains =
      if domains == [] do
        []
      else
        # Split the gene's angular range into N equal sub-sweeps, one per
        # domain. Each sub-arc fills the FULL radial thickness (r_inner →
        # r_outer) of the chromosome ring. No concentric crown — domains
        # are now linear segments along the chromosome itself.
        per_domain = (end_angle - start_angle) / length(domains)

        domains
        |> Enum.with_index()
        |> Enum.map(fn {dom, dindex} ->
          d_start = start_angle + dindex * per_domain
          d_end = d_start + per_domain
          layout_domain(dom, dindex, cx, cy, r_inner, r_outer, d_start, d_end)
        end)
      end

    %{
      id: gene[:id] || "gene-#{index}",
      index: index,
      label: gene[:label] || "g#{index + 1}",
      arc: %{
        path_d: full_path,
        color: gene[:color] || "#94a3b8",
        start_angle: start_angle,
        end_angle: end_angle,
        label_x: label_x,
        label_y: label_y,
        label_anchor: label_anchor,
        editable?: gene[:editable?] || false
      },
      domains: laid_domains
    }
  end

  defp layout_domain(dom, dindex, cx, cy, r_inner, r_outer, d_start, d_end) do
    # Each domain is a thin angular wedge spanning the full chromosome
    # thickness (r_inner..r_outer). Adjacent domains within the same gene
    # share their cut edges — no internal padding, so the gene reads as a
    # contiguous striped segment.
    path_d = ring_arc_path(cx, cy, r_outer, r_inner, d_start, d_end)

    mid_angle = (d_start + d_end) / 2
    mid_r = (r_outer + r_inner) / 2

    %{
      index: dindex,
      type: dom[:type],
      label: dom[:label] || domain_short_label(dom[:type]),
      color: dom[:color] || "#64748b",
      path_d: path_d,
      tooltip: domain_tooltip(dom),
      center_x: cx + mid_r * :math.cos(mid_angle),
      center_y: cy + mid_r * :math.sin(mid_angle),
      start_angle: d_start,
      end_angle: d_end
    }
  end

  defp layout_plasmids([]), do: []

  defp layout_plasmids(plasmids) do
    plasmids
    |> Enum.with_index()
    |> Enum.map(fn {p, idx} ->
      cx = @plasmid_grid_x + rem(idx, 2) * @plasmid_step
      cy = @plasmid_grid_y + div(idx, 2) * @plasmid_step
      layout = layout_replicon(p[:genes] || [], cx, cy, @plasmid_radius, @plasmid_inner)
      Map.put(layout, :label, p[:label] || "Plasmid #{idx + 1}")
    end)
  end

  # ---------------------------------------------------------------------------
  # SVG path geometry: a closed ring sector (annular wedge).

  defp ring_arc_path(cx, cy, r_outer, r_inner, start_angle, end_angle) do
    large_arc = if end_angle - start_angle > :math.pi(), do: 1, else: 0

    x1 = cx + r_outer * :math.cos(start_angle)
    y1 = cy + r_outer * :math.sin(start_angle)
    x2 = cx + r_outer * :math.cos(end_angle)
    y2 = cy + r_outer * :math.sin(end_angle)

    x3 = cx + r_inner * :math.cos(end_angle)
    y3 = cy + r_inner * :math.sin(end_angle)
    x4 = cx + r_inner * :math.cos(start_angle)
    y4 = cy + r_inner * :math.sin(start_angle)

    [
      "M ",
      f(x1),
      " ",
      f(y1),
      " A ",
      f(r_outer),
      " ",
      f(r_outer),
      " 0 ",
      Integer.to_string(large_arc),
      " 1 ",
      f(x2),
      " ",
      f(y2),
      " L ",
      f(x3),
      " ",
      f(y3),
      " A ",
      f(r_inner),
      " ",
      f(r_inner),
      " 0 ",
      Integer.to_string(large_arc),
      " 0 ",
      f(x4),
      " ",
      f(y4),
      " Z"
    ]
    |> IO.iodata_to_binary()
  end

  defp f(num) when is_number(num) do
    Float.round(num * 1.0, 2) |> Float.to_string()
  end

  # ---------------------------------------------------------------------------
  # Domain naming helpers (UI-only; no biology dependency).

  defp domain_short_label(:substrate_binding), do: "SB"
  defp domain_short_label(:catalytic_site), do: "CAT"
  defp domain_short_label(:transmembrane_anchor), do: "TM"
  defp domain_short_label(:channel_pore), do: "CH"
  defp domain_short_label(:energy_coupling), do: "EC"
  defp domain_short_label(:dna_binding), do: "DNA"
  defp domain_short_label(:regulator_output), do: "REG"
  defp domain_short_label(:ligand_sensor), do: "LIG"
  defp domain_short_label(:structural_fold), do: "SF"
  defp domain_short_label(:surface_tag), do: "ST"
  defp domain_short_label(:repair_fidelity), do: "RPR"
  defp domain_short_label(_), do: "·"

  defp domain_tooltip(%{tooltip: t}) when is_binary(t), do: t
  defp domain_tooltip(%{type: type, label: label}) when is_binary(label), do: "#{label} (#{type})"
  defp domain_tooltip(%{type: type}) when is_atom(type), do: Atom.to_string(type)
  defp domain_tooltip(_), do: ""

  # ---------------------------------------------------------------------------
  # Convenience: derive the canvas data shape from a genome preview struct
  # (`Arkea.Game.SeedLab.preview/1` output → canvas input).

  @doc """
  Map a real `%Arkea.Genome{}` (with chromosome/plasmids/prophages of
  `Gene.t()` records carrying domains) to the lightweight `genome_data`
  shape `build/1` consumes. Custom genes carry their `editable?` flag so the
  UI can render reorder buttons next to them.
  """
  @spec from_preview(map()) :: genome_data()
  def from_preview(preview) when is_map(preview) do
    custom_count = preview[:custom_gene_count] || 0
    total = length(preview.genome.chromosome)
    base_count = total - custom_count

    chromosome =
      preview.genome.chromosome
      |> Enum.with_index()
      |> Enum.map(fn {gene, idx} ->
        editable? = idx >= base_count
        gene_to_canvas(gene, editable?)
      end)

    plasmids =
      Enum.with_index(preview.genome.plasmids, fn p, idx ->
        plasmid_genes =
          case p do
            %{genes: gs} -> gs
            list when is_list(list) -> list
          end

        %{
          label: "Plasmid #{idx + 1}",
          genes: Enum.map(plasmid_genes, &gene_to_canvas(&1, false))
        }
      end)

    %{chromosome: chromosome, plasmids: plasmids}
  end

  defp gene_to_canvas(gene, editable?) do
    domains =
      Enum.map(gene.domains || [], fn domain ->
        %{
          type: domain.type,
          label: domain_short_label(domain.type),
          color: domain_color(domain.type)
        }
      end)

    %{
      id: gene.id,
      label: short_id(gene.id),
      color: gene_color(gene),
      domains: domains,
      editable?: editable?
    }
  end

  defp gene_color(gene) do
    sig = :erlang.phash2({gene.id, length(gene.domains || [])}, 360)
    hue = rem(sig, 360)
    "hsl(#{hue} 60% 56%)"
  end

  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 6)
  defp short_id(_), do: "?"

  @doc """
  Color of a single domain type. Stable palette aligned with the biological
  intent (binding/transport in cool tones, catalytic/structural in warm).
  """
  def domain_color(:substrate_binding), do: "#38bdf8"
  def domain_color(:catalytic_site), do: "#f59e0b"
  def domain_color(:transmembrane_anchor), do: "#fb7185"
  def domain_color(:channel_pore), do: "#22d3ee"
  def domain_color(:energy_coupling), do: "#facc15"
  def domain_color(:dna_binding), do: "#a78bfa"
  def domain_color(:regulator_output), do: "#84cc16"
  def domain_color(:ligand_sensor), do: "#f97316"
  def domain_color(:structural_fold), do: "#ef4444"
  def domain_color(:surface_tag), do: "#10b981"
  def domain_color(:repair_fidelity), do: "#94a3b8"
  def domain_color(_), do: "#64748b"
end
