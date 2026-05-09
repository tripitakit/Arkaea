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
  # Prophage column: same horizontal anchor as plasmids but offset by one column.
  # Two replicons per row, vertical step matches plasmids.
  @prophage_grid_x 380
  @prophage_grid_y 280

  @type domain_data :: %{type: atom(), label: String.t(), color: String.t()}

  @type gene_data :: %{
          id: binary(),
          domains: [domain_data()]
        }

  @type genome_data :: %{
          chromosome: [gene_data()],
          plasmids: [%{label: String.t(), genes: [gene_data()]}],
          prophages: [
            %{
              label: String.t(),
              genes: [gene_data()],
              state: :lysogenic | :induced
            }
          ]
        }

  @type layout :: map()

  @spec build(genome_data()) :: layout()
  def build(genome) when is_map(genome) do
    chromosome = genome[:chromosome] || []
    plasmids = genome[:plasmids] || []
    prophages = genome[:prophages] || []

    chromosome_layout =
      chromosome
      |> layout_replicon(@chrom_cx, @chrom_cy, @chrom_r_outer, @chrom_r_inner)
      |> Map.put(:replicon_kind, :chromosome)

    %{
      width: @canvas_w,
      height: @canvas_h,
      viewbox: "0 0 #{@canvas_w} #{@canvas_h}",
      chromosome: chromosome_layout,
      plasmids: layout_plasmids(plasmids),
      prophages: layout_prophages(prophages)
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

      p[:genes]
      |> List.wrap()
      |> layout_replicon(cx, cy, @plasmid_radius, @plasmid_inner)
      |> Map.merge(%{
        label: p[:label] || "Plasmid #{idx + 1}",
        replicon_kind: :plasmid
      })
    end)
  end

  defp layout_prophages([]), do: []

  defp layout_prophages(prophages) do
    prophages
    |> Enum.with_index()
    |> Enum.map(fn {p, idx} ->
      cx = @prophage_grid_x + rem(idx, 2) * @plasmid_step
      cy = @prophage_grid_y + div(idx, 2) * @plasmid_step
      state = p[:state] || :lysogenic

      p[:genes]
      |> List.wrap()
      |> layout_replicon(cx, cy, @plasmid_radius, @plasmid_inner)
      |> Map.merge(%{
        label: p[:label] || "Prophage #{idx + 1}",
        replicon_kind: :prophage,
        state: state
      })
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

    prophages =
      Enum.with_index(preview.genome.prophages, fn ph, idx ->
        prophage_genes =
          case ph do
            %{genes: gs} -> gs
            list when is_list(list) -> list
          end

        state =
          case ph do
            %{state: s} -> s
            _ -> :lysogenic
          end

        %{
          label: "Prophage #{idx + 1}",
          state: state,
          genes: Enum.map(prophage_genes, &gene_to_canvas(&1, false))
        }
      end)

    %{chromosome: chromosome, plasmids: plasmids, prophages: prophages}
  end

  defp gene_to_canvas(gene, editable?) do
    domains =
      Enum.map(gene.domains || [], fn domain ->
        %{
          type: domain.type,
          label: domain_short_label(domain.type),
          color: domain_color(domain.type),
          params: Map.get(domain, :params, %{}),
          tooltip: rich_domain_tooltip(domain.type, Map.get(domain, :params, %{}))
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
  Render a chemically/functionally-meaningful tooltip line for a domain.

  Phase 26 / 8.10. Translates the per-type `params` map (produced by
  `Domain.compute_params/1`) into a single human-readable string with
  the key biological values:

    * `:catalytic_site` → reaction class + `kcat` + cofactor flag
    * `:substrate_binding` → target metabolite + `Km` + breadth
    * `:dna_binding` → binding affinity + promoter specificity
    * `:ligand_sensor` → sensed metabolite + threshold + response curve
    * `:transmembrane_anchor` → hydrophobicity + n_passes
    * `:channel_pore` → selectivity + gating threshold
    * `:energy_coupling` → ATP cost + PMF coupling
    * `:regulator_output` → mode + cooperativity
    * `:structural_fold` → stability + multimerisation
    * `:surface_tag` → tag class
    * `:repair_fidelity` → repair class + efficiency

  The output is intentionally compact (one line) so it slots into a
  `<title>` SVG element without overflowing. Returns just the type
  name when params are missing or empty.
  """
  @spec rich_domain_tooltip(atom(), map()) :: String.t()
  def rich_domain_tooltip(type, params) when is_atom(type) and is_map(params) do
    name = Atom.to_string(type)

    case domain_param_summary(type, params) do
      "" -> name
      summary -> "#{name} — #{summary}"
    end
  end

  defp domain_param_summary(:catalytic_site, p) do
    parts = [
      pretty_atom(p[:reaction_class]),
      kcat_part(p[:kcat]),
      cofactor_part(p[:cofactor_required])
    ]

    join_parts(parts)
  end

  defp domain_param_summary(:substrate_binding, p) do
    parts = [
      target_part(p[:target_metabolite_id]),
      km_part(p[:km]),
      breadth_part(p[:specificity_breadth])
    ]

    join_parts(parts)
  end

  defp domain_param_summary(:dna_binding, p) do
    parts = [
      affinity_part(p[:binding_affinity]),
      promoter_part(p[:promoter_specificity])
    ]

    join_parts(parts)
  end

  defp domain_param_summary(:ligand_sensor, p) do
    parts = [
      sensed_part(p[:sensed_metabolite_id]),
      threshold_part(p[:threshold]),
      pretty_atom(p[:response_curve])
    ]

    join_parts(parts)
  end

  defp domain_param_summary(:transmembrane_anchor, p) do
    parts = [
      hydro_part(p[:hydrophobicity]),
      n_passes_part(p[:n_passes])
    ]

    join_parts(parts)
  end

  defp domain_param_summary(:channel_pore, p) do
    parts = [
      selectivity_part(p[:selectivity]),
      gating_part(p[:gating_threshold])
    ]

    join_parts(parts)
  end

  defp domain_param_summary(:energy_coupling, p) do
    parts = [
      atp_part(p[:atp_cost]),
      pmf_part(p[:pmf_coupling])
    ]

    join_parts(parts)
  end

  defp domain_param_summary(:regulator_output, p) do
    parts = [
      pretty_atom(p[:mode]),
      coop_part(p[:cooperativity])
    ]

    join_parts(parts)
  end

  defp domain_param_summary(:structural_fold, p) do
    parts = [
      stability_part(p[:stability]),
      multi_part(p[:multimerization_n])
    ]

    join_parts(parts)
  end

  defp domain_param_summary(:surface_tag, p), do: pretty_atom(p[:tag_class])

  defp domain_param_summary(:repair_fidelity, p) do
    parts = [
      pretty_atom(p[:repair_class]),
      efficiency_part(p[:efficiency])
    ]

    join_parts(parts)
  end

  defp domain_param_summary(_, _), do: ""

  defp join_parts(parts) do
    parts
    |> Enum.reject(&(&1 == "" or is_nil(&1)))
    |> Enum.join(", ")
  end

  defp pretty_atom(nil), do: ""
  defp pretty_atom(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp pretty_atom(other) when is_binary(other), do: other
  defp pretty_atom(_), do: ""

  defp kcat_part(nil), do: ""
  defp kcat_part(v) when is_number(v), do: "kcat=#{format_float(v)} s⁻¹"

  defp km_part(nil), do: ""
  defp km_part(v) when is_number(v), do: "Km=#{format_float(v)}"

  defp affinity_part(nil), do: ""
  defp affinity_part(v) when is_number(v), do: "affinity=#{format_float(v)}"

  defp promoter_part(nil), do: ""
  defp promoter_part(v) when is_number(v), do: "spec=#{format_float(v)}"

  defp threshold_part(nil), do: ""
  defp threshold_part(v) when is_number(v), do: "θ=#{format_float(v)}"

  defp hydro_part(nil), do: ""
  defp hydro_part(v) when is_number(v), do: "ϕ=#{format_float(v)}"

  defp n_passes_part(nil), do: ""
  defp n_passes_part(v) when is_integer(v), do: "passes=#{v}"

  defp selectivity_part(nil), do: ""
  defp selectivity_part(v) when is_number(v), do: "sel=#{format_float(v)}"

  defp gating_part(nil), do: ""
  defp gating_part(v) when is_number(v), do: "gate=#{format_float(v)}"

  defp atp_part(nil), do: ""
  defp atp_part(v) when is_number(v), do: "ATP=#{format_float(v)}"

  defp pmf_part(nil), do: ""
  defp pmf_part(v) when is_number(v), do: "PMF=#{format_float(v)}"

  defp coop_part(nil), do: ""
  defp coop_part(v) when is_number(v), do: "n_H=#{format_float(v)}"

  defp stability_part(nil), do: ""
  defp stability_part(v) when is_number(v), do: "stab=#{format_float(v)}"

  defp multi_part(nil), do: ""
  defp multi_part(v) when is_integer(v), do: "n_mer=#{v}"

  defp efficiency_part(nil), do: ""
  defp efficiency_part(v) when is_number(v), do: "eff=#{format_float(v)}"

  defp breadth_part(nil), do: ""
  defp breadth_part(v) when is_number(v), do: "breadth=#{format_float(v)}"

  defp target_part(nil), do: ""
  defp target_part(v) when is_binary(v), do: "→#{v}"
  defp target_part(v) when is_atom(v), do: "→#{Atom.to_string(v)}"
  defp target_part(v), do: "→#{inspect(v)}"

  defp sensed_part(nil), do: ""
  defp sensed_part(v) when is_binary(v), do: "senses #{v}"
  defp sensed_part(v) when is_atom(v), do: "senses #{Atom.to_string(v)}"
  defp sensed_part(v), do: "senses #{inspect(v)}"

  defp cofactor_part(true), do: "+cofactor"
  defp cofactor_part(false), do: ""
  defp cofactor_part(_), do: ""

  defp format_float(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 2)
  defp format_float(v) when is_integer(v), do: Integer.to_string(v)

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
