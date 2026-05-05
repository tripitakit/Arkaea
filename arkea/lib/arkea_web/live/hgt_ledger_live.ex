defmodule ArkeaWeb.HGTLedgerLive do
  @moduledoc """
  Per-biotope ledger of horizontal gene transfer events (UI Phase E).

  Mounted at `/biotopes/:id/hgt-ledger`. Reads from `audit_log`,
  filters via `Arkea.Views.HGTLedger.build/2`, and renders both a flat
  table of events and a `donor → recipient` rollup.

  Filter chips honour `?kind=<event_type>` so deep-linking to a
  specific HGT channel (conjugation, transformation, transduction,
  R-M digestion, …) is permalink-friendly.
  """
  use ArkeaWeb, :live_view

  import Ecto.Query

  alias Arkea.Persistence.AuditLog
  alias Arkea.Views.HGTLedger
  alias ArkeaWeb.Components.Panel
  alias ArkeaWeb.Components.Shell

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       player: socket.assigns.current_player,
       biotope_id: nil,
       kind: nil,
       ledger: empty_ledger(),
       page_title: "Arkea HGT ledger"
     )}
  end

  @impl Phoenix.LiveView
  def handle_params(%{"id" => biotope_id} = params, _uri, socket) do
    kind =
      case Map.get(params, "kind") do
        k when is_binary(k) and k != "" -> k
        _ -> nil
      end

    audit = audit_for(biotope_id)
    ledger = HGTLedger.build(audit, kind: kind)

    {:noreply,
     assign(socket,
       biotope_id: biotope_id,
       kind: kind,
       ledger: ledger
     )}
  end

  @impl Phoenix.LiveView
  def handle_event("filter", %{"kind" => kind}, socket) do
    next_kind = if kind == "all", do: nil, else: kind

    {:noreply,
     push_patch(socket,
       to: ~p"/biotopes/#{socket.assigns.biotope_id}/hgt-ledger?kind=#{next_kind || ""}"
     )}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Shell.shell sidebar?={false}>
      <:header>
        <Shell.shell_brand>Arkea</Shell.shell_brand>
        <Shell.shell_nav items={Shell.nav_items(:none)} />
        <div class="arkea-shell__spacer"></div>
        <Shell.shell_user name={@player.display_name} logout_href={~p"/players/log-out"} />
      </:header>

      <div class="arkea-help arkea-scrollable">
        <header class="arkea-help__heading">
          <span class="arkea-help__eyebrow">HGT ledger</span>
          <h1 class="arkea-help__title">Horizontal gene transfer events</h1>
          <p class="arkea-help__copy">
            Provenance of mobile-element movement in biotope <code>{short_id(@biotope_id)}</code>. The flat table is the
            raw event ledger; the rollup aggregates by donor → recipient
            pair.
            <.link
              navigate={~p"/biotopes/#{@biotope_id}"}
              class="arkea-link"
            >
              ← back to biotope viewport
            </.link>
          </p>
        </header>

        <div
          class="arkea-help__layout"
          style="grid-template-columns: 1fr; max-width: 72rem; margin: 0 auto;"
        >
          <div class="arkea-tablist" role="tablist" aria-label="Filter HGT events by kind">
            <button
              type="button"
              phx-click="filter"
              phx-value-kind="all"
              aria-selected={is_nil(@kind)}
              class="arkea-tab"
            >
              All ({@ledger.total})
            </button>
            <button
              :for={kind <- HGTLedger.hgt_types()}
              type="button"
              phx-click="filter"
              phx-value-kind={kind}
              aria-selected={@kind == kind}
              class="arkea-tab"
            >
              {kind} ({Map.get(@ledger.kind_counts, kind, 0)})
            </button>
          </div>

          <Panel.panel>
            <:header
              eyebrow="Donor → recipient"
              title="Aggregated flows"
              meta={"#{length(@ledger.flows)} pairs"}
            />
            <:body scroll>
              <%= if @ledger.flows == [] do %>
                <p class="arkea-muted">
                  No HGT flows yet for this biotope.
                  Provision conjugative plasmids in the seed and let the
                  simulation run a few hundred ticks.
                </p>
              <% else %>
                <table class="arkea-audit__table">
                  <thead>
                    <tr>
                      <th>Donor</th>
                      <th>Recipient</th>
                      <th>Events</th>
                      <th>Last tick</th>
                      <th>Channels</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={flow <- @ledger.flows}>
                      <td class="arkea-audit__id" title={flow.donor_id || ""}>
                        {short_id(flow.donor_id)}
                      </td>
                      <td class="arkea-audit__id" title={flow.recipient_id || ""}>
                        {short_id(flow.recipient_id)}
                      </td>
                      <td>{flow.count}</td>
                      <td class="arkea-audit__tick">{flow.last_tick}</td>
                      <td>
                        <span :for={k <- flow.kinds} class="arkea-token arkea-token--ghost">
                          {k}
                        </span>
                      </td>
                    </tr>
                  </tbody>
                </table>
              <% end %>
            </:body>
          </Panel.panel>

          <Panel.panel>
            <:header
              eyebrow="Raw events"
              title="HGT event log"
              meta={"#{@ledger.total} entries"}
            />
            <:body scroll>
              <%= if @ledger.entries == [] do %>
                <p class="arkea-muted">No matching events.</p>
              <% else %>
                <table class="arkea-audit__table">
                  <thead>
                    <tr>
                      <th>Tick</th>
                      <th>Kind</th>
                      <th>Donor</th>
                      <th>Recipient</th>
                      <th>Payload</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={entry <- @ledger.entries}>
                      <td class="arkea-audit__tick">{entry.tick}</td>
                      <td>
                        <span class="arkea-audit__type arkea-audit__type--metabolite">
                          {entry.kind}
                        </span>
                      </td>
                      <td class="arkea-audit__id" title={entry.donor_id || ""}>
                        {short_id(entry.donor_id)}
                      </td>
                      <td class="arkea-audit__id" title={entry.recipient_id || ""}>
                        {short_id(entry.recipient_id)}
                      </td>
                      <td class="arkea-audit__payload">
                        {format_payload(entry.payload)}
                      </td>
                    </tr>
                  </tbody>
                </table>
              <% end %>
            </:body>
          </Panel.panel>
        </div>
      </div>
    </Shell.shell>
    """
  end

  defp empty_ledger, do: %{entries: [], flows: [], kind_counts: %{}, total: 0}

  defp audit_for(biotope_id) do
    Arkea.Repo.all(
      from a in AuditLog,
        where: a.target_biotope_id == ^biotope_id,
        order_by: [desc: a.occurred_at_tick],
        limit: 500
    )
  end

  defp short_id(nil), do: "—"
  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)

  defp format_payload(nil), do: ""
  defp format_payload(map) when is_map(map) and map_size(map) == 0, do: ""

  defp format_payload(map) when is_map(map) do
    map
    |> Enum.reject(fn {k, _} -> k in ["lineage_id", "parent_id", "tick"] end)
    |> Enum.map(fn {k, v} -> "#{k}=#{inspect(v)}" end)
    |> Enum.join(" · ")
  end

  defp format_payload(other), do: inspect(other)
end
