defmodule ArkeaWeb.HelpLive do
  @moduledoc """
  In-app rendering of the canonical Markdown docs (USER-MANUAL, DESIGN,
  CALIBRATION, plan files). Replaces the previous Dashboard "Docs"
  placeholder.

  Mounted at `/help` (index) and `/help/:doc` (single doc by slug).
  """
  use ArkeaWeb, :live_view

  alias Arkea.Views.HelpDoc
  alias ArkeaWeb.Components.Panel
  alias ArkeaWeb.Components.Shell

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       player: socket.assigns.current_player,
       docs: HelpDoc.list(),
       page_title: "Arkea Help"
     )}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    slug = Map.get(params, "doc", "user-manual")
    anchor = Map.get(params, "section")

    case HelpDoc.find(slug) do
      nil ->
        {:noreply,
         socket
         |> assign(
           selected_doc: nil,
           rendered: nil,
           anchor: nil,
           error: "Documento non trovato: #{slug}"
         )}

      doc ->
        case HelpDoc.render(doc) do
          {:ok, %{html: html, headings: headings}} ->
            {:noreply,
             assign(socket,
               selected_doc: doc,
               rendered: html,
               headings: headings,
               anchor: anchor,
               error: nil,
               page_title: "Arkea Help · #{doc.title}"
             )}

          {:error, reason} ->
            {:noreply,
             assign(socket,
               selected_doc: doc,
               rendered: nil,
               anchor: nil,
               error: "Could not render #{doc.slug}: #{inspect(reason)}"
             )}
        end
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Shell.shell sidebar?={false}>
      <:header>
        <Shell.shell_brand>Arkea</Shell.shell_brand>
        <Shell.shell_nav items={Shell.nav_items(:help)} />
        <div class="arkea-shell__spacer"></div>
        <Shell.shell_user name={@player.display_name} logout_href={~p"/players/log-out"} />
      </:header>

      <div class="arkea-help arkea-scrollable">
        <header class="arkea-help__heading">
          <span class="arkea-help__eyebrow">Help</span>
          <h1 class="arkea-help__title">Documentazione Arkea</h1>
          <p class="arkea-help__copy">
            Riferimenti canonici renderizzati direttamente dai file Markdown
            del repository. Le ancore di sezione sono permalink-friendly:
            condividi un URL come
            <code>/help/user-manual?section=5-8-ricolonizzare-un-home-estinto</code>
            per puntare a una specifica sezione.
          </p>
        </header>

        <div class="arkea-help__layout">
          <aside class="arkea-help__sidebar">
            <Panel.panel class="arkea-help__doc-list">
              <:header eyebrow="Documenti" title="Indice" meta={"#{length(@docs)} doc"} />
              <:body>
                <ul class="arkea-help__nav-list">
                  <li :for={doc <- @docs} class="arkea-help__nav-item">
                    <.link
                      navigate={~p"/help/#{doc.slug}"}
                      class={[
                        "arkea-help__nav-link",
                        @selected_doc && @selected_doc.slug == doc.slug &&
                          "arkea-help__nav-link--active"
                      ]}
                    >
                      <span class="arkea-help__nav-title">{doc.title}</span>
                      <span class="arkea-help__nav-summary">{doc.summary}</span>
                    </.link>
                  </li>
                </ul>
              </:body>
            </Panel.panel>

            <Panel.panel :if={@rendered && @headings != []} class="arkea-help__toc">
              <:header eyebrow="In questa pagina" title="Sezioni" meta={"#{length(@headings)}"} />
              <:body scroll>
                <ul class="arkea-help__toc-list">
                  <li
                    :for={h <- @headings}
                    class={"arkea-help__toc-item arkea-help__toc-item--h#{h.level}"}
                  >
                    <a href={"##{h.anchor}"} class="arkea-help__toc-link">{h.text}</a>
                  </li>
                </ul>
              </:body>
            </Panel.panel>
          </aside>

          <article class="arkea-help__article">
            <%= cond do %>
              <% @error -> %>
                <div class="arkea-help__error">{@error}</div>
              <% @rendered -> %>
                <div class="arkea-help__markdown">
                  {@rendered}
                </div>
              <% true -> %>
                <div class="arkea-help__empty">Seleziona un documento dall'indice.</div>
            <% end %>
          </article>
        </div>
      </div>
    </Shell.shell>
    """
  end
end
