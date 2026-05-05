defmodule ArkeaWeb.WorldLive do
  @moduledoc """
  Macroscala world overview (UI rewrite — phase U2).

  Layout: shell + main split into a full-bleed SVG graph (left) and a
  contextual side panel (right, 320 px). The page never grows a global
  scrollbar — the side panel scrolls only when its body overflows. Pan/zoom
  on the SVG ships with phase U3 (SvgPanZoom hook); for now the graph is a
  static viewBox sized to the available space.
  """

  use ArkeaWeb, :live_view

  alias Arkea.Game.World
  alias ArkeaWeb.Components.Metric
  alias ArkeaWeb.Components.Panel
  alias ArkeaWeb.Components.Shell

  @filters [:all, :mine, :wild]

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if Phoenix.LiveView.connected?(socket) do
      Phoenix.PubSub.subscribe(Arkea.PubSub, "world:tick")
      Phoenix.PubSub.subscribe(Arkea.PubSub, "world:registry")
    end

    {:ok,
     socket
     |> assign(filter: :all, selected_id: nil)
     |> refresh()}
  end

  @impl Phoenix.LiveView
  def handle_info({:tick, _tick}, socket), do: {:noreply, refresh(socket)}
  def handle_info({:world_changed, _id}, socket), do: {:noreply, refresh(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def handle_event("filter", %{"to" => to}, socket) do
    f = parse_filter(to)
    {:noreply, assign(socket, filter: f) |> reconcile_selection()}
  end

  def handle_event("select_biotope", %{"id" => id}, socket) do
    selected =
      cond do
        socket.assigns.selected_id == id -> nil
        Enum.any?(socket.assigns.overview.biotopes, &(&1.id == id)) -> id
        true -> nil
      end

    {:noreply, assign(socket, selected_id: selected)}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, selected_id: nil)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    visible = filter_biotopes(assigns.overview.biotopes, assigns.filter)
    selected = Enum.find(assigns.overview.biotopes, &(&1.id == assigns.selected_id))
    assigns = assign(assigns, visible: visible, selected: selected)

    ~H"""
    <Shell.shell sidebar?={false}>
      <:header>
        <Shell.shell_brand>Arkea</Shell.shell_brand>
        <Shell.shell_nav items={nav_items()} />
        <div class="arkea-shell__spacer"></div>
        <Shell.shell_user name={@player.display_name} logout_href={~p"/players/log-out"} />
      </:header>

      <div class="arkea-world">
        <section class="arkea-world__graph">
          <header class="arkea-world__toolbar">
            <div class="arkea-tablist" role="tablist" aria-label="World filter">
              <button
                :for={f <- @filters}
                type="button"
                role="tab"
                phx-click="filter"
                phx-value-to={Atom.to_string(f)}
                aria-selected={@filter == f}
                class="arkea-tab"
              >
                {filter_label(f)}
              </button>
            </div>

            <Metric.metric_strip class="arkea-world__chips">
              <Metric.metric_chip label="active" value={@overview.active_count} tone="gold" />
              <Metric.metric_chip label="owned" value={@overview.owned_count} tone="teal" />
              <Metric.metric_chip label="wild" value={@overview.wild_count} tone="sky" />
              <Metric.metric_chip
                label="archetypes"
                value={length(@overview.archetype_breakdown)}
                tone="signal"
              />
              <Metric.metric_chip label="tick" value={@overview.max_tick} tone="muted" />
            </Metric.metric_strip>
          </header>

          <div class="arkea-world__canvas">
            <%= if @overview.biotopes == [] do %>
              <div class="arkea-world__empty">
                <h2>No active biotopes</h2>
                <p>
                  Provision a starter home from the
                  <.link navigate={~p"/seed-lab"} class="arkea-link">Seed Lab</.link>
                  to populate the world.
                </p>
              </div>
            <% else %>
              <svg
                class="arkea-world__svg"
                viewBox="0 0 100 100"
                preserveAspectRatio="xMidYMid meet"
                role="img"
                aria-label="Biotope network graph"
              >
                <g class="arkea-world__edges">
                  <line
                    :for={edge <- visible_edges(@overview.edges, @visible)}
                    class="arkea-world__edge"
                    x1={edge.x1}
                    y1={edge.y1}
                    x2={edge.x2}
                    y2={edge.y2}
                  />
                </g>

                <g class="arkea-world__nodes">
                  <g
                    :for={b <- @visible}
                    class={[
                      "arkea-world__node",
                      "arkea-world__node--#{ownership_tone(b.ownership)}",
                      @selected_id == b.id && "arkea-world__node--selected"
                    ]}
                    transform={"translate(#{b.display_x} #{b.display_y})"}
                    phx-click="select_biotope"
                    phx-value-id={b.id}
                    style={"--arkea-node-accent: #{archetype_color(b.archetype)};"}
                    tabindex="0"
                    role="button"
                    aria-label={"#{archetype_label(b.archetype)} #{short_id(b.id)}"}
                  >
                    <circle r={node_radius(b)} class="arkea-world__node-halo" />
                    <circle r={node_radius(b) * 0.55} class="arkea-world__node-core" />
                    <text
                      class="arkea-world__node-count"
                      text-anchor="middle"
                      dominant-baseline="central"
                    >
                      {b.lineage_count}
                    </text>
                    <text class="arkea-world__node-label" y={node_radius(b) + 2.5}>
                      {archetype_label(b.archetype)}
                    </text>
                  </g>
                </g>
              </svg>
            <% end %>

            <p
              :if={@overview.biotopes != [] and @visible == []}
              class="arkea-world__filter-empty"
            >
              No biotopes match the current filter.
            </p>
          </div>
        </section>

        <aside class="arkea-world__side">
          <.operator_panel player={@player} overview={@overview} />
          <.selected_panel selected={@selected} />
          <.archetype_panel breakdown={@overview.archetype_breakdown} />
        </aside>
      </div>
    </Shell.shell>
    """
  end

  # ---------------------------------------------------------------------------
  # Side panels

  attr :player, :map, required: true
  attr :overview, :map, required: true

  defp operator_panel(assigns) do
    ~H"""
    <Panel.panel>
      <:header
        eyebrow="Operator"
        title={@player.display_name}
        meta={
          if @overview.owned_count > 0,
            do: pluralize(@overview.owned_count, "biotope") <> " owned",
            else: "no home yet"
        }
      />
      <:body>
        <.arkea_button variant="primary" navigate={~p"/seed-lab"}>
          {if @overview.owned_count > 0, do: "Open Seed Lab", else: "Provision starter home"}
        </.arkea_button>

        <.arkea_button
          :if={@overview.focus_biotope_id}
          variant="secondary"
          navigate={~p"/biotopes/#{@overview.focus_biotope_id}"}
        >
          Inspect demo biotope
        </.arkea_button>
      </:body>
    </Panel.panel>
    """
  end

  attr :selected, :map, default: nil

  defp selected_panel(assigns) do
    ~H"""
    <Panel.panel>
      <:header
        eyebrow="Selected"
        title={if @selected, do: archetype_label(@selected.archetype), else: "Nothing selected"}
        meta={if @selected, do: short_id(@selected.id), else: nil}
      />
      <:body>
        <%= if @selected do %>
          <Metric.metric_strip>
            <Metric.metric_chip
              label="status"
              value={ownership_label(@selected.ownership)}
              tone={ownership_tone_metric(@selected.ownership)}
            />
            <Metric.metric_chip label="zone" value={zone_label(@selected.zone)} tone="muted" />
            <Metric.metric_chip label="tick" value={@selected.tick_count} tone="gold" />
            <Metric.metric_chip
              label="lineages"
              value={@selected.lineage_count}
              tone="metabolite"
            />
            <Metric.metric_chip
              label="N"
              value={format_population(@selected.total_population)}
              tone="growth"
            />
            <Metric.metric_chip
              label="phases"
              value={@selected.phase_count}
              tone="muted"
            />
          </Metric.metric_strip>

          <.arkea_button variant="primary" navigate={~p"/biotopes/#{@selected.id}"}>
            Open biotope
          </.arkea_button>
        <% else %>
          <Panel.empty_state>
            Click a node on the graph to inspect it.
          </Panel.empty_state>
        <% end %>
      </:body>
    </Panel.panel>
    """
  end

  attr :breakdown, :list, required: true

  defp archetype_panel(assigns) do
    total = Enum.reduce(assigns.breakdown, 0, fn entry, acc -> acc + entry.count end)
    assigns = assign(assigns, total: total)

    ~H"""
    <Panel.panel :if={@breakdown != []}>
      <:header eyebrow="Distribution" title="Archetypes" meta={"#{@total} nodes"} />
      <:body>
        <div class="arkea-world__archetype-bar">
          <div
            :for={entry <- @breakdown}
            class="arkea-world__archetype-segment"
            style={"flex: #{entry.count}; background: #{archetype_color(entry.archetype)};"}
            title={"#{archetype_label(entry.archetype)}: #{entry.count}"}
          />
        </div>
        <ul class="arkea-world__archetype-list">
          <li :for={entry <- @breakdown} class="arkea-world__archetype-item">
            <span
              class="arkea-world__archetype-swatch"
              style={"background: #{archetype_color(entry.archetype)};"}
              aria-hidden="true"
            />
            <span class="arkea-world__archetype-name">{archetype_label(entry.archetype)}</span>
            <span class="arkea-world__archetype-count">{entry.count}</span>
          </li>
        </ul>
      </:body>
    </Panel.panel>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers

  defp refresh(socket) do
    player = socket.assigns.current_player
    overview = World.overview(player.id)

    socket
    |> assign(
      player: player,
      overview: overview,
      filters: @filters,
      page_title: "Arkea World"
    )
    |> reconcile_selection()
  end

  defp reconcile_selection(socket) do
    selected_id = socket.assigns[:selected_id]

    keep? =
      selected_id != nil and
        Enum.any?(socket.assigns.overview.biotopes, &(&1.id == selected_id))

    if keep?, do: socket, else: assign(socket, selected_id: nil)
  end

  defp parse_filter(s) when is_binary(s) do
    case s do
      "mine" -> :mine
      "wild" -> :wild
      _ -> :all
    end
  end

  defp filter_label(:all), do: "All"
  defp filter_label(:mine), do: "Mine"
  defp filter_label(:wild), do: "Wild"

  defp filter_biotopes(biotopes, :all), do: biotopes

  defp filter_biotopes(biotopes, :mine),
    do: Enum.filter(biotopes, &(&1.ownership == :player_controlled))

  defp filter_biotopes(biotopes, :wild),
    do: Enum.filter(biotopes, &(&1.ownership == :wild))

  defp visible_edges(edges, visible_biotopes) do
    ids = MapSet.new(visible_biotopes, & &1.id)

    Enum.filter(edges, fn edge ->
      case String.split(Map.get(edge, :id, ""), ":", parts: 2) do
        [a, b] -> MapSet.member?(ids, a) and MapSet.member?(ids, b)
        _ -> true
      end
    end)
  end

  defp node_radius(%{total_population: pop, lineage_count: lc}) do
    base = 2.6
    pop_term = :math.log10(max(1, pop)) * 0.55
    lin_term = :math.log10(max(1, lc)) * 0.4
    Float.round(min(6.0, base + pop_term + lin_term), 2)
  end

  defp archetype_label(archetype) when is_atom(archetype) do
    archetype
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp zone_label(zone) when is_atom(zone) do
    zone
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp ownership_label(:player_controlled), do: "player home"
  defp ownership_label(:wild), do: "wild"
  defp ownership_label(:foreign_controlled), do: "foreign"

  defp ownership_tone(:player_controlled), do: "owned"
  defp ownership_tone(:wild), do: "wild"
  defp ownership_tone(:foreign_controlled), do: "foreign"

  defp ownership_tone_metric(:player_controlled), do: "growth"
  defp ownership_tone_metric(:wild), do: "sky"
  defp ownership_tone_metric(:foreign_controlled), do: "rust"

  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)
  defp short_id(_), do: ""

  defp format_population(p) when p >= 1_000_000, do: "#{Float.round(p / 1_000_000, 1)}M"
  defp format_population(p) when p >= 1_000, do: "#{Float.round(p / 1_000, 1)}k"
  defp format_population(p), do: to_string(p)

  defp archetype_color(:eutrophic_pond), do: "#f59e0b"
  defp archetype_color(:oligotrophic_lake), do: "#38bdf8"
  defp archetype_color(:mesophilic_soil), do: "#84cc16"
  defp archetype_color(:methanogenic_bog), do: "#10b981"
  defp archetype_color(:saline_estuary), do: "#22d3ee"
  defp archetype_color(:marine_sediment), do: "#fb7185"
  defp archetype_color(:hydrothermal_vent), do: "#f97316"
  defp archetype_color(:acid_mine_drainage), do: "#ef4444"
  defp archetype_color(_), do: "#94a3b8"

  defp pluralize(1, noun), do: "1 #{noun}"
  defp pluralize(n, noun), do: "#{n} #{noun}s"

  defp nav_items, do: Shell.nav_items(:world)
end
