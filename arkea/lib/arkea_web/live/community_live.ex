defmodule ArkeaWeb.CommunityLive do
  @moduledoc """
  Public read-only listing of community-mode runs (UI rewrite — phase U6).

  Joins each `community_provisioned` event in `audit_log` with the
  current biotope summary from `Arkea.Game.World.list_biotopes/0`. A
  community is identified by the (biotope_id, occurred_at) pair from the
  audit event; this preserves the original founder count regardless of
  later evolutionary divergence.
  """
  use ArkeaWeb, :live_view

  import Ecto.Query

  alias Arkea.Game.PrototypePlayer
  alias Arkea.Game.World
  alias Arkea.Persistence.AuditLog
  alias Arkea.Repo
  alias ArkeaWeb.Components.Panel
  alias ArkeaWeb.Components.Shell

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, refresh(socket)}
  end

  @impl Phoenix.LiveView
  def handle_event("refresh", _params, socket), do: {:noreply, refresh(socket)}

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Shell.shell sidebar?={false}>
      <:header>
        <Shell.shell_brand>Arkea</Shell.shell_brand>
        <Shell.shell_nav items={nav_items()} />
        <div class="arkea-shell__spacer"></div>
        <button
          type="button"
          phx-click="refresh"
          class="arkea-biotope__header-btn"
          title="Refresh"
        >
          ↻
        </button>
        <Shell.shell_user name={@current_player.display_name} logout_href={~p"/players/log-out"} />
      </:header>

      <div class="arkea-audit">
        <header class="arkea-audit__heading">
          <span class="arkea-seed-lab__eyebrow">Community</span>
          <h1 class="arkea-seed-lab__title">Multi-seed runs</h1>
          <p class="arkea-seed-lab__copy">
            Read-only browser of biotopes that received a community-mode
            inoculation (DESIGN.md Block 19). The founder list is reconstructed
            from the persisted `community_provisioned` audit events.
          </p>
        </header>

        <Panel.panel class="arkea-audit__panel">
          <:body scroll>
            <%= if @entries == [] do %>
              <Panel.empty_state title="No community runs yet">
                Provision a community via the simulation API to see it
                listed here.
              </Panel.empty_state>
            <% else %>
              <ul class="arkea-community-list">
                <li :for={entry <- @entries} class="arkea-community-list__item">
                  <div class="arkea-community-list__main">
                    <div class="arkea-community-list__title">
                      {entry.archetype_label}
                    </div>
                    <div class="arkea-community-list__meta">
                      seeds {entry.founder_count} · phase {entry.phase}
                      · provisioned {format_time(entry.occurred_at)}
                    </div>
                  </div>
                  <div class="arkea-community-list__metrics">
                    <span class="arkea-community-list__metric">
                      tick {entry.tick_count}
                    </span>
                    <span class="arkea-community-list__metric">
                      lineages {entry.lineage_count}
                    </span>
                    <.link
                      navigate={~p"/biotopes/#{entry.biotope_id}"}
                      class="arkea-button arkea-button--secondary arkea-community-list__link"
                    >
                      Open →
                    </.link>
                  </div>
                </li>
              </ul>
            <% end %>
          </:body>
        </Panel.panel>
      </div>
    </Shell.shell>
    """
  end

  # ---------------------------------------------------------------------------

  defp refresh(socket) do
    biotopes = Map.new(World.list_biotopes(PrototypePlayer.id()), &{&1.id, &1})
    events = community_events()

    entries =
      events
      |> Enum.map(fn event ->
        summary = Map.get(biotopes, event.target_biotope_id)
        build_entry(event, summary)
      end)

    assign(socket,
      current_player: socket.assigns.current_player,
      entries: entries,
      page_title: "Arkea Community"
    )
  end

  defp community_events do
    AuditLog
    |> where([a], a.event_type == "community_provisioned")
    |> order_by([a], desc: a.occurred_at)
    |> limit(50)
    |> Repo.all()
  end

  defp build_entry(event, summary) do
    payload = event.payload || %{}

    %{
      biotope_id: event.target_biotope_id,
      occurred_at: event.occurred_at,
      founder_count: list_size(payload, "founders") || list_size(payload, "seed_entries") || 0,
      phase: Map.get(payload, "phase_name") || Map.get(payload, "phase") || "?",
      archetype_label: archetype_label(summary, payload),
      tick_count: (summary && summary.tick_count) || event.occurred_at_tick || 0,
      lineage_count: (summary && summary.lineage_count) || 0
    }
  end

  defp list_size(map, key) when is_map(map) do
    case Map.get(map, key) do
      list when is_list(list) -> length(list)
      _ -> nil
    end
  end

  defp archetype_label(%{archetype: archetype}, _payload) when is_atom(archetype) do
    humanize(Atom.to_string(archetype))
  end

  defp archetype_label(_summary, payload) do
    case Map.get(payload, "archetype") do
      a when is_binary(a) -> humanize(a)
      _ -> "Unknown biotope"
    end
  end

  defp humanize(s) do
    s |> String.replace("_", " ") |> String.split() |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp format_time(nil), do: "—"

  defp format_time(%DateTime{} = dt) do
    dt
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
    |> String.replace("T", " ")
    |> String.replace_suffix("Z", "")
  end

  defp nav_items do
    [
      %{label: "Dashboard", href: "/dashboard", active: false},
      %{label: "World", href: "/world", active: false},
      %{label: "Audit", href: "/audit", active: false},
      %{label: "Community", href: "/community", active: true}
    ]
  end
end
