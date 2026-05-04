defmodule ArkeaWeb.DashboardLive do
  @moduledoc """
  Post-login landing for the Arkea UI rewrite (phase U1).

  Six card-link panels summarising the player's footprint and the simulation
  surface area. Each panel opens a dedicated full-page view; the dashboard
  itself never grows scrollbars (a sub-panel may, only when needed).

  Three panels carry live data (`World`, `Seed Lab`, `My Biotopes`); the
  remaining three (`Community`, `Audit`, `Docs`) are placeholders pointing at
  later phases of the rewrite. Migration plan: UI-REWRITE-PLAN.md.
  """
  use ArkeaWeb, :live_view

  alias Arkea.Game.World
  alias ArkeaWeb.Components.Metric
  alias ArkeaWeb.Components.Panel
  alias ArkeaWeb.Components.Shell

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if Phoenix.LiveView.connected?(socket) do
      Phoenix.PubSub.subscribe(Arkea.PubSub, "world:tick")
      Phoenix.PubSub.subscribe(Arkea.PubSub, "world:registry")
    end

    {:ok, refresh(socket)}
  end

  @impl Phoenix.LiveView
  def handle_info({:tick, _tick}, socket), do: {:noreply, refresh(socket)}
  def handle_info({:world_changed, _id}, socket), do: {:noreply, refresh(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Shell.shell sidebar?={false}>
      <:header>
        <Shell.shell_brand>Arkea</Shell.shell_brand>
        <Shell.shell_nav items={nav_items()} />
        <div class="arkea-shell__spacer"></div>
        <Shell.shell_user name={@player.display_name} logout_href={~p"/players/log-out"} />
      </:header>

      <div class="arkea-dashboard arkea-scrollable">
        <header class="arkea-dashboard__heading">
          <span class="arkea-dashboard__eyebrow">Dashboard</span>
          <h1 class="arkea-dashboard__title">Welcome, {@player.display_name}.</h1>
          <p class="arkea-dashboard__copy">
            Six panels — three live, three coming online during the rewrite.
            Click a panel to open its full-page view.
          </p>
        </header>

        <div class="arkea-dashboard__grid">
          <.world_panel overview={@overview} />
          <.seed_lab_panel overview={@overview} />
          <.my_biotopes_panel overview={@overview} player={@player} />
          <.community_panel />
          <.audit_panel />
          <.docs_panel />
        </div>
      </div>
    </Shell.shell>
    """
  end

  # ---------------------------------------------------------------------------
  # Panels

  attr :overview, :map, required: true

  defp world_panel(assigns) do
    ~H"""
    <.link navigate={~p"/world"} class="arkea-dashboard__card-link" aria-label="Open world view">
      <Panel.panel class="arkea-dashboard__card">
        <:header eyebrow="World" title="Biotope network" meta={meta_for(@overview)} />
        <:body>
          <Metric.metric_strip>
            <Metric.metric_chip label="active" value={@overview.active_count} tone="gold" />
            <Metric.metric_chip label="owned" value={@overview.owned_count} tone="teal" />
            <Metric.metric_chip label="wild" value={@overview.wild_count} tone="sky" />
            <Metric.metric_chip
              label="archetypes"
              value={length(@overview.archetype_breakdown)}
              tone="signal"
            />
          </Metric.metric_strip>

          <div :if={@overview.active_count == 0} class="arkea-dashboard__hint">
            No biotopes yet. Provision one from the Seed Lab.
          </div>
        </:body>
      </Panel.panel>
    </.link>
    """
  end

  attr :overview, :map, required: true

  defp seed_lab_panel(assigns) do
    max_homes = Arkea.Game.SeedLab.max_homes()
    owned = assigns.overview.owned_count
    slots_open? = owned < max_homes
    assigns = assign(assigns, max_homes: max_homes, slots_open?: slots_open?)

    ~H"""
    <.link navigate={~p"/seed-lab"} class="arkea-dashboard__card-link" aria-label="Open seed lab">
      <Panel.panel class="arkea-dashboard__card">
        <:header
          eyebrow="Seed Lab"
          title="Founder design"
          meta={"#{@overview.owned_count}/#{@max_homes} homes"}
        />
        <:body>
          <p class="arkea-dashboard__copy">
            Visual genome editor: phenotype targets, gene composition, intergenic
            biases. Each player can claim up to {@max_homes} home biotopes —
            mix archetypes to diversify niches.
          </p>
          <div class="arkea-dashboard__cta">
            {if @slots_open?, do: "Design new home", else: "Inspect locked seed"}
          </div>
        </:body>
      </Panel.panel>
    </.link>
    """
  end

  attr :overview, :map, required: true
  attr :player, :map, required: true

  defp my_biotopes_panel(assigns) do
    owned =
      assigns.overview.biotopes
      |> Enum.filter(&(&1.ownership == :player_controlled))
      |> Enum.take(4)

    assigns = assign(assigns, owned: owned)

    ~H"""
    <Panel.panel class="arkea-dashboard__card arkea-dashboard__card--span-2">
      <:header
        eyebrow="My Biotopes"
        title="Owned runtime nodes"
        meta={"#{@overview.owned_count} owned"}
      />
      <:body scroll>
        <%= if @owned == [] do %>
          <Panel.empty_state title="No owned biotopes">
            Provision a starter home from the <.link navigate={~p"/seed-lab"} class="arkea-link">Seed Lab</.link>.
          </Panel.empty_state>
        <% else %>
          <ul class="arkea-biotope-list">
            <li :for={b <- @owned} class="arkea-biotope-list__item">
              <.link navigate={~p"/biotopes/#{b.id}"} class="arkea-biotope-list__link">
                <div class="arkea-biotope-list__main">
                  <span class="arkea-biotope-list__name">{archetype_label(b.archetype)}</span>
                  <span class="arkea-biotope-list__id">{short_id(b.id)}</span>
                </div>
                <div class="arkea-biotope-list__metrics">
                  <span class="arkea-biotope-list__metric">tick {b.tick_count}</span>
                  <span class="arkea-biotope-list__metric">{b.lineage_count} lineages</span>
                  <span class="arkea-biotope-list__metric">N {b.total_population}</span>
                </div>
              </.link>
            </li>
          </ul>
        <% end %>
      </:body>
    </Panel.panel>
    """
  end

  defp community_panel(assigns) do
    ~H"""
    <.link
      navigate={~p"/community"}
      class="arkea-dashboard__card-link"
      aria-label="Open community view"
    >
      <Panel.panel class="arkea-dashboard__card">
        <:header eyebrow="Community" title="Multi-seed runs" meta="read-only" />
        <:body>
          <p class="arkea-dashboard__copy">
            Browse biotopes that received a community-mode inoculation
            (BIOLOGICAL-MODEL-REVIEW.md Phase 19). Founder lists are
            reconstructed from persisted audit events.
          </p>
          <div class="arkea-dashboard__cta">Browse runs</div>
        </:body>
      </Panel.panel>
    </.link>
    """
  end

  defp audit_panel(assigns) do
    ~H"""
    <.link navigate={~p"/audit"} class="arkea-dashboard__card-link" aria-label="Open audit view">
      <Panel.panel class="arkea-dashboard__card">
        <:header eyebrow="Audit" title="Global event stream" meta="paginated" />
        <:body>
          <p class="arkea-dashboard__copy">
            Append-only typed event log: HGT, mutations, mass lysis,
            interventions, colonisation, mobile element release.
          </p>
          <div class="arkea-dashboard__cta">Open feed</div>
        </:body>
      </Panel.panel>
    </.link>
    """
  end

  defp docs_panel(assigns) do
    ~H"""
    <Panel.panel class="arkea-dashboard__card arkea-dashboard__card--soon">
      <:header eyebrow="Docs" title="Design & calibration" meta="phase U6" />
      <:body>
        <p class="arkea-dashboard__copy">
          In-app rendering of the canonical references coming online in U6:
        </p>
        <ul class="arkea-doc-list">
          <li>
            <span class="arkea-doc-list__name">DESIGN.md</span><span class="arkea-doc-list__hint">15 architectural blocks</span>
          </li>
          <li>
            <span class="arkea-doc-list__name">CALIBRATION.md</span><span class="arkea-doc-list__hint">parameter ↔ literature mapping</span>
          </li>
          <li>
            <span class="arkea-doc-list__name">BIOLOGICAL-MODEL-REVIEW.md</span><span class="arkea-doc-list__hint">phases 12–20 plan</span>
          </li>
          <li>
            <span class="arkea-doc-list__name">UI-REWRITE-PLAN.md</span><span class="arkea-doc-list__hint">this rewrite</span>
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

    socket
    |> assign(
      player: player,
      overview: World.overview(player.id),
      page_title: "Arkea Dashboard"
    )
  end

  defp nav_items do
    [
      %{label: "Dashboard", href: "/dashboard", active: true},
      %{label: "World", href: "/world", active: false},
      %{label: "Seed Lab", href: "/seed-lab", active: false},
      %{label: "Community", href: "/community", active: false}
    ]
  end

  defp meta_for(%{active_count: 0}), do: "no nodes yet"
  defp meta_for(%{active_count: n}), do: "#{n} active"

  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)
  defp short_id(_), do: ""

  defp archetype_label(archetype) when is_atom(archetype) do
    archetype
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
