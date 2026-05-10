defmodule ArkeaWeb.Components.DomainLandscapePanel do
  @moduledoc """
  Structure-function landscape scatter (Phase 36 / priority 5 — UI
  consumer for `Arkea.Views.DomainLandscape`).

  Renders every domain instance of a chosen `domain_type` across
  the population as a 2D point cloud:

    * **X / Y axes** — two numeric keys from the domain's `params`
      map. The biologically interesting plot for catalytic_site
      is `kcat × Km`; for `:dna_binding` it's
      `binding_affinity × promoter_specificity`. The consumer
      wires both selectors above the scatter.
    * **Point size** ∝ √abundance of the lineage carrying the
      domain (larger lineages dominate the visual mass).
    * **Point colour** by replicon (chromosome / plasmid /
      prophage), letting the player spot variants that
      "live" on mobile DNA.

  Pure markup. The scatter geometry is computed in this
  module from the `Arkea.Views.DomainLandscape.t()` shape
  (no upstream layout module — the panel is small enough
  that inline SVG scaling keeps things readable).

  ## Empty data

  When the chosen `domain_type` has no instances in the
  population, renders a terse "no points" placeholder so the
  player knows the selector landed on an empty domain category.
  """

  use Phoenix.Component

  @canvas_w 540
  @canvas_h 320
  @margin_left 50
  @margin_right 16
  @margin_top 16
  @margin_bottom 36

  attr :landscape, :map, required: true
  attr :x_key, :atom, required: true
  attr :y_key, :atom, required: true
  attr :class, :string, default: nil

  def domain_landscape_panel(assigns) do
    points = filter_numeric_points(assigns.landscape.points, assigns.x_key, assigns.y_key)
    {x_min, x_max} = axis_range(points, assigns.x_key)
    {y_min, y_max} = axis_range(points, assigns.y_key)
    laid_out = layout_points(points, assigns.x_key, assigns.y_key, x_min, x_max, y_min, y_max)

    assigns =
      assign(assigns,
        points: laid_out,
        empty?: points == [],
        x_min: x_min,
        x_max: x_max,
        y_min: y_min,
        y_max: y_max,
        canvas_w: @canvas_w,
        canvas_h: @canvas_h,
        plot_x: @margin_left,
        plot_y: @margin_top,
        plot_w: @canvas_w - @margin_left - @margin_right,
        plot_h: @canvas_h - @margin_top - @margin_bottom
      )

    ~H"""
    <div class={["arkea-landscape", @class]}>
      <div class="arkea-landscape__header">
        <span class="arkea-landscape__counts">
          {@landscape.point_count} points · {@landscape.domain_type}
        </span>
        <span class="arkea-landscape__axes">
          X: {@x_key} · Y: {@y_key}
        </span>
      </div>

      <%= if @empty? do %>
        <p class="arkea-muted" style="margin: var(--arkea-space-3) 0;">
          No domain instances of <code>{@landscape.domain_type}</code> in
          the population, or none with both <code>{@x_key}</code> and <code>{@y_key}</code> populated.
        </p>
      <% else %>
        <svg
          class="arkea-landscape__svg"
          viewBox={"0 0 #{@canvas_w} #{@canvas_h}"}
          preserveAspectRatio="xMidYMid meet"
          role="img"
          aria-label="Domain landscape scatter"
        >
          <%!-- Axis frame --%>
          <line
            class="arkea-landscape__axis"
            x1={@plot_x}
            y1={@plot_y + @plot_h}
            x2={@plot_x + @plot_w}
            y2={@plot_y + @plot_h}
          />
          <line
            class="arkea-landscape__axis"
            x1={@plot_x}
            y1={@plot_y}
            x2={@plot_x}
            y2={@plot_y + @plot_h}
          />

          <%!-- Tick labels --%>
          <text
            class="arkea-landscape__tick"
            x={@plot_x}
            y={@plot_y + @plot_h + 14}
            text-anchor="start"
          >
            {format_axis(@x_min)}
          </text>
          <text
            class="arkea-landscape__tick"
            x={@plot_x + @plot_w}
            y={@plot_y + @plot_h + 14}
            text-anchor="end"
          >
            {format_axis(@x_max)}
          </text>
          <text
            class="arkea-landscape__tick"
            x={@plot_x - 6}
            y={@plot_y + @plot_h}
            text-anchor="end"
            dominant-baseline="alphabetic"
          >
            {format_axis(@y_min)}
          </text>
          <text
            class="arkea-landscape__tick"
            x={@plot_x - 6}
            y={@plot_y + 8}
            text-anchor="end"
            dominant-baseline="alphabetic"
          >
            {format_axis(@y_max)}
          </text>

          <%!-- Axis labels --%>
          <text
            class="arkea-landscape__axis-label"
            x={@plot_x + @plot_w / 2}
            y={@plot_y + @plot_h + 28}
            text-anchor="middle"
          >
            {@x_key}
          </text>
          <text
            class="arkea-landscape__axis-label"
            x={12}
            y={@plot_y + @plot_h / 2}
            text-anchor="middle"
            transform={"rotate(-90 12 #{@plot_y + @plot_h / 2})"}
          >
            {@y_key}
          </text>

          <%!-- Points --%>
          <circle
            :for={p <- @points}
            class={[
              "arkea-landscape__point",
              "arkea-landscape__point--#{p.replicon}"
            ]}
            cx={p.cx}
            cy={p.cy}
            r={p.r}
            data-replicon={p.replicon}
            data-lineage-id={p.lineage_id}
          >
            <title>{point_tooltip(p)}</title>
          </circle>
        </svg>

        <div class="arkea-landscape__legend">
          <span class="arkea-landscape__legend-item">
            <span class="arkea-landscape__legend-swatch arkea-landscape__legend-swatch--chromosome" />chromosome
          </span>
          <span class="arkea-landscape__legend-item">
            <span class="arkea-landscape__legend-swatch arkea-landscape__legend-swatch--plasmid" />plasmid
          </span>
          <span class="arkea-landscape__legend-item">
            <span class="arkea-landscape__legend-swatch arkea-landscape__legend-swatch--prophage" />prophage
          </span>
          <span class="arkea-landscape__legend-note">size ∝ √abundance</span>
        </div>
      <% end %>
    </div>
    """
  end

  defp filter_numeric_points(points, x_key, y_key) do
    Enum.filter(points, fn p ->
      x = Map.get(p.params, x_key)
      y = Map.get(p.params, y_key)
      is_number(x) and is_number(y)
    end)
  end

  defp axis_range([], _key), do: {0.0, 1.0}

  defp axis_range(points, key) do
    values = Enum.map(points, fn p -> Map.get(p.params, key) * 1.0 end)
    lo = Enum.min(values)
    hi = Enum.max(values)
    if hi == lo, do: {lo - 0.5, hi + 0.5}, else: {lo, hi}
  end

  defp layout_points([], _x, _y, _xmin, _xmax, _ymin, _ymax), do: []

  defp layout_points(points, x_key, y_key, x_min, x_max, y_min, y_max) do
    plot_x = @margin_left
    plot_y = @margin_top
    plot_w = @canvas_w - @margin_left - @margin_right
    plot_h = @canvas_h - @margin_top - @margin_bottom

    Enum.map(points, fn p ->
      x = Map.get(p.params, x_key) * 1.0
      y = Map.get(p.params, y_key) * 1.0

      cx = plot_x + (x - x_min) / max(x_max - x_min, 1.0e-9) * plot_w
      cy = plot_y + plot_h - (y - y_min) / max(y_max - y_min, 1.0e-9) * plot_h
      r = max(:math.sqrt(p.abundance) / 2.5, 2.0) |> min(12.0)

      Map.merge(p, %{
        cx: Float.round(cx, 2),
        cy: Float.round(cy, 2),
        r: Float.round(r, 2)
      })
    end)
  end

  defp point_tooltip(p) do
    short_lid = String.slice(p.lineage_id, 0, 8)

    "lineage #{short_lid} · #{p.replicon}#{replicon_index_part(p)}\n" <>
      "abundance #{p.abundance} · gene #{String.slice(p.gene_id, 0, 8)}"
  end

  defp replicon_index_part(%{replicon: :chromosome}), do: ""
  defp replicon_index_part(%{replicon_index: idx}), do: " ##{idx}"

  defp format_axis(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 2)
  defp format_axis(v) when is_integer(v), do: Integer.to_string(v)
  defp format_axis(v), do: to_string(v)
end
