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
  alias Arkea.Views.PhenotypeDistribution
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

  attr :model, :map,
    required: true,
    doc: "PopulationTrajectory.trait_t() built by Arkea.Views.PopulationTrajectory.build_trait/3"

  attr :class, :string, default: nil
  attr :height, :integer, default: @viewport_h

  @doc """
  Render an overlaid-line chart of per-lineage trait values over time
  (Phase 21 Top 5 #4 — trait tracker). Same layout primitives as
  `population_trajectory/1` but the Y axis is a continuous float
  domain derived from `model.value_domain`.
  """
  def trait_trajectory(assigns) do
    %{model: model} = assigns

    {min_t, max_t} = model.tick_domain
    {min_y, max_y} = padded_value_domain(model.value_domain)

    inner_w = @viewport_w - @padding_left - @padding_right
    inner_h = assigns.height - @padding_top - @padding_bottom

    x_scale =
      ChartLib.linear_scale({min_t, max_t}, {@padding_left, @padding_left + inner_w})

    y_scale =
      ChartLib.linear_scale({min_y, max_y}, {@padding_top + inner_h, @padding_top})

    lineage_paths =
      Enum.map(model.lineages, fn series ->
        %{
          id: series.id,
          max: series.max,
          path: ChartLib.path_for_series(series.points, x_scale, y_scale),
          color: lineage_color(series.id)
        }
      end)

    x_ticks = ChartLib.axis_ticks(min_t, max_t, target: 6)
    y_ticks = ChartLib.axis_ticks(min_y, max_y, target: 5)

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
      |> assign(:markers, model.markers)
      |> assign(:trait, model.trait)

    ~H"""
    <div class={["arkea-chart", @class]}>
      <%= cond do %>
        <% not @has_data? -> %>
          <div class="arkea-chart__empty">
            No phenotype-trait samples yet — trait trajectory will populate as
            the simulation accumulates ticks (every {Arkea.Persistence.TimeSeries.cell_sampling_period()} ticks).
          </div>
        <% true -> %>
          <svg
            class="arkea-chart__svg"
            viewBox={"0 0 #{@width} #{@height}"}
            preserveAspectRatio="none"
            role="img"
            aria-label={"Phenotype trait '#{@trait}' over time per lineage"}
          >
            <rect
              x={@padding_left}
              y={@padding_top}
              width={@width - @padding_left - 12}
              height={@inner_h}
              class="arkea-chart__panel"
            />

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
                  {format_trait_value(t)}
                </text>
              <% end %>
            </g>

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
                <title>Lineage {short_id(line.id)} · max {format_trait_value(line.max)}</title>
              </path>
            <% end %>

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
      <% end %>
    </div>
    """
  end

  attr :samples, :list, default: []
  attr :audit, :list, default: []
  attr :trait, :string, required: true
  attr :class, :string, default: nil

  @doc """
  Convenience wrapper that builds a trait trajectory model and renders it.
  """
  def trait_trajectory_from_samples(assigns) do
    model = PopulationTrajectory.build_trait(assigns.samples, assigns.audit, assigns.trait)
    assigns = assign(assigns, :model, model)

    ~H"""
    <.trait_trajectory model={@model} class={@class} />
    """
  end

  attr :model, :map,
    required: true,
    doc: "PhenotypeDistribution.t() built by Arkea.Views.PhenotypeDistribution.build/3"

  attr :class, :string, default: nil
  attr :height, :integer, default: 220

  @doc """
  Render a per-lineage strip plot of the population's distribution
  on a phenotype trait at the latest sampled tick (Phase 22 / 2.8).

  Each lineage is a circle: x = trait value, y = abundance, radius
  ∝ √abundance. A vertical reference line marks the abundance-
  weighted mean (centre of mass). Two visible clusters on the x-axis
  flag incipient speciation / polarisation; a single tight cluster
  with a small vertical spread = stable population.
  """
  def phenotype_distribution(assigns) do
    %{model: model} = assigns

    {min_x, max_x} = padded_value_domain(model.x_domain)
    {_min_y, max_y} = model.y_domain

    inner_w = @viewport_w - @padding_left - @padding_right
    inner_h = assigns.height - @padding_top - @padding_bottom

    x_scale =
      ChartLib.linear_scale({min_x, max_x}, {@padding_left, @padding_left + inner_w})

    y_scale =
      ChartLib.linear_scale({0, max(max_y, 1)}, {@padding_top + inner_h, @padding_top})

    # Radius scale: the largest lineage gets a 14px circle; smaller
    # lineages scale down by √abundance share. The view emits raw √
    # in `point.radius`; here we map to pixel space.
    max_radius_raw = model.points |> Enum.map(& &1.radius) |> Enum.max(fn -> 1.0 end)
    px_radius = fn r -> max(2.0, r / max_radius_raw * 14.0) end

    points =
      Enum.map(model.points, fn p ->
        %{
          id: p.id,
          cx: x_scale.(p.x),
          cy: y_scale.(p.y),
          r: px_radius.(p.radius),
          x: p.x,
          y: p.y,
          color: lineage_color(p.id)
        }
      end)

    x_ticks = ChartLib.axis_ticks(min_x, max_x, target: 5)
    y_ticks = ChartLib.axis_ticks(0, max_y, target: 4)

    has_data? = points != [] and max_x > min_x

    mean_x =
      case model.weighted_mean do
        nil -> nil
        m -> x_scale.(m)
      end

    assigns =
      assigns
      |> assign(:has_data?, has_data?)
      |> assign(:points, points)
      |> assign(:x_scale, x_scale)
      |> assign(:y_scale, y_scale)
      |> assign(:x_ticks, x_ticks)
      |> assign(:y_ticks, y_ticks)
      |> assign(:width, @viewport_w)
      |> assign(:padding_left, @padding_left)
      |> assign(:padding_top, @padding_top)
      |> assign(:padding_bottom, @padding_bottom)
      |> assign(:inner_h, inner_h)
      |> assign(:trait, model.trait)
      |> assign(:tick, model.tick)
      |> assign(:weighted_mean, model.weighted_mean)
      |> assign(:mean_x, mean_x)
      |> assign(:total_abundance, model.total_abundance)

    ~H"""
    <div class={["arkea-chart arkea-chart--distribution", @class]}>
      <%= cond do %>
        <% not @has_data? -> %>
          <div class="arkea-chart__empty">
            No phenotype-trait samples for trait <code>{@trait}</code>
            yet — distribution will populate once
            the cellular sampling boundary fires.
          </div>
        <% true -> %>
          <svg
            class="arkea-chart__svg"
            viewBox={"0 0 #{@width} #{@height}"}
            preserveAspectRatio="none"
            role="img"
            aria-label={"Distribution of '#{@trait}' across lineages at tick #{@tick}"}
          >
            <rect
              x={@padding_left}
              y={@padding_top}
              width={@width - @padding_left - 12}
              height={@inner_h}
              class="arkea-chart__panel"
            />

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

            <g class="arkea-chart__axis arkea-chart__axis--x">
              <%= for t <- @x_ticks do %>
                <text
                  x={@x_scale.(t)}
                  y={@height - 8}
                  text-anchor="middle"
                  class="arkea-chart__tick-label"
                >
                  {format_trait_value(t)}
                </text>
              <% end %>
            </g>

            <%!-- Lineage markers --%>
            <g class="arkea-chart__points">
              <%= for p <- @points do %>
                <circle
                  cx={p.cx}
                  cy={p.cy}
                  r={p.r}
                  fill={p.color}
                  fill-opacity="0.55"
                  stroke={p.color}
                  stroke-width="1"
                >
                  <title>
                    Lineage {short_id(p.id)} · {@trait}={format_trait_value(p.x)} · N={p.y}
                  </title>
                </circle>
              <% end %>
            </g>

            <%!-- Centre-of-mass reference line + label --%>
            <%= if @mean_x do %>
              <g class="arkea-chart__mean">
                <line
                  x1={@mean_x}
                  x2={@mean_x}
                  y1={@padding_top}
                  y2={@height - @padding_bottom}
                  class="arkea-chart__mean-line"
                  stroke-dasharray="4 3"
                />
                <text
                  x={@mean_x + 4}
                  y={@padding_top + 12}
                  class="arkea-chart__mean-label"
                >
                  μ̄ = {format_trait_value(@weighted_mean)}
                </text>
              </g>
            <% end %>

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
      <% end %>
    </div>
    """
  end

  attr :samples, :list, default: []
  attr :abundances, :map, default: %{}
  attr :trait, :string, required: true
  attr :class, :string, default: nil

  @doc """
  Convenience wrapper that builds a phenotype-distribution model and
  renders it.
  """
  def phenotype_distribution_from_samples(assigns) do
    model = PhenotypeDistribution.build(assigns.samples, assigns.trait, assigns.abundances)
    assigns = assign(assigns, :model, model)

    ~H"""
    <.phenotype_distribution model={@model} class={@class} />
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

  defp format_trait_value(n) when is_integer(n), do: Integer.to_string(n)
  defp format_trait_value(n) when is_float(n), do: Float.to_string(Float.round(n, 3))
  defp format_trait_value(_), do: ""

  # Pad the value domain for trait charts so lines never sit flush with
  # the panel edge. A degenerate domain (`{x, x}` — single sample, or a
  # constant trait) becomes `{x - 1, x + 1}` so the chart still draws.
  defp padded_value_domain({lo, hi}) when is_number(lo) and is_number(hi) do
    cond do
      lo == hi and lo == 0.0 -> {0.0, 1.0}
      lo == hi -> {lo - abs(lo) * 0.1 - 0.001, hi + abs(hi) * 0.1 + 0.001}
      true -> {lo - (hi - lo) * 0.05, hi + (hi - lo) * 0.05}
    end
  end

  defp padded_value_domain(_), do: {0.0, 1.0}

  defp short_id(nil), do: ""
  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)
end
