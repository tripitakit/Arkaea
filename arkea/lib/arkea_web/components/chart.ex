defmodule ArkeaWeb.Components.Chart do
  @moduledoc """
  Phoenix function components built on top of the pure `Arkea.Views.Chart`
  module. UI Phase C ships:

  - `<Chart.population_trajectory>` — overlaid line plot of per-lineage
    abundance over time, with vertical event markers from the audit log.

  Future phases (D/E) will add `<Chart.heatmap>`, `<Chart.sankey>` and
  `<Chart.brushable_axis>` over the same primitive layer.
  """
  use Phoenix.Component

  alias Arkea.Views.Chart, as: ChartLib
  alias Arkea.Views.PopulationTrajectory

  @viewport_w 800
  @viewport_h 280
  @padding_left 56
  @padding_right 12
  @padding_top 12
  @padding_bottom 28

  attr :model, :map,
    required: true,
    doc: "PopulationTrajectory.t() built by Arkea.Views.PopulationTrajectory.build/2"

  attr :class, :string, default: nil
  attr :height, :integer, default: @viewport_h

  @doc """
  Render an overlaid-line chart of per-lineage abundance over time.

  When the model carries no points, renders a centred "No samples yet"
  placeholder so the slot doesn't collapse to 0px.
  """
  def population_trajectory(assigns) do
    %{model: model} = assigns

    {min_t, max_t} = model.tick_domain
    {_min_y, max_y} = model.population_domain

    inner_w = @viewport_w - @padding_left - @padding_right
    inner_h = assigns.height - @padding_top - @padding_bottom

    x_scale =
      ChartLib.linear_scale({min_t, max_t}, {@padding_left, @padding_left + inner_w})

    # SVG y axis is flipped: high values render near the top.
    y_scale =
      ChartLib.linear_scale({0, max(max_y, 1)}, {@padding_top + inner_h, @padding_top})

    lineage_paths =
      Enum.map(model.lineages, fn series ->
        %{
          id: series.id,
          peak: series.peak,
          path: ChartLib.path_for_series(series.points, x_scale, y_scale),
          color: lineage_color(series.id)
        }
      end)

    x_ticks = ChartLib.axis_ticks(min_t, max_t, target: 6)
    y_ticks = ChartLib.axis_ticks(0, max_y, target: 5)

    has_data? = lineage_paths != [] and max_t > min_t

    assigns =
      assigns
      |> assign(:has_data?, has_data?)
      |> assign(:lineage_paths, lineage_paths)
      |> assign(:x_scale, x_scale)
      |> assign(:y_scale, y_scale)
      |> assign(:x_ticks, x_ticks)
      |> assign(:y_ticks, y_ticks)
      |> assign(:width, @viewport_w)
      |> assign(:padding_left, @padding_left)
      |> assign(:padding_top, @padding_top)
      |> assign(:padding_bottom, @padding_bottom)
      |> assign(:inner_h, inner_h)
      |> assign(:tick_domain, model.tick_domain)
      |> assign(:population_domain, model.population_domain)
      |> assign(:markers, model.markers)

    ~H"""
    <div class={["arkea-chart", @class]}>
      <%= cond do %>
        <% not @has_data? -> %>
          <div class="arkea-chart__empty">
            No abundance samples yet — population trajectory will populate as
            the simulation accumulates ticks (every {Arkea.Persistence.TimeSeries.sampling_period()} ticks).
          </div>
        <% true -> %>
          <svg
            class="arkea-chart__svg"
            viewBox={"0 0 #{@width} #{@height}"}
            preserveAspectRatio="none"
            role="img"
            aria-label="Population abundance over time per lineage"
          >
            <%!-- Background panel --%>
            <rect
              x={@padding_left}
              y={@padding_top}
              width={@width - @padding_left - 12}
              height={@inner_h}
              class="arkea-chart__panel"
            />

            <%!-- Y-axis grid + labels --%>
            <g class="arkea-chart__axis arkea-chart__axis--y">
              <%= for t <- @y_ticks do %>
                <line
                  x1={@padding_left}
                  x2={@width - 12}
                  y1={@y_scale.(t)}
                  y2={@y_scale.(t)}
                  class="arkea-chart__grid-line"
                />
                <text
                  x={@padding_left - 6}
                  y={@y_scale.(t) + 4}
                  text-anchor="end"
                  class="arkea-chart__tick-label"
                >
                  {format_count(t)}
                </text>
              <% end %>
            </g>

            <%!-- X-axis labels --%>
            <g class="arkea-chart__axis arkea-chart__axis--x">
              <%= for t <- @x_ticks do %>
                <text
                  x={@x_scale.(t)}
                  y={@height - 8}
                  text-anchor="middle"
                  class="arkea-chart__tick-label"
                >
                  {round(t)}
                </text>
              <% end %>
            </g>

            <%!-- Lineage trajectories --%>
            <%= for line <- @lineage_paths do %>
              <path
                d={line.path}
                fill="none"
                stroke={line.color}
                stroke-width="1.5"
                stroke-linejoin="round"
                stroke-linecap="round"
                opacity="0.85"
              >
                <title>Lineage {short_id(line.id)} · peak {line.peak}</title>
              </path>
            <% end %>

            <%!-- Event markers --%>
            <g class="arkea-chart__markers">
              <%= for marker <- @markers do %>
                <line
                  x1={@x_scale.(marker.tick)}
                  x2={@x_scale.(marker.tick)}
                  y1={@padding_top}
                  y2={@height - @padding_bottom}
                  class={"arkea-chart__marker arkea-chart__marker--#{marker.type}"}
                  stroke-dasharray={marker_dash(marker.type)}
                >
                  <title>{marker.type} @ tick {marker.tick}</title>
                </line>
              <% end %>
            </g>

            <%!-- Axis lines --%>
            <line
              x1={@padding_left}
              x2={@padding_left}
              y1={@padding_top}
              y2={@height - @padding_bottom}
              class="arkea-chart__axis-line"
            />
            <line
              x1={@padding_left}
              x2={@width - 12}
              y1={@height - @padding_bottom}
              y2={@height - @padding_bottom}
              class="arkea-chart__axis-line"
            />
          </svg>

          <div class="arkea-chart__legend">
            <span :for={line <- @lineage_paths} class="arkea-chart__legend-item">
              <span class="arkea-chart__legend-swatch" style={"background: #{line.color}"} />
              <span>{short_id(line.id)}</span>
              <span class="arkea-chart__legend-peak">{format_count(line.peak)}</span>
            </span>
          </div>
      <% end %>
    </div>
    """
  end

  attr :samples, :list, default: []
  attr :audit, :list, default: []
  attr :class, :string, default: nil

  @doc """
  Convenience wrapper that builds a `PopulationTrajectory` view-model
  from the raw sample/audit lists and renders it.
  """
  def population_trajectory_from_samples(assigns) do
    model = PopulationTrajectory.build(assigns.samples, assigns.audit)
    assigns = assign(assigns, :model, model)

    ~H"""
    <.population_trajectory model={@model} class={@class} />
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers

  # Deterministic lineage colour: hash the id into the HSL hue space so
  # the same lineage gets the same colour across renders.
  defp lineage_color(id) when is_binary(id) do
    h = :erlang.phash2(id, 360)
    "hsl(#{h}, 65%, 60%)"
  end

  defp lineage_color(_), do: "#67e8f9"

  defp marker_dash("intervention"), do: "4 3"
  defp marker_dash("mass_lysis"), do: "2 2"
  defp marker_dash("mutation_notable"), do: "6 2"
  defp marker_dash("phage_burst"), do: "1 3"
  defp marker_dash("colonization"), do: "5 1 1 1"
  defp marker_dash(_), do: "3 3"

  defp format_count(n) when is_integer(n) and n >= 10_000,
    do: "#{Float.round(n / 1000, 1)}k"

  defp format_count(n) when is_integer(n), do: Integer.to_string(n)
  defp format_count(n) when is_float(n), do: format_count(round(n))

  defp short_id(nil), do: ""
  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)
end
