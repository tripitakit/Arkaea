defmodule ArkeaWeb.AuditLive do
  @moduledoc """
  Global audit feed (UI rewrite — phase U6).

  Reads the persistent `Arkea.Persistence.AuditLog` table populated by
  `AuditWriter`. Filters by event type via tabs; paginates with a simple
  cursor (offset). The view is read-only and never opens a global scrollbar
  — the table body scrolls internally.
  """
  use ArkeaWeb, :live_view

  import Ecto.Query

  alias Arkea.Persistence.AuditLog
  alias Arkea.Repo
  alias ArkeaWeb.Components.Panel
  alias ArkeaWeb.Components.Shell

  @page_size 50

  @event_types [
    :all,
    :hgt_event,
    :mutation_notable,
    :mass_lysis,
    :intervention,
    :community_provisioned,
    :colonization,
    :mobile_element_release
  ]

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(filter: :all, page: 0, total: 0, entries: [])
     |> reload_entries()}
  end

  @impl Phoenix.LiveView
  def handle_event("filter", %{"to" => to}, socket) do
    f = parse_filter(to)
    {:noreply, socket |> assign(filter: f, page: 0) |> reload_entries()}
  end

  def handle_event("page", %{"to" => "next"}, socket) do
    next = socket.assigns.page + 1
    last = max(div(socket.assigns.total - 1, @page_size), 0)
    page = min(next, last)
    {:noreply, socket |> assign(page: page) |> reload_entries()}
  end

  def handle_event("page", %{"to" => "prev"}, socket) do
    {:noreply, socket |> assign(page: max(socket.assigns.page - 1, 0)) |> reload_entries()}
  end

  def handle_event("refresh", _params, socket), do: {:noreply, reload_entries(socket)}

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
          <span class="arkea-seed-lab__eyebrow">Audit</span>
          <h1 class="arkea-seed-lab__title">Global event stream</h1>
          <p class="arkea-seed-lab__copy">
            Append-only log of typed runtime events: HGT transfers, notable
            mutations, mass lysis, player interventions, colonisation,
            community provisioning. Reads directly from the audit_log
            persistence table.
          </p>
        </header>

        <div class="arkea-audit__toolbar">
          <div class="arkea-world__filters" role="tablist" aria-label="Audit filter">
            <button
              :for={f <- filter_options()}
              type="button"
              role="tab"
              phx-click="filter"
              phx-value-to={Atom.to_string(f)}
              aria-selected={@filter == f}
              class={[
                "arkea-world__filter",
                @filter == f && "arkea-world__filter--active"
              ]}
            >
              {filter_label(f)}
            </button>
          </div>

          <div class="arkea-audit__pager">
            <span class="arkea-audit__pager-info">
              {pager_label(@page, @total)}
            </span>
            <button
              type="button"
              phx-click="page"
              phx-value-to="prev"
              disabled={@page == 0}
              class="arkea-button arkea-button--secondary arkea-audit__pager-btn"
              aria-label="Previous page"
            >
              ←
            </button>
            <button
              type="button"
              phx-click="page"
              phx-value-to="next"
              disabled={(@page + 1) * @page_size >= @total}
              class="arkea-button arkea-button--secondary arkea-audit__pager-btn"
              aria-label="Next page"
            >
              →
            </button>
          </div>
        </div>

        <Panel.panel class="arkea-audit__panel">
          <:body scroll>
            <%= if @entries == [] do %>
              <Panel.empty_state title="No audit events yet">
                Once a biotope simulation runs, its typed events will be
                persisted here.
              </Panel.empty_state>
            <% else %>
              <table class="arkea-audit__table">
                <thead>
                  <tr>
                    <th>Time</th>
                    <th>Type</th>
                    <th>Tick</th>
                    <th>Biotope</th>
                    <th>Lineage</th>
                    <th>Payload</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={entry <- @entries}>
                    <td class="arkea-audit__time">{format_time(entry.occurred_at)}</td>
                    <td>
                      <span class={[
                        "arkea-audit__type",
                        "arkea-audit__type--#{type_tone(entry.event_type)}"
                      ]}>
                        {entry.event_type}
                      </span>
                    </td>
                    <td class="arkea-audit__tick">{entry.occurred_at_tick}</td>
                    <td class="arkea-audit__id">{short_id(entry.target_biotope_id)}</td>
                    <td class="arkea-audit__id">{short_id(entry.target_lineage_id)}</td>
                    <td class="arkea-audit__payload">{format_payload(entry.payload)}</td>
                  </tr>
                </tbody>
              </table>
            <% end %>
          </:body>
        </Panel.panel>
      </div>
    </Shell.shell>
    """
  end

  # ---------------------------------------------------------------------------
  # Query

  defp reload_entries(socket) do
    filter = socket.assigns.filter
    page = socket.assigns.page

    base = base_query(filter)
    total = Repo.aggregate(base, :count, :id)

    entries =
      base
      |> order_by([a], desc: a.occurred_at)
      |> limit(^@page_size)
      |> offset(^(page * @page_size))
      |> Repo.all()

    assign(socket,
      entries: entries,
      total: total,
      page_size: @page_size,
      page_title: "Arkea Audit"
    )
  end

  defp base_query(:all), do: from(a in AuditLog)

  defp base_query(filter) when is_atom(filter) do
    type_str = Atom.to_string(filter)
    from(a in AuditLog, where: a.event_type == ^type_str)
  end

  # ---------------------------------------------------------------------------
  # Helpers

  defp nav_items do
    [
      %{label: "Dashboard", href: "/dashboard", active: false},
      %{label: "World", href: "/world", active: false},
      %{label: "Audit", href: "/audit", active: true},
      %{label: "Community", href: "/community", active: false}
    ]
  end

  defp filter_options, do: @event_types

  defp parse_filter(s) when is_binary(s) do
    atom = String.to_existing_atom(s)
    if atom in @event_types, do: atom, else: :all
  rescue
    ArgumentError -> :all
  end

  defp filter_label(:all), do: "All"
  defp filter_label(:hgt_event), do: "HGT"
  defp filter_label(:mutation_notable), do: "Mutations"
  defp filter_label(:mass_lysis), do: "Lysis"
  defp filter_label(:intervention), do: "Interventions"
  defp filter_label(:community_provisioned), do: "Community"
  defp filter_label(:colonization), do: "Colonisation"
  defp filter_label(:mobile_element_release), do: "Mobile"
  defp filter_label(other), do: Atom.to_string(other)

  defp pager_label(_page, 0), do: "0 events"

  defp pager_label(page, total) do
    from = page * @page_size + 1
    to = min((page + 1) * @page_size, total)
    "#{from}–#{to} of #{total}"
  end

  defp short_id(nil), do: "—"
  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)
  defp short_id(_), do: "—"

  defp format_time(nil), do: "—"

  defp format_time(%DateTime{} = dt) do
    dt
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
    |> String.replace("T", " ")
    |> String.replace_suffix("Z", "")
  end

  defp format_payload(nil), do: ""
  defp format_payload(map) when is_map(map) and map_size(map) == 0, do: ""

  defp format_payload(map) when is_map(map) do
    map
    |> Enum.take(4)
    |> Enum.map_join(" · ", fn {k, v} -> "#{k}=#{inline_value(v)}" end)
  end

  defp format_payload(other), do: inspect(other)

  defp inline_value(v) when is_binary(v), do: String.slice(v, 0, 12)
  defp inline_value(v) when is_number(v), do: to_string(v)
  defp inline_value(v) when is_atom(v), do: Atom.to_string(v)
  defp inline_value(v), do: inspect(v, limit: 1)

  defp type_tone("hgt_event"), do: "metabolite"
  defp type_tone("mutation_notable"), do: "signal"
  defp type_tone("mass_lysis"), do: "stress"
  defp type_tone("intervention"), do: "growth"
  defp type_tone("community_provisioned"), do: "gold"
  defp type_tone("colonization"), do: "teal"
  defp type_tone("mobile_element_release"), do: "rust"
  defp type_tone(_), do: "muted"
end
