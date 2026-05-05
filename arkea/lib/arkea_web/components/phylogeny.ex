defmodule ArkeaWeb.Components.Phylogeny do
  @moduledoc """
  Phoenix function component that renders the lineage dendrogram built
  by `Arkea.Views.Phylogeny.build/3`.

  Pure SVG, no JS chart library. The layout is a top-down dendrogram:

  - Each lineage is a node positioned at its **cumulative p-distance**
    from the root (vertical axis).
  - Sibling spread runs along the horizontal axis.
  - Edges are right-angle L-shapes (parent vertical drop → horizontal
    span → child vertical drop) so divergence depth is read off the
    y-coordinate of the horizontal segment.
  - Leaves (lineages with no descendants in the input set) carry a
    short-id label; internal nodes (lineages that branched) are
    rendered as smaller anchor dots.
  - Extinct lineages render in grey with a dashed outline regardless
    of position.
  """
  use Phoenix.Component

  @padding 24

  attr :model, :map, required: true, doc: "Arkea.Views.Phylogeny.t()"
  attr :class, :string, default: nil
  attr :width, :integer, default: 960
  attr :height, :integer, default: 360

  def phylogeny(assigns) do
    %{model: model} = assigns

    inner_w = max(model.width, 100.0)
    inner_h = max(model.height, 100.0)

    x_scale = fn x -> x * (assigns.width - 2 * @padding) / inner_w + @padding end
    y_scale = fn y -> y * (assigns.height - 2 * @padding) / inner_h + @padding end

    nodes_by_id = Map.new(model.nodes, fn n -> {n.id, n} end)

    assigns =
      assigns
      |> assign(:x_scale, x_scale)
      |> assign(:y_scale, y_scale)
      |> assign(:nodes_by_id, nodes_by_id)
      |> assign(:has_data?, model.nodes != [])

    ~H"""
    <div class={["arkea-phylogeny", @class]}>
      <%= cond do %>
        <% not @has_data? -> %>
          <div class="arkea-phylogeny__empty">
            No lineages to plot — provision a home and let the simulation run a few ticks.
          </div>
        <% true -> %>
          <svg
            class="arkea-phylogeny__svg"
            viewBox={"0 0 #{@width} #{@height}"}
            preserveAspectRatio="xMidYMid meet"
            role="img"
            aria-label="Lineage phylogeny dendrogram"
          >
            <%!-- Edges (right-angle L-shape: parent_y → child_y at parent_x, then horizontal to child_x) --%>
            <g class="arkea-phylogeny__edges">
              <%= for edge <- @model.edges do %>
                <%= case {Map.get(@nodes_by_id, edge.from), Map.get(@nodes_by_id, edge.to)} do %>
                  <% {nil, _} -> %>
                  <% {_, nil} -> %>
                  <% {parent, child} -> %>
                    <% px = @x_scale.(parent.x) %>
                    <% py = @y_scale.(parent.y) %>
                    <% cx = @x_scale.(child.x) %>
                    <% cy = @y_scale.(child.y) %>
                    <%!--
                      Horizontal dendrogram edge: leave the parent
                      horizontally at parent.y, drop vertically at
                      parent.x to child.y, then horizontally to the
                      child anchor. This keeps the visible "trunk"
                      length equal to (child.x - parent.x), i.e. the
                      child's branch_length × scale.
                    --%>
                    <path
                      d={"M#{fmt(px)} #{fmt(py)} L#{fmt(px)} #{fmt(cy)} L#{fmt(cx)} #{fmt(cy)}"}
                      class={[
                        "arkea-phylogeny__edge",
                        child.extinct? && "arkea-phylogeny__edge--extinct"
                      ]}
                      fill="none"
                    >
                      <title>{edge_title(child, edge)}</title>
                    </path>
                <% end %>
              <% end %>
            </g>

            <%!-- Nodes --%>
            <g class="arkea-phylogeny__nodes">
              <%= for node <- @model.nodes do %>
                <% nx = @x_scale.(node.x) %>
                <% ny = @y_scale.(node.y) %>
                <g class={[
                  "arkea-phylogeny__node",
                  node.leaf? && "arkea-phylogeny__node--leaf",
                  not node.leaf? && "arkea-phylogeny__node--internal",
                  node.extinct? && "arkea-phylogeny__node--extinct"
                ]}>
                  <circle
                    cx={fmt(nx)}
                    cy={fmt(ny)}
                    r={node_radius(node)}
                    fill={node_color(node)}
                    stroke={if node.extinct?, do: "rgba(148,163,184,0.6)", else: "rgba(15,23,42,0.6)"}
                    stroke-width="1.2"
                    stroke-dasharray={if node.extinct?, do: "2 2", else: nil}
                  >
                    <title>{node_title(node)}</title>
                  </circle>
                  <text
                    :if={node.leaf?}
                    x={fmt(nx + node_radius(node) + 5)}
                    y={fmt(ny + 4)}
                    text-anchor="start"
                    class="arkea-phylogeny__node-label"
                  >
                    {short_id(node.id)}
                  </text>
                </g>
              <% end %>
            </g>
          </svg>
      <% end %>
    </div>
    """
  end

  attr :model, :map, required: true
  attr :class, :string, default: nil

  @doc """
  Convenience wrapper that takes the same `Phylogeny` model and uses
  the default 720x360 viewport. Used by SimLive's Phylogeny tab.
  """
  def phylogeny_default(assigns) do
    ~H"""
    <.phylogeny model={@model} class={@class} />
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers

  defp node_color(%{extinct?: true}), do: "rgba(148, 163, 184, 0.55)"

  defp node_color(%{abundance: abundance}) when is_integer(abundance) and abundance > 0 do
    # Map abundance into a teal→cyan→magenta hue range so dominant
    # lineages (high abundance) stand out from low-abundance survivors.
    hue =
      cond do
        abundance > 5_000 -> 320
        abundance > 1_000 -> 280
        abundance > 200 -> 200
        abundance > 50 -> 170
        true -> 140
      end

    "hsl(#{hue}, 65%, 60%)"
  end

  defp node_color(_), do: "rgba(148, 163, 184, 0.55)"

  defp node_title(node) do
    abundance =
      cond do
        node.extinct? -> "extinct"
        node.abundance == 0 -> "abundance 0"
        true -> "N=#{node.abundance}"
      end

    role = if node.leaf?, do: "leaf", else: "internal"

    "Lineage #{short_id(node.id)} · #{role} · depth #{node.depth} · " <>
      "#{abundance} · genes #{node.gene_count}"
  end

  defp edge_title(child, edge) do
    parts = [
      "p-distance #{format_distance(child.branch_length)}",
      "child #{short_id(child.id)}"
    ]

    summary_part =
      case edge.mutation_summary do
        %{} = s ->
          [
            "Δµ #{format_signed(s["d_growth_rate"])}",
            "Δrepair #{format_signed(s["d_repair"])}",
            "ΔE #{format_signed(s["d_energy_cost"])}"
          ]

        _ ->
          []
      end

    Enum.join(parts ++ summary_part, " · ")
  end

  defp node_radius(%{leaf?: true}), do: 6
  defp node_radius(_), do: 3

  defp format_distance(d) when is_number(d) do
    :erlang.float_to_binary(d * 1.0, decimals: 4)
  end

  defp format_distance(_), do: "—"

  defp format_signed(nil), do: "—"
  defp format_signed(n) when is_integer(n), do: format_signed(n * 1.0)

  defp format_signed(n) when is_float(n) do
    sign = if n >= 0, do: "+", else: ""
    "#{sign}#{:erlang.float_to_binary(n, decimals: 2)}"
  end

  defp short_id(nil), do: ""
  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)

  defp fmt(value) when is_integer(value), do: Integer.to_string(value)

  defp fmt(value) when is_float(value) do
    case Float.round(value, 2) do
      n when n == trunc(n) -> Integer.to_string(trunc(n))
      n -> Float.to_string(n)
    end
  end
end
