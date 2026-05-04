defmodule ArkeaWeb.SearchLive do
  @moduledoc """
  Global search skeleton (Fase A.6).

  At the moment the search backend covers three lightweight surfaces:

  - **Biotopes**: prefix match on `id` for the player's owned + wild
    biotopes (id-aware, since uuids are the cross-cutting handle).
  - **Help docs**: substring match on the registered titles in
    `Arkea.Views.HelpDoc.list/0`.
  - **Glossary**: substring match on the keys of
    `ArkeaWeb.Components.Help.glossary/0`.

  This is intentionally minimal — Fase F will widen the surface (lineage
  prefix search, audit full-text, blueprint name search) once the
  persistence backbone of Fase B is in place.
  """
  use ArkeaWeb, :live_view

  alias Arkea.Game.World
  alias Arkea.Views.HelpDoc
  alias ArkeaWeb.Components.Help, as: HelpComp
  alias ArkeaWeb.Components.Panel
  alias ArkeaWeb.Components.Shell

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       player: socket.assigns.current_player,
       page_title: "Arkea Search",
       query: "",
       results: empty_results()
     )}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    query = Map.get(params, "q", "") |> String.trim()

    {:noreply,
     socket
     |> assign(query: query, results: search(query, socket.assigns.player))}
  end

  @impl Phoenix.LiveView
  def handle_event("submit_search", %{"search" => %{"q" => q}}, socket) do
    {:noreply, push_patch(socket, to: ~p"/search?q=#{q}")}
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
          <span class="arkea-help__eyebrow">Search</span>
          <h1 class="arkea-help__title">Cerca nel banco</h1>
          <p class="arkea-help__copy">
            Cerca biotopi (per id), documenti e voci di glossario. Lo
            scope verrà esteso a lineage / blueprint / audit nelle fasi
            successive del piano.
          </p>
        </header>

        <form
          phx-submit="submit_search"
          class="arkea-help__layout"
          style="grid-template-columns: 1fr; max-width: 56rem; margin: 0 auto;"
        >
          <div class="arkea-search__field">
            <input
              type="search"
              name="search[q]"
              placeholder="biotope id, doc title, glossary term..."
              value={@query}
              autofocus
              class="arkea-seed-input"
            />
          </div>
        </form>

        <div
          class="arkea-help__layout"
          style="grid-template-columns: 1fr; max-width: 56rem; margin: 1rem auto 0;"
        >
          <div :if={@query == ""} class="arkea-help__empty">
            Inserisci almeno un carattere per iniziare la ricerca.
          </div>

          <Panel.panel :if={@query != ""}>
            <:header
              eyebrow="Biotopes"
              title="Biotopes"
              meta={"#{length(@results.biotopes)}"}
            />
            <:body scroll>
              <ul :if={@results.biotopes != []} class="arkea-help__nav-list">
                <li :for={b <- @results.biotopes} class="arkea-help__nav-item">
                  <.link
                    navigate={~p"/biotopes/#{b.id}"}
                    class="arkea-help__nav-link"
                  >
                    <span class="arkea-help__nav-title">{short_id(b.id)}</span>
                    <span class="arkea-help__nav-summary">{b.archetype} · {b.zone}</span>
                  </.link>
                </li>
              </ul>
              <p :if={@results.biotopes == []} class="arkea-muted">Nessun biotope match.</p>
            </:body>
          </Panel.panel>

          <Panel.panel :if={@query != ""}>
            <:header
              eyebrow="Documenti"
              title="Help docs"
              meta={"#{length(@results.docs)}"}
            />
            <:body scroll>
              <ul :if={@results.docs != []} class="arkea-help__nav-list">
                <li :for={d <- @results.docs} class="arkea-help__nav-item">
                  <.link
                    navigate={~p"/help/#{d.slug}"}
                    class="arkea-help__nav-link"
                  >
                    <span class="arkea-help__nav-title">{d.title}</span>
                    <span class="arkea-help__nav-summary">{d.summary}</span>
                  </.link>
                </li>
              </ul>
              <p :if={@results.docs == []} class="arkea-muted">Nessun documento match.</p>
            </:body>
          </Panel.panel>

          <Panel.panel :if={@query != ""}>
            <:header
              eyebrow="Glossario"
              title="Termini biologici"
              meta={"#{length(@results.glossary)}"}
            />
            <:body scroll>
              <ul :if={@results.glossary != []} class="arkea-help__nav-list">
                <li :for={{term, meta} <- @results.glossary} class="arkea-help__nav-item">
                  <.link
                    navigate={~p"/help/#{meta.doc}?section=#{meta.section}"}
                    class="arkea-help__nav-link"
                  >
                    <span class="arkea-help__nav-title">{term}</span>
                    <span class="arkea-help__nav-summary">{meta.summary}</span>
                  </.link>
                </li>
              </ul>
              <p :if={@results.glossary == []} class="arkea-muted">Nessun termine match.</p>
            </:body>
          </Panel.panel>
        </div>
      </div>
    </Shell.shell>
    """
  end

  defp empty_results, do: %{biotopes: [], docs: [], glossary: []}

  defp search("", _player), do: empty_results()

  defp search(query, player) when is_binary(query) do
    q = String.downcase(query)

    %{
      biotopes: search_biotopes(q, player),
      docs: search_docs(q),
      glossary: search_glossary(q)
    }
  end

  defp search_biotopes(q, player) do
    World.list_biotopes(player.id)
    |> Enum.filter(fn b -> String.contains?(String.downcase(b.id), q) end)
    |> Enum.take(10)
  end

  defp search_docs(q) do
    HelpDoc.list()
    |> Enum.filter(fn d ->
      String.contains?(String.downcase(d.title), q) or
        String.contains?(String.downcase(d.slug), q) or
        String.contains?(String.downcase(d.summary), q)
    end)
  end

  defp search_glossary(q) do
    HelpComp.glossary()
    |> Enum.filter(fn {term, meta} ->
      String.contains?(String.downcase(term), q) or
        String.contains?(String.downcase(meta.summary), q)
    end)
  end

  defp short_id(nil), do: ""
  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)
end
