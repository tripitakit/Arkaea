defmodule ArkeaWeb.WorldLive do
  @moduledoc """
  Macroscala world overview for active player-controlled biotopes.
  """

  use ArkeaWeb, :live_view

  alias Arkea.Game.SeedLab
  alias Arkea.Game.World
  alias ArkeaWeb.GameChrome

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if Phoenix.LiveView.connected?(socket) do
      Phoenix.PubSub.subscribe(Arkea.PubSub, "world:tick")
      Phoenix.PubSub.subscribe(Arkea.PubSub, "world:registry")
    end

    {:ok, refresh(socket)}
  end

  @impl Phoenix.LiveView
  def handle_info({:tick, _tick_number}, socket), do: {:noreply, refresh(socket)}
  def handle_info({:world_changed, _biotope_id}, socket), do: {:noreply, refresh(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="sim-shell" data-view="world">
      <div class="sim-shell__grid"></div>
      <div class="sim-shell__content">
        <GameChrome.top_nav active={:world} player_name={@player.display_name} />

        <section class="sim-hero world-hero mt-6">
          <div>
            <div class="sim-hero__eyebrow">Arkea prototype · world shell</div>
            <h1 class="sim-hero__title">Shared world overview</h1>
            <p class="sim-hero__copy">
              Macroscala summary of active biotopes. Realtime evolution still lives inside each authoritative `Biotope.Server`; this page reads only lightweight runtime summaries.
            </p>
          </div>

          <div class="sim-stat-strip">
            <.stat_chip label="active" value={@overview.active_count} tone="gold" />
            <.stat_chip label="owned" value={@overview.owned_count} tone="teal" />
            <.stat_chip label="wild" value={@overview.wild_count} tone="sky" />
            <.stat_chip label="archetypes" value={length(@overview.archetype_breakdown)} tone="amber" />
            <.stat_chip label="edges" value={@overview.edge_count} tone="slate" />
            <.stat_chip label="tick" value={@overview.max_tick} tone="slate" />
          </div>
        </section>

        <div class="sim-main-grid mt-6">
          <section class="sim-card world-map-card">
            <div class="sim-card__header">
              <div>
                <div class="sim-card__eyebrow">World graph</div>
                <h2 class="sim-card__title">Biotope network</h2>
              </div>
              <div class="sim-card__meta">
                <%= if @overview.focus_biotope_id do %>
                  demo focus {short_id(@overview.focus_biotope_id)}
                <% else %>
                  waiting for runtime nodes
                <% end %>
              </div>
            </div>

            <%= if @overview.biotopes == [] do %>
              <p class="sim-muted">
                No active biotopes are currently registered. Provision a starter home from the seed lab to populate the world shell.
              </p>
            <% else %>
              <div class="world-map">
                <svg class="world-map__edges" viewBox="0 0 100 100" preserveAspectRatio="none">
                  <line
                    :for={edge <- @overview.edges}
                    class="world-map__edge"
                    x1={edge.x1}
                    y1={edge.y1}
                    x2={edge.x2}
                    y2={edge.y2}
                  />
                </svg>

                <.link
                  :for={biotope <- @overview.biotopes}
                  href={~p"/biotopes/#{biotope.id}"}
                  class={[
                    "world-node",
                    "world-node--#{ownership_tone(biotope.ownership)}",
                    biotope.is_demo && "world-node--demo"
                  ]}
                  style={"left: #{biotope.display_x}%; top: #{biotope.display_y}%; --node-accent: #{archetype_color(biotope.archetype)};"}
                >
                  <span class="world-node__title">{archetype_label(biotope.archetype)}</span>
                  <span class="world-node__meta">
                    {zone_label(biotope.zone)} · N {format_population(biotope.total_population)}
                  </span>
                </.link>
              </div>
            <% end %>

            <div class="sim-scene-note">
              The world shell does not subscribe to every biotope channel. It refreshes on the global tick barrier and on explicit world-graph changes.
            </div>
          </section>

          <div class="sim-sidebar">
            <section class="sim-card">
              <div class="sim-card__header">
                <div>
                  <div class="sim-card__eyebrow">Operator</div>
                  <h2 class="sim-card__title">{@player.display_name}</h2>
                </div>
                <div class="sim-card__meta">
                  <%= if @overview.owned_count > 0 do %>
                    {pluralize(@overview.owned_count, "biotope")} owned
                  <% else %>
                    no home yet
                  <% end %>
                </div>
              </div>

              <div class="world-cta-stack">
                <.link href={~p"/seed-lab"} class="sim-action-button sim-action-button--wide">
                  <%= if @overview.owned_count > 0 do %>
                    Open seed lab
                  <% else %>
                    Provision starter home
                  <% end %>
                </.link>

                <.link
                  :if={@overview.focus_biotope_id}
                  href={~p"/biotopes/#{@overview.focus_biotope_id}"}
                  class="sim-action-button sim-action-button--wide"
                >
                  Inspect active biotope
                </.link>
              </div>

              <%= if @overview.archetype_breakdown != [] do %>
                <div class="mt-4">
                  <div class="sim-card__eyebrow mb-2">Archetype distribution</div>
                  <div style="display: flex; height: 0.5rem; border-radius: 999px; overflow: hidden; gap: 2px;">
                    <div
                      :for={{archetype, count} <- @overview.archetype_breakdown}
                      style={"flex: #{count}; background: #{archetype_color(archetype)}; min-width: 4px;"}
                      title={"#{archetype_label(archetype)}: #{count}"}
                    >
                    </div>
                  </div>
                  <div class="sim-token-cloud mt-2">
                    <span
                      :for={{archetype, count} <- @overview.archetype_breakdown}
                      class="sim-token sim-token--ghost"
                      style={"border-left: 3px solid #{archetype_color(archetype)}; border-radius: 0 999px 999px 0; padding-left: 0.5rem;"}
                    >
                      <span class="sim-token__label" style="font-size: 0.68rem;">
                        {archetype_label(archetype)}
                      </span>
                      <span class="sim-token__value">{count}</span>
                    </span>
                  </div>
                </div>
              <% end %>
            </section>
          </div>
        </div>

        <section class="sim-card sim-card--wide mt-6">
          <div class="sim-card__header">
            <div>
              <div class="sim-card__eyebrow">World table</div>
              <h2 class="sim-card__title">Active ecotype inventory</h2>
            </div>
            <div class="sim-card__meta">
              {length(@overview.archetype_breakdown)} archetype classes
            </div>
          </div>

          <div class="overflow-x-auto">
            <table class="sim-table">
              <thead>
                <tr>
                  <th>Biotope</th>
                  <th>Status</th>
                  <th>Zone</th>
                  <th>N (total)</th>
                  <th>Tick</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <%= if @overview.biotopes == [] do %>
                  <tr>
                    <td colspan="6" class="sim-table__empty">No active biotopes.</td>
                  </tr>
                <% else %>
                  <tr :for={biotope <- @overview.biotopes}>
                    <td>
                      <div style="display: flex; align-items: center; gap: 0.5rem;">
                        <span style={"display: inline-block; width: 3px; height: 2rem; border-radius: 999px; background: #{archetype_color(biotope.archetype)}; flex-shrink: 0;"}>
                        </span>
                        <div>
                          <div class="world-table__title">{archetype_label(biotope.archetype)}</div>
                          <div class="sim-lineage-id__sub">{short_id(biotope.id)}</div>
                        </div>
                      </div>
                    </td>
                    <td>
                      <span class={[
                        "world-status-pill",
                        "world-status-pill--#{ownership_tone(biotope.ownership)}"
                      ]}>
                        {ownership_label(biotope.ownership)}
                      </span>
                    </td>
                    <td style="color: var(--sim-muted); font-size: var(--text-sm);">
                      {zone_label(biotope.zone)}
                    </td>
                    <td style="font-variant-numeric: tabular-nums;">
                      {format_population(biotope.total_population)}
                    </td>
                    <td style="font-variant-numeric: tabular-nums; color: var(--sim-muted);">
                      {biotope.tick_count}
                    </td>
                    <td>
                      <.link href={~p"/biotopes/#{biotope.id}"} class="world-table__link">
                        <span class="hero-arrow-top-right-on-square w-4 h-4"></span>
                      </.link>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </div>
    """
  end

  defp refresh(socket) do
    player = socket.assigns.current_player

    assign(socket,
      overview: World.overview(player.id),
      starter_ecotypes: SeedLab.starter_ecotypes(),
      player: player,
      page_title: "Arkea World"
    )
  end

  defp stat_chip(assigns) do
    ~H"""
    <div class={["sim-stat-chip", "sim-stat-chip--#{@tone}"]}>
      <span class="sim-stat-chip__label">{@label}</span>
      <span class="sim-stat-chip__value">{@value}</span>
    </div>
    """
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

  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)

  defp format_population(population) when population >= 1_000_000 do
    "#{Float.round(population / 1_000_000, 1)}M"
  end

  defp format_population(population) when population >= 1_000 do
    "#{Float.round(population / 1_000, 1)}k"
  end

  defp format_population(population), do: to_string(population)

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
end
