defmodule ArkeaWeb.SimLive do
  @moduledoc """
  Detailed LiveView viewport for one authoritative biotope.

  The simulation remains server-authoritative: this module subscribes to the
  selected `"biotope:<id>"`, receives `{:biotope_tick, new_state, events}` from
  `Arkea.Sim.Biotope.Server`, and turns the current `BiotopeState` into:

    - a LiveView dashboard for operator-facing telemetry (sidebar +
      bottom tabs: Events / Lineages / Chemistry / Interventions);
    - a `scene_layout` consumed by `ArkeaWeb.Components.BiotopeScene` to
      render the procedural 2D scene as native SVG (since UI rewrite phase
      U3, no Pixi/canvas/WebGL hop).

  No tick logic runs here. The browser scene is a pure visualization derived
  from per-phase authoritative state, consistent with DESIGN.md Blocks 12 and 14.
  """

  use ArkeaWeb, :live_view

  alias Arkea.Ecology.Lineage
  alias Arkea.Game.PlayerInterventions
  alias Arkea.Game.SeedLab
  alias Arkea.Sim.Biotope.Server, as: BiotopeServer
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Phenotype
  alias Arkea.Views.BiotopeScene, as: SceneLayout
  alias ArkeaWeb.Components.Chart
  alias ArkeaWeb.Components.Panel
  alias ArkeaWeb.Components.Phylogeny
  alias ArkeaWeb.Components.Shell

  @max_event_log 20
  @max_operator_log 8

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       biotope_id: nil,
       sim_state: nil,
       player: socket.assigns.current_player,
       phenotype_cache: %{},
       selected_phase_name: nil,
       event_log: [],
       operator_log: [],
       operator_error: nil,
       intervention_status: default_intervention_status(),
       running: false,
       scene_layout: SceneLayout.build(%{phases: [], lineages: []}),
       not_found?: false,
       lineage_sort: :abundance,
       bottom_tab: :events,
       selected_lineage_id: nil,
       trends_samples: [],
       trends_audit: [],
       phylogeny_model: nil,
       page_title: "Arkea Biotope"
     )}
  end

  @impl Phoenix.LiveView
  def handle_info({:biotope_tick, new_state, events}, socket) do
    cache = update_phenotype_cache(socket.assigns.phenotype_cache, new_state)
    log = prepend_events(socket.assigns.event_log, events)
    selected_phase_name = resolve_selected_phase(socket.assigns.selected_phase_name, new_state)

    socket =
      socket
      |> assign(
        sim_state: new_state,
        phenotype_cache: cache,
        selected_phase_name: selected_phase_name,
        event_log: log,
        running: true,
        intervention_status: intervention_status(socket.assigns.player, socket.assigns.biotope_id)
      )
      |> assign_scene_snapshot()
      |> maybe_refresh_trends(new_state)

    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # When the user is currently viewing the Trends tab and the new tick
  # crosses a sampling boundary, re-load the time-series + audit so the
  # chart updates in near-real time.
  defp maybe_refresh_trends(socket, %{tick_count: tick}) do
    period = Arkea.Persistence.TimeSeries.sampling_period()

    if socket.assigns.bottom_tab == :trends and rem(tick, period) == 0 do
      maybe_load_trends_data(socket, :trends)
    else
      socket
    end
  end

  defp maybe_refresh_trends(socket, _state), do: socket

  @impl Phoenix.LiveView
  def handle_params(%{"id" => biotope_id}, _uri, socket) do
    if Phoenix.LiveView.connected?(socket) and socket.assigns.biotope_id != biotope_id do
      # Drop the previous subscription so cross-biotope ticks don't keep
      # arriving and overwriting `sim_state` with stale data.
      previous = socket.assigns.biotope_id

      if is_binary(previous) do
        Phoenix.PubSub.unsubscribe(Arkea.PubSub, "biotope:#{previous}")
      end

      Phoenix.PubSub.subscribe(Arkea.PubSub, "biotope:#{biotope_id}")
    end

    {sim_state, phenotype_cache} = load_initial_state(biotope_id)
    selected_phase_name = resolve_selected_phase(nil, sim_state)

    socket =
      socket
      |> assign(
        biotope_id: biotope_id,
        sim_state: sim_state,
        phenotype_cache: phenotype_cache,
        selected_phase_name: selected_phase_name,
        event_log: [],
        operator_log: [],
        operator_error: nil,
        intervention_status: intervention_status(socket.assigns.player, biotope_id),
        running: Phoenix.LiveView.connected?(socket) and not is_nil(sim_state),
        not_found?: is_nil(sim_state),
        page_title: page_title(sim_state, biotope_id)
      )
      |> assign_scene_snapshot()

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("select_phase", %{"phase" => phase_name}, socket) do
    selected_phase_name = find_phase_name(socket.assigns.sim_state, phase_name)

    socket =
      if selected_phase_name do
        socket
        |> assign(selected_phase_name: selected_phase_name)
        |> assign_scene_snapshot()
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("sort_lineages", %{"by" => field}, socket) do
    sort =
      if field in ~w[abundance growth repair born],
        do: String.to_existing_atom(field),
        else: :abundance

    {:noreply, assign(socket, lineage_sort: sort)}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab_atom =
      case tab do
        "lineages" -> :lineages
        "chemistry" -> :chemistry
        "interventions" -> :interventions
        "trends" -> :trends
        "phylogeny" -> :phylogeny
        _ -> :events
      end

    socket =
      socket
      |> assign(bottom_tab: tab_atom)
      |> maybe_load_trends_data(tab_atom)
      |> maybe_load_phylogeny_data(tab_atom)

    {:noreply, socket}
  end

  def handle_event("select_lineage", %{"id" => id}, socket) do
    selected =
      cond do
        is_nil(socket.assigns.sim_state) -> nil
        socket.assigns.selected_lineage_id == id -> nil
        Enum.any?(socket.assigns.sim_state.lineages, &(&1.id == id)) -> id
        true -> nil
      end

    {:noreply, assign(socket, selected_lineage_id: selected)}
  end

  def handle_event("close_drawer", _params, socket) do
    {:noreply, assign(socket, selected_lineage_id: nil)}
  end

  def handle_event("recolonize_home", _params, socket) do
    case SeedLab.recolonize_home(socket.assigns.player, socket.assigns.biotope_id) do
      {:ok, %{lineage_id: lineage_id, tick: tick}} ->
        entry = %{kind: "Home recolonized", scope: "biotope", tick: tick, lineage: lineage_id}

        {:noreply,
         socket
         |> assign(
           operator_log: prepend_operator_log(socket.assigns.operator_log, entry),
           operator_error: nil
         )}

      {:error, reason} ->
        {:noreply, assign(socket, operator_error: recolonize_error_message(reason))}
    end
  end

  def handle_event("apply_intervention", params, socket) do
    case socket.assigns.sim_state do
      %BiotopeState{id: biotope_id} ->
        with {:ok, command} <- intervention_command(params, socket.assigns.selected_phase_name),
             {:ok, result} <-
               PlayerInterventions.apply(socket.assigns.player, biotope_id, command) do
          entry = operator_entry(command, result)

          {:noreply,
           socket
           |> assign(
             operator_log: prepend_operator_log(socket.assigns.operator_log, entry),
             operator_error: nil,
             intervention_status: intervention_status(socket.assigns.player, biotope_id)
           )}
        else
          {:error, reason} ->
            {:noreply,
             assign(socket,
               operator_error: intervention_error_message(reason),
               intervention_status: intervention_status(socket.assigns.player, biotope_id)
             )}
        end

      nil ->
        {:noreply, assign(socket, operator_error: "Biotope state is not available yet.")}
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    selected_lineage =
      assigns.sim_state &&
        Enum.find(assigns.sim_state.lineages, &(&1.id == assigns.selected_lineage_id))

    assigns = assign(assigns, selected_lineage: selected_lineage)

    ~H"""
    <Shell.shell sidebar?={not is_nil(@sim_state) and not @not_found?}>
      <:header>
        <Shell.shell_brand>Arkea</Shell.shell_brand>
        <Shell.shell_nav items={nav_items()} />
        <span :if={@sim_state} class="arkea-biotope__title-chip">
          <span
            class="arkea-biotope__title-dot"
            style={"background: #{archetype_color(@sim_state.archetype)}"}
            aria-hidden="true"
          />
          <span>{phase_label(@sim_state.archetype)}</span>
        </span>
        <div class="arkea-shell__spacer"></div>
        <a
          :if={@sim_state}
          href={~p"/api/biotopes/#{@biotope_id}/snapshot"}
          class="arkea-biotope__header-btn"
          title="Download snapshot.json (full state + audit + time-series)"
          aria-label="Download biotope snapshot JSON"
          download
        >
          ⤓
        </a>
        <button
          :if={@sim_state}
          type="button"
          class="arkea-biotope__header-btn"
          onclick="document.getElementById('topology-modal').showModal()"
          title="Topology details"
          aria-label="Topology details"
        >
          ⚙
        </button>
        <Shell.shell_user name={@player.display_name} logout_href={~p"/players/log-out"} />
      </:header>

      <:sidebar :if={not is_nil(@sim_state) and not @not_found?}>
        <.phase_sidebar
          sim_state={@sim_state}
          selected_phase_name={@selected_phase_name}
          running={@running}
          intervention_status={@intervention_status}
        />
      </:sidebar>

      <%= cond do %>
        <% @not_found? -> %>
          <.missing_view biotope_id={@biotope_id} />
        <% is_nil(@sim_state) -> %>
          <.loading_view />
        <% true -> %>
          <div class="arkea-biotope">
            <.recolonize_banner
              :if={
                @intervention_status.owner? and
                  BiotopeState.total_abundance(@sim_state) == 0
              }
              operator_error={@operator_error}
              biotope_id={@biotope_id}
            />

            <aside
              :if={@selected_lineage}
              class="arkea-drawer arkea-drawer--right"
              aria-label="Lineage detail"
            >
              <.lineage_drawer
                lineage={@selected_lineage}
                phenotype_cache={@phenotype_cache}
                biotope_id={@biotope_id}
              />
            </aside>

            <section class="arkea-biotope__bottom" aria-label="Auxiliary panel">
              <div class="arkea-tablist" role="tablist">
                <button
                  :for={{id, label} <- bottom_tabs()}
                  role="tab"
                  type="button"
                  phx-click="switch_tab"
                  phx-value-tab={Atom.to_string(id)}
                  aria-selected={@bottom_tab == id}
                  class="arkea-tab"
                >
                  {label}
                </button>
              </div>
              <div class="arkea-biotope__bottom-body arkea-scrollable">
                <%= case @bottom_tab do %>
                  <% :events -> %>
                    <.event_log_content event_log={@event_log} />
                  <% :lineages -> %>
                    <.lineage_table
                      sim_state={@sim_state}
                      phenotype_cache={@phenotype_cache}
                      lineage_sort={@lineage_sort}
                      selected_lineage_id={@selected_lineage_id}
                    />
                  <% :trends -> %>
                    <.trends_panel
                      samples={@trends_samples}
                      audit={@trends_audit}
                    />
                  <% :phylogeny -> %>
                    <.phylogeny_panel model={@phylogeny_model} />
                  <% :chemistry -> %>
                    <.chemistry_panel sim_state={@sim_state} />
                  <% :interventions -> %>
                    <.operator_content
                      selected_phase_name={@selected_phase_name}
                      operator_log={@operator_log}
                      operator_error={@operator_error}
                      intervention_status={@intervention_status}
                    />
                <% end %>
              </div>
            </section>

            <.topology_modal sim_state={@sim_state} />
          </div>
      <% end %>
    </Shell.shell>
    """
  end

  # ---------------------------------------------------------------------------
  # Sidebar (phase list + KPIs)

  attr :sim_state, :map, required: true
  attr :selected_phase_name, :atom, default: nil
  attr :running, :boolean, default: false
  attr :intervention_status, :map, required: true

  defp phase_sidebar(assigns) do
    total_population = BiotopeState.total_abundance(assigns.sim_state)
    lineage_count = length(assigns.sim_state.lineages)

    assigns =
      assign(assigns, total_population: total_population, lineage_count: lineage_count)

    ~H"""
    <div class="arkea-biotope__sidebar arkea-scrollable">
      <div class="arkea-biotope__sidebar-section">
        <div class="arkea-biotope__sidebar-eyebrow">Biotope</div>
        <div class="arkea-biotope__sidebar-stats">
          <div class="arkea-biotope__sidebar-stat">
            <span>Tick</span>
            <span class="arkea-biotope__sidebar-stat-value">{@sim_state.tick_count}</span>
          </div>
          <div class="arkea-biotope__sidebar-stat">
            <span>Lineages</span>
            <span class="arkea-biotope__sidebar-stat-value">{@lineage_count}</span>
          </div>
          <div class="arkea-biotope__sidebar-stat">
            <span>N total</span>
            <span class="arkea-biotope__sidebar-stat-value">{format_compact(@total_population)}</span>
          </div>
          <div class="arkea-biotope__sidebar-stat">
            <span>Stream</span>
            <span class={[
              "arkea-biotope__sidebar-stat-value",
              @running && "arkea-biotope__sidebar-stat-value--ok"
            ]}>
              {if @running, do: "live", else: "shell"}
            </span>
          </div>
        </div>
      </div>

      <div class="arkea-biotope__sidebar-section">
        <div class="arkea-biotope__sidebar-eyebrow">Phases</div>
        <ul class="arkea-phase-list" role="list">
          <li :for={phase <- @sim_state.phases}>
            <button
              type="button"
              phx-click="select_phase"
              phx-value-phase={Atom.to_string(phase.name)}
              class={[
                "arkea-phase-list__item",
                @selected_phase_name == phase.name && "arkea-phase-list__item--active"
              ]}
              aria-current={@selected_phase_name == phase.name && "true"}
            >
              <span
                class="arkea-phase-list__swatch"
                style={"background: #{phase_color(phase.name)}"}
                aria-hidden="true"
              />
              <span class="arkea-phase-list__main">
                <span class="arkea-phase-list__label">{phase_label(phase.name)}</span>
                <span class="arkea-phase-list__meta">
                  T {format_float(phase.temperature, 1)}°C · pH {format_float(phase.ph, 1)}
                </span>
              </span>
              <span class="arkea-phase-list__count">
                {format_compact(phase_population(@sim_state.lineages, phase.name))}
              </span>
            </button>
          </li>
        </ul>
      </div>

      <.phase_inspector
        sim_state={@sim_state}
        selected_phase_name={@selected_phase_name}
      />
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Recolonize banner — surfaced only when the owner's home biotope has
  # collapsed to zero abundance.

  attr :operator_error, :string, default: nil
  attr :biotope_id, :string, required: true

  defp recolonize_banner(assigns) do
    ~H"""
    <div class="arkea-recolonize-banner" role="status">
      <div class="arkea-recolonize-banner__body">
        <span class="arkea-recolonize-banner__title">Colony extinct</span>
        <p class="arkea-recolonize-banner__copy">
          The seeded population has collapsed to zero. Two paths to restart
          the home biotope:
        </p>
        <ul class="arkea-recolonize-banner__list">
          <li>
            <strong>Re-inoculate as-is</strong> — fresh founder built from
            the same locked blueprint. Useful when the previous extinction
            looked like bad luck and the seed strategy is otherwise sound.
          </li>
          <li>
            <strong>Edit seed and recolonize</strong> — open the Seed Lab
            with the previous spec pre-loaded; change every field except
            the starter archetype, then submit. The old blueprint stays in
            the audit log, the new one becomes the home's founder.
          </li>
        </ul>
        <p :if={@operator_error} class="arkea-recolonize-banner__error">
          {@operator_error}
        </p>
      </div>
      <div class="arkea-recolonize-banner__actions">
        <.arkea_button
          variant="secondary"
          phx-click="recolonize_home"
          phx-confirm="Re-inoculate the home biotope with a fresh founder colony from the locked seed?"
          disable_with="Re-inoculating…"
          class="arkea-recolonize-banner__cta"
        >
          Re-inoculate as-is
        </.arkea_button>
        <.arkea_button
          variant="primary"
          navigate={~p"/seed-lab?recolonize=#{@biotope_id}"}
          class="arkea-recolonize-banner__cta"
        >
          Edit seed and recolonize
        </.arkea_button>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Lineage drawer

  attr :lineage, :map, required: true
  attr :phenotype_cache, :map, required: true
  attr :biotope_id, :string, required: true

  defp lineage_drawer(assigns) do
    phenotype = Map.get(assigns.phenotype_cache, assigns.lineage.id)
    cluster = phenotype_cluster(phenotype)
    abundance = Lineage.total_abundance(assigns.lineage)

    assigns =
      assign(assigns,
        phenotype: phenotype,
        cluster: cluster,
        abundance: abundance,
        color: lineage_color(assigns.lineage.id, phenotype)
      )

    ~H"""
    <Panel.panel>
      <:header
        eyebrow="Selected lineage"
        title={short_id(@lineage.id)}
        meta={@cluster}
      />
      <:body scroll>
        <div class="arkea-drawer__swatch-row">
          <span class="arkea-drawer__swatch" style={"background: #{@color}"} />
          <span class="arkea-drawer__id">{@lineage.id}</span>
        </div>

        <ul class="arkea-drawer__kv">
          <li><span>N total</span><span>{@abundance}</span></li>
          <li><span>Born</span><span>tick {@lineage.created_at_tick}</span></li>
          <li :if={@phenotype}>
            <span>µ (h⁻¹)</span><span>{format_float(@phenotype.base_growth_rate, 3)}</span>
          </li>
          <li :if={@phenotype}>
            <span>ε (repair)</span><span>{format_float(@phenotype.repair_efficiency, 3)}</span>
          </li>
          <li :if={@phenotype}>
            <span>Surface tags</span>
            <span>{format_surface_tags(@phenotype.surface_tags)}</span>
          </li>
        </ul>

        <div class="arkea-drawer__section">
          <div class="arkea-drawer__section-title">Per-phase abundance</div>
          <ul class="arkea-drawer__kv">
            <li :for={{phase, count} <- sorted_phase_abundances(@lineage)}>
              <span>{phase_label(phase)}</span>
              <span>{count}</span>
            </li>
          </ul>
        </div>
      </:body>
      <:footer>
        <.arkea_button variant="ghost" size="sm" phx-click="close_drawer">
          Close
        </.arkea_button>
        <.arkea_button
          variant="secondary"
          size="sm"
          navigate={~p"/audit"}
          title="Open the audit log to inspect lineage events"
        >
          Audit log
        </.arkea_button>
        <.arkea_button
          variant="secondary"
          size="sm"
          navigate={~p"/biotopes/#{@biotope_id}/hgt-ledger"}
          title="Open the HGT provenance ledger for this biotope"
        >
          HGT ledger
        </.arkea_button>
      </:footer>
    </Panel.panel>
    """
  end

  defp loading_view(assigns) do
    ~H"""
    <div class="arkea-loading mt-6">
      <span class="arkea-spinner" aria-hidden="true"></span>
      <h2 class="arkea-loading__title">Loading biotope viewport</h2>
      <p class="arkea-loading__copy">
        Waiting for the authoritative biotope process to publish its first state.
      </p>
    </div>
    """
  end

  defp missing_view(assigns) do
    ~H"""
    <div class="arkea-loading mt-6">
      <h2 class="arkea-loading__title">Biotope not found</h2>
      <p class="arkea-loading__copy">
        No active `Biotope.Server` is registered for {@biotope_id || "this route"}.
      </p>
      <div class="arkea-cta-stack">
        <.arkea_button variant="primary" href={~p"/world"} class="arkea-action-button--wide">
          Return to world overview
        </.arkea_button>
        <.arkea_button variant="secondary" href={~p"/seed-lab"} class="arkea-action-button--wide">
          Open seed lab
        </.arkea_button>
      </div>
    </div>
    """
  end

  defp phase_inspector(assigns) do
    phase = selected_phase(assigns.sim_state, assigns.selected_phase_name)

    phase_lineages =
      phase &&
        Enum.filter(assigns.sim_state.lineages, &(Lineage.abundance_in(&1, phase.name) > 0))

    total_population = phase && phase_population(assigns.sim_state.lineages, phase.name)
    richness = phase && length(phase_lineages)
    shannon = phase && shannon_diversity(phase_lineages, phase.name)
    phage_load = phase && round_metric(sum_phage_pool(phase.phage_pool))

    assigns =
      assign(assigns,
        phase: phase,
        total_population: total_population,
        richness: richness,
        shannon: shannon,
        phage_load: phage_load
      )

    ~H"""
    <section class="arkea-card">
      <%= if @phase do %>
        <div class="arkea-card__header">
          <div>
            <div class="arkea-card__eyebrow">Focused phase</div>
            <h2 id="phase-inspector-title" class="arkea-card__title">{phase_label(@phase.name)}</h2>
          </div>
          <div class="arkea-phase-mark" style={"background: #{phase_color(@phase.name)}"}></div>
        </div>

        <div class="arkea-phase-kpis">
          <div class="arkea-mini-stat">
            <span class="arkea-mini-stat__label">N</span>
            <span class="arkea-mini-stat__value">{format_compact(@total_population)}</span>
          </div>
          <div class="arkea-mini-stat">
            <span class="arkea-mini-stat__label">richness</span>
            <span class="arkea-mini-stat__value">{@richness}</span>
          </div>
          <div class="arkea-mini-stat">
            <span class="arkea-mini-stat__label">Shannon H′</span>
            <span class="arkea-mini-stat__value">{@shannon}</span>
          </div>
          <div class="arkea-mini-stat">
            <span class="arkea-mini-stat__label">phages</span>
            <span class="arkea-mini-stat__value">{@phage_load}</span>
          </div>
        </div>

        <div class="arkea-phase-environment">
          <.env_reading label="T (°C)" value={format_float(@phase.temperature, 1)} />
          <.env_reading label="pH" value={format_float(@phase.ph, 1)} />
          <.env_reading label="Osmolarity" value={format_float(@phase.osmolarity, 0)} />
          <.env_reading
            label="Dilution"
            value={"#{format_float(@phase.dilution_rate * 100.0, 1)}%/tick"}
          />
        </div>
      <% else %>
        <div class="arkea-card__header">
          <div>
            <div class="arkea-card__eyebrow">Focused phase</div>
            <h2 id="phase-inspector-title" class="arkea-card__title">No phase available</h2>
          </div>
        </div>
        <p class="arkea-muted">
          This biotope does not currently expose any authoritative phase pocket.
        </p>
      <% end %>
    </section>
    """
  end

  defp env_reading(assigns) do
    ~H"""
    <div class="arkea-env-reading">
      <span class="arkea-env-reading__label">{@label}</span>
      <span class="arkea-env-reading__value">{@value}</span>
    </div>
    """
  end

  defp topology_modal(assigns) do
    owner =
      case assigns.sim_state.owner_player_id do
        nil -> "wild"
        owner_id -> short_id(owner_id)
      end

    assigns = assign(assigns, owner: owner)

    ~H"""
    <%!-- The dialog ships with `phx-update="ignore"` so LiveView's
         per-tick DOM morph never touches the open modal — without this
         flag, the next `:biotope_tick` (~2s) would re-render the
         dialog's children, the browser would close the modal, and
         the dialog's pending-close state could leave the page
         inert. The metadata shown here is per-biotope immutable
         (id, zone, coords, owner, neighbour ids) so freezing the
         content after first mount is safe. --%>
    <dialog id="topology-modal" class="arkea-modal" phx-update="ignore">
      <div class="arkea-modal__box arkea-modal-box">
        <form method="dialog" class="arkea-modal__close-form">
          <button
            type="submit"
            class="arkea-button arkea-button--ghost arkea-button--sm arkea-button--icon-only arkea-modal__close"
            aria-label="Close"
          >
            <span class="arkea-button__icon hero-x-mark" aria-hidden="true"></span>
            <span class="arkea-button__label arkea-sr-only">Close</span>
          </button>
        </form>
        <div class="arkea-card__eyebrow mb-1">Topology</div>
        <h3 class="arkea-card__title mb-4">Network-facing metadata</h3>

        <div class="arkea-topology-grid">
          <.env_reading label="biotope" value={short_id(@sim_state.id)} />
          <.env_reading label="zone" value={phase_label(@sim_state.zone)} />
          <.env_reading
            label="coords"
            value={format_float(@sim_state.x, 1) <> ", " <> format_float(@sim_state.y, 1)}
          />
          <.env_reading label="owner" value={@owner} />
        </div>

        <div class="mt-3">
          <div class="arkea-card__eyebrow mb-2">Neighbor ids ({length(@sim_state.neighbor_ids)})</div>
          <%= if @sim_state.neighbor_ids == [] do %>
            <p class="arkea-muted">No migration edge attached yet.</p>
          <% else %>
            <div class="arkea-token-cloud">
              <span :for={nid <- @sim_state.neighbor_ids} class="arkea-token arkea-token--ghost">
                {short_id(nid)}
              </span>
            </div>
          <% end %>
        </div>
      </div>
    </dialog>
    """
  end

  defp operator_content(assigns) do
    phase_actions_disabled =
      not assigns.intervention_status.owner? or
        not assigns.intervention_status.allowed? or
        is_nil(assigns.selected_phase_name)

    biotope_actions_disabled =
      not assigns.intervention_status.owner? or not assigns.intervention_status.allowed?

    assigns =
      assign(assigns,
        phase_actions_disabled: phase_actions_disabled,
        biotope_actions_disabled: biotope_actions_disabled
      )

    ~H"""
    <div>
      <div class="arkea-operator-status mb-3">
        <%= cond do %>
          <% not @intervention_status.owner? -> %>
            <span class="arkea-token arkea-token--ghost">Read-only · not owner</span>
          <% @intervention_status.allowed? -> %>
            <span class="arkea-token">Slot open · {phase_label(@selected_phase_name)}</span>
          <% true -> %>
            <span class="arkea-token arkea-token--ghost">
              Locked {format_duration(@intervention_status.remaining_seconds)}
            </span>
        <% end %>
      </div>

      <div class="arkea-action-grid">
        <.arkea_button
          variant="primary"
          phx-click="apply_intervention"
          phx-value-kind="nutrient_pulse"
          disabled={@phase_actions_disabled}
          phx-confirm={"Pulse nutrients into #{phase_label(@selected_phase_name)}?"}
          disable_with="Applying…"
        >
          Pulse nutrients
        </.arkea_button>
        <.arkea_button
          variant="primary"
          phx-click="apply_intervention"
          phx-value-kind="plasmid_inoculation"
          disabled={@phase_actions_disabled}
          phx-confirm={"Inoculate plasmid into #{phase_label(@selected_phase_name)}?"}
          disable_with="Applying…"
        >
          Inoculate plasmid
        </.arkea_button>
        <.arkea_button
          variant="primary"
          phx-click="apply_intervention"
          phx-value-kind="mixing_event"
          phx-value-scope="biotope"
          disabled={@biotope_actions_disabled}
          phx-confirm="Trigger mixing event for the whole biotope?"
          disable_with="Applying…"
          class="arkea-action-button--wide"
        >
          Trigger mixing event
        </.arkea_button>
      </div>

      <%= if @operator_error do %>
        <p class="arkea-muted mt-3">{@operator_error}</p>
      <% end %>

      <%= if @operator_log != [] do %>
        <div class="mt-3">
          <div class="arkea-card__eyebrow mb-2">Recent interventions</div>
          <table class="arkea-table">
            <thead>
              <tr>
                <th>Kind</th>
                <th>Scope</th>
                <th>Tick</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={entry <- @operator_log}>
                <td style="font-size: var(--text-sm)">{entry.kind}</td>
                <td style="font-size: var(--text-sm); color: var(--sim-muted)">{entry.scope}</td>
                <td style="font-size: var(--text-sm); font-variant-numeric: tabular-nums; color: var(--sim-muted)">
                  {entry.tick || "?"}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  defp lineage_table(assigns) do
    lineages =
      case assigns.lineage_sort do
        :growth ->
          Enum.sort_by(
            assigns.sim_state.lineages,
            fn l ->
              phenotype = Map.get(assigns.phenotype_cache, l.id)
              if phenotype, do: phenotype.base_growth_rate, else: 0.0
            end,
            :desc
          )

        :repair ->
          Enum.sort_by(
            assigns.sim_state.lineages,
            fn l ->
              phenotype = Map.get(assigns.phenotype_cache, l.id)
              if phenotype, do: phenotype.repair_efficiency, else: 0.0
            end,
            :desc
          )

        :born ->
          Enum.sort_by(assigns.sim_state.lineages, & &1.created_at_tick, :asc)

        _ ->
          Enum.sort_by(assigns.sim_state.lineages, &Lineage.total_abundance/1, :desc)
      end

    max_abundance =
      lineages |> Enum.map(&Lineage.total_abundance/1) |> Enum.max(fn -> 1 end) |> max(1)

    selected_id = assigns[:selected_lineage_id]

    assigns =
      assign(assigns,
        sorted_lineages: lineages,
        max_abundance: max_abundance,
        selected_id: selected_id
      )

    ~H"""
    <section class="arkea-card">
      <div class="arkea-card__header">
        <div>
          <div class="arkea-card__eyebrow">Lineages</div>
          <h2 class="arkea-card__title">Population board</h2>
        </div>
        <div class="arkea-card__meta">{length(@sorted_lineages)}</div>
      </div>

      <div class="overflow-x-auto">
        <table class="arkea-table">
          <thead>
            <tr>
              <th>ID</th>
              <th>Cluster</th>
              <th>Phase</th>
              <th>
                <.arkea_button
                  variant="ghost"
                  size="sm"
                  phx-click="sort_lineages"
                  phx-value-by="abundance"
                  aria-pressed={@lineage_sort == :abundance}
                >
                  N {if @lineage_sort == :abundance, do: "↓"}
                </.arkea_button>
              </th>
              <th>
                <.arkea_button
                  variant="ghost"
                  size="sm"
                  phx-click="sort_lineages"
                  phx-value-by="growth"
                  aria-pressed={@lineage_sort == :growth}
                >
                  µ (h⁻¹) {if @lineage_sort == :growth, do: "↓"}
                </.arkea_button>
              </th>
              <th>
                <.arkea_button
                  variant="ghost"
                  size="sm"
                  phx-click="sort_lineages"
                  phx-value-by="repair"
                  aria-pressed={@lineage_sort == :repair}
                >
                  ε {if @lineage_sort == :repair, do: "↓"}
                </.arkea_button>
              </th>
              <th>
                <.arkea_button
                  variant="ghost"
                  size="sm"
                  phx-click="sort_lineages"
                  phx-value-by="born"
                  aria-pressed={@lineage_sort == :born}
                >
                  Born {if @lineage_sort == :born, do: "↑"}
                </.arkea_button>
              </th>
            </tr>
          </thead>
          <tbody>
            <%= if @sorted_lineages == [] do %>
              <tr>
                <td colspan="7" class="arkea-table__empty">No lineages present.</td>
              </tr>
            <% else %>
              <.lineage_row
                :for={lineage <- @sorted_lineages}
                lineage={lineage}
                phenotype_cache={@phenotype_cache}
                max_abundance={@max_abundance}
                selected_id={@selected_id}
              />
            <% end %>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  defp lineage_row(assigns) do
    lineage = assigns.lineage
    phenotype = Map.get(assigns.phenotype_cache, lineage.id)
    abundance = Lineage.total_abundance(lineage)
    pct = Float.round(min(abundance / assigns.max_abundance * 100.0, 100.0), 1)

    cluster = phenotype_cluster(phenotype)
    cluster_color = cluster_badge_color(cluster)

    assigns =
      assign(assigns,
        short_id: short_id(lineage.id),
        abundance: abundance,
        pct: pct,
        growth_str: (phenotype && format_float(phenotype.base_growth_rate, 2)) || "—",
        repair_str: (phenotype && format_float(phenotype.repair_efficiency, 2)) || "—",
        color: lineage_color(lineage.id, phenotype),
        cluster: cluster,
        cluster_color: cluster_color,
        dominant_phase: dominant_phase_label(lineage),
        is_selected: assigns[:selected_id] == lineage.id
      )

    ~H"""
    <tr
      phx-click="select_lineage"
      phx-value-id={@lineage.id}
      class={["arkea-lineage-row", @is_selected && "arkea-lineage-row--selected"]}
      style="height: 2rem; cursor: pointer;"
    >
      <td style="padding: 0.45rem 0.5rem;">
        <div class="arkea-lineage-id">
          <span class="arkea-lineage-swatch" style={"background: #{@color}"}></span>
          <span class="arkea-lineage-id__main">{@short_id}</span>
        </div>
      </td>
      <td style="padding: 0.45rem 0.5rem;">
        <span class={"badge badge-xs #{@cluster_color}"}>{@cluster}</span>
      </td>
      <td style="padding: 0.45rem 0.5rem; color: var(--sim-muted); font-size: var(--text-sm);">
        {@dominant_phase}
      </td>
      <td style="padding: 0.45rem 0.5rem;">
        <div class="arkea-abundance-bar">
          <div class="arkea-abundance-bar__track" style="min-width: 3rem;">
            <div class="arkea-abundance-bar__fill" style={"width: #{@pct}%; background: #{@color}"} />
          </div>
          <span class="arkea-abundance-bar__value" style="font-size: var(--text-sm);">
            {@abundance}
          </span>
        </div>
      </td>
      <td style="padding: 0.45rem 0.5rem; font-variant-numeric: tabular-nums; font-size: var(--text-sm);">
        {@growth_str}
      </td>
      <td style="padding: 0.45rem 0.5rem; font-variant-numeric: tabular-nums; font-size: var(--text-sm);">
        {@repair_str}
      </td>
      <td style="padding: 0.45rem 0.5rem; font-variant-numeric: tabular-nums; font-size: var(--text-sm); color: var(--sim-muted);">
        {@lineage.created_at_tick}
      </td>
    </tr>
    """
  end

  defp chemistry_panel(assigns) do
    chem = chemistry_matrix(assigns.sim_state)
    assigns = assign(assigns, chem: chem)

    ~H"""
    <section class="arkea-card">
      <div class="arkea-card__header">
        <div>
          <div class="arkea-card__eyebrow">Chemistry</div>
          <h2 class="arkea-card__title">Metabolite pools</h2>
        </div>
        <div class="arkea-card__meta">
          {length(@sim_state.phases)} phases × {length(@chem.metabolites)} metabolites
        </div>
      </div>

      <%= if @chem.rows == [] do %>
        <p class="arkea-muted">No phase pools available.</p>
      <% else %>
        <div class="overflow-x-auto">
          <table class="arkea-heatmap">
            <thead>
              <tr>
                <th></th>
                <th :for={m <- @chem.metabolites}>{met_abbr(m)}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @chem.rows}>
                <td>{phase_label(row.phase)}</td>
                <td
                  :for={{conc, max_c} <- Enum.zip(row.concentrations, @chem.max_per_met)}
                  class="arkea-heatmap__cell"
                  style={"--fill: #{Float.round(if(max_c > 0, do: conc / max_c, else: 0.0), 2)}"}
                >
                  {if conc > 0, do: format_μm(conc)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="arkea-token-cloud mt-3">
          <span :for={phase <- @sim_state.phases} class="arkea-token arkea-token--ghost">
            <span class="arkea-token__label">{phase_label(phase.name)}</span>
            <span class="arkea-token__value">
              sig {round_metric(sum_pool(phase.signal_pool))} · phage {round_metric(
                sum_phage_pool(phase.phage_pool)
              )}
            </span>
          </span>
        </div>
      <% end %>
    </section>
    """
  end

  attr :samples, :list, required: true
  attr :audit, :list, required: true

  defp trends_panel(assigns) do
    ~H"""
    <div class="arkea-trends">
      <div class="arkea-trends__intro">
        <span class="arkea-card__eyebrow">Population trajectory</span>
        <p class="arkea-muted">
          Per-lineage abundance sampled every {Arkea.Persistence.TimeSeries.sampling_period()} ticks.
          Vertical markers flag <code>mass_lysis</code>, <code>mutation_notable</code>, <code>phage_burst</code>,
          <code>colonization</code>
          and player <code>intervention</code>
          events.
        </p>
      </div>

      <Chart.population_trajectory_from_samples
        samples={@samples}
        audit={@audit}
      />
    </div>
    """
  end

  attr :model, :any, required: true

  defp phylogeny_panel(assigns) do
    ~H"""
    <div class="arkea-trends">
      <div class="arkea-trends__intro">
        <span class="arkea-card__eyebrow">Phylogeny</span>
        <p class="arkea-muted">
          Lineage genealogy. Each circle is a lineage, coloured by current
          abundance (extinct lineages are grey + dashed). Edges carry the
          most-impactful phenotype delta extracted from the <code>lineage_born</code> audit payload.
        </p>
      </div>

      <%= if @model do %>
        <Phylogeny.phylogeny_default model={@model} />
      <% else %>
        <p class="arkea-muted">Loading phylogeny…</p>
      <% end %>
    </div>
    """
  end

  defp event_log_content(assigns) do
    ~H"""
    <div>
      <%= if @event_log == [] do %>
        <p class="arkea-muted">Awaiting broadcast events from the biotope server.</p>
      <% else %>
        <div class="space-y-1" id="event-log-scroll" phx-hook="EventLogScroll">
          <.event_entry :for={event <- @event_log} event={event} />
        </div>
      <% end %>
    </div>
    """
  end

  defp event_entry(assigns) do
    {icon_class, tone, label, short_lineage, tick} = format_event(assigns.event)

    assigns =
      assign(assigns,
        icon_class: icon_class,
        tone: tone,
        label: label,
        short_lineage: short_lineage,
        tick: tick
      )

    ~H"""
    <div class="arkea-event-entry" style="padding: 0.5rem 0.75rem;">
      <span class={[
        "arkea-event-entry__icon w-4 h-4 flex-shrink-0",
        "arkea-event-entry__icon--#{@tone}"
      ]}>
        <span class={@icon_class}></span>
      </span>
      <div class="arkea-event-entry__body">
        <div class="arkea-event-entry__label">{@label}</div>
        <div class="arkea-event-entry__meta">
          tick {@tick}
          <%= if @short_lineage != "" do %>
            · {@short_lineage}
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp load_initial_state(biotope_id) do
    state = BiotopeServer.get_state(biotope_id)
    cache = build_phenotype_cache(state.lineages)
    {state, cache}
  rescue
    _ -> {nil, %{}}
  end

  defp page_title(nil, biotope_id), do: "Arkea Biotope · #{short_id(biotope_id || "")}"

  defp page_title(%BiotopeState{} = state, _biotope_id) do
    "Arkea Biotope · " <> phase_label(state.archetype)
  end

  defp assign_scene_snapshot(%{assigns: %{sim_state: nil}} = socket) do
    assign(socket, scene_layout: SceneLayout.build(%{phases: [], lineages: []}))
  end

  defp assign_scene_snapshot(socket) do
    snapshot =
      build_scene_snapshot(
        socket.assigns.sim_state,
        socket.assigns.phenotype_cache,
        socket.assigns.selected_phase_name
      )

    assign(socket, scene_layout: SceneLayout.build(snapshot))
  end

  defp build_scene_snapshot(%BiotopeState{} = state, phenotype_cache, selected_phase_name) do
    %{
      biotope_id: state.id,
      tick: state.tick_count,
      archetype: phase_label(state.archetype),
      selected_phase: atom_to_string(selected_phase_name),
      phases:
        Enum.map(state.phases, fn phase ->
          %{
            name: Atom.to_string(phase.name),
            label: phase_label(phase.name),
            color: phase_color(phase.name),
            temperature: round_metric(phase.temperature),
            ph: round_metric(phase.ph),
            osmolarity: round_metric(phase.osmolarity),
            dilution_rate: round_metric(phase.dilution_rate),
            total_abundance: phase_population(state.lineages, phase.name),
            lineage_count: phase_richness(state.lineages, phase.name),
            metabolite_load: round_metric(sum_pool(phase.metabolite_pool)),
            signal_load: round_metric(sum_pool(phase.signal_pool)),
            phage_load: round_metric(sum_phage_pool(phase.phage_pool))
          }
        end),
      lineages:
        Enum.map(Enum.sort_by(state.lineages, &Lineage.total_abundance/1, :desc), fn lineage ->
          phenotype = Map.get(phenotype_cache, lineage.id)

          %{
            id: lineage.id,
            short_id: short_id(lineage.id),
            total_abundance: Lineage.total_abundance(lineage),
            cluster: phenotype_cluster(phenotype),
            color: lineage_color(lineage.id, phenotype),
            phase_abundance: stringify_phase_map(lineage.abundance_by_phase)
          }
        end)
    }
  end

  defp update_phenotype_cache(cache, %BiotopeState{lineages: lineages}) do
    current_ids = MapSet.new(lineages, & &1.id)
    pruned = Map.filter(cache, fn {id, _} -> MapSet.member?(current_ids, id) end)

    Enum.reduce(lineages, pruned, fn lineage, acc ->
      if Map.has_key?(acc, lineage.id) or is_nil(lineage.genome) do
        acc
      else
        Map.put(acc, lineage.id, Phenotype.from_genome(lineage.genome))
      end
    end)
  end

  defp build_phenotype_cache(lineages) do
    lineages
    |> Enum.reject(&is_nil(&1.genome))
    |> Map.new(fn lineage -> {lineage.id, Phenotype.from_genome(lineage.genome)} end)
  end

  defp prepend_events(log, new_events), do: (new_events ++ log) |> Enum.take(@max_event_log)

  defp prepend_operator_log(log, entry), do: [entry | log] |> Enum.take(@max_operator_log)

  defp default_intervention_status do
    %{allowed?: false, owner?: false, retry_at: nil, remaining_seconds: 0, last_kind: nil}
  end

  defp intervention_status(_player, nil), do: default_intervention_status()

  defp intervention_status(player, biotope_id) do
    PlayerInterventions.status(player.id, biotope_id)
  rescue
    _ -> default_intervention_status()
  end

  defp format_event(%{type: :lineage_born, payload: %{lineage_id: id, tick: tick}}) do
    {"hero-plus-circle", "green", "Lineage born", short_id(id), tick}
  end

  defp format_event(%{type: :lineage_extinct, payload: %{lineage_id: id, tick: tick}}) do
    {"hero-minus-circle", "red", "Lineage extinct", short_id(id), tick}
  end

  defp format_event(%{type: :hgt_transfer, payload: %{lineage_id: id, tick: tick}}) do
    {"hero-arrows-right-left", "amber", "Horizontal transfer", short_id(id), tick}
  end

  defp format_event(%{type: :intervention, payload: payload}) do
    kind = Map.get(payload, :kind) || Map.get(payload, "kind") || "intervention"
    lineage_id = Map.get(payload, :lineage_id) || Map.get(payload, "lineage_id") || ""
    tick = Map.get(payload, :tick) || Map.get(payload, "tick") || "?"
    {"hero-beaker", "teal", intervention_label(kind), short_id(lineage_id), tick}
  end

  defp format_event(%{type: type, payload: payload}) do
    {"hero-ellipsis-horizontal", "slate", phase_label(type),
     short_id(Map.get(payload, :lineage_id, "")), Map.get(payload, :tick, "?")}
  end

  defp intervention_command(%{"kind" => kind} = params, selected_phase_name) do
    with {:ok, parsed_kind} <- parse_intervention_kind(kind),
         {:ok, scope} <- parse_intervention_scope(Map.get(params, "scope", "phase")) do
      command =
        %{kind: parsed_kind, scope: scope}
        |> maybe_put_phase_name(scope, selected_phase_name)

      if scope == :phase and is_nil(Map.get(command, :phase_name)) do
        {:error, :invalid_phase}
      else
        {:ok, command}
      end
    end
  end

  defp parse_intervention_kind("nutrient_pulse"), do: {:ok, :nutrient_pulse}
  defp parse_intervention_kind("plasmid_inoculation"), do: {:ok, :plasmid_inoculation}
  defp parse_intervention_kind("mixing_event"), do: {:ok, :mixing_event}
  defp parse_intervention_kind(_kind), do: {:error, :unknown_intervention}

  defp parse_intervention_scope("biotope"), do: {:ok, :biotope}
  defp parse_intervention_scope("phase"), do: {:ok, :phase}
  defp parse_intervention_scope(nil), do: {:ok, :phase}
  defp parse_intervention_scope(_scope), do: {:error, :unknown_scope}

  defp maybe_put_phase_name(command, :phase, phase_name) when is_atom(phase_name) do
    Map.put(command, :phase_name, phase_name)
  end

  defp maybe_put_phase_name(command, _scope, _phase_name), do: command

  defp operator_entry(command, %{payload: payload}) do
    scope =
      case Map.get(command, :scope, :phase) do
        :biotope -> "Whole biotope"
        _ -> phase_label(Map.get(command, :phase_name))
      end

    %{
      id: System.unique_integer([:positive]),
      kind: intervention_label(Map.get(payload, :kind) || Map.get(payload, "kind")),
      scope: scope,
      tick: Map.get(payload, :tick) || Map.get(payload, "tick")
    }
  end

  defp intervention_error_message(:forbidden),
    do: "This biotope is not controlled by the current player."

  defp intervention_error_message(:budget_locked),
    do: "Intervention budget locked for this biotope."

  defp intervention_error_message(:invalid_phase),
    do: "The selected phase is no longer available."

  defp intervention_error_message(:no_lineage_host),
    do:
      "The focused phase has no live lineage that can host the inoculated plasmid. " <>
        "Click a phase that contains at least one lineage (check the count chip in the sidebar) and retry."

  defp intervention_error_message(:persistence_failed),
    do: "The intervention executed, but its budget record could not be persisted."

  defp intervention_error_message(reason) when is_atom(reason),
    do: "Intervention failed: #{reason |> Atom.to_string() |> humanize_string()}."

  defp selected_phase(%BiotopeState{phases: phases}, phase_name) do
    Enum.find(phases, &(&1.name == phase_name)) || List.first(phases)
  end

  defp resolve_selected_phase(current_phase_name, nil), do: current_phase_name

  defp resolve_selected_phase(current_phase_name, %BiotopeState{phases: phases}) do
    available = MapSet.new(phases, & &1.name)

    cond do
      current_phase_name && MapSet.member?(available, current_phase_name) -> current_phase_name
      phases == [] -> nil
      true -> hd(phases).name
    end
  end

  defp find_phase_name(nil, _phase_name), do: nil

  defp find_phase_name(%BiotopeState{phases: phases}, phase_name) when is_binary(phase_name) do
    Enum.find_value(phases, fn phase ->
      if Atom.to_string(phase.name) == phase_name, do: phase.name, else: nil
    end)
  end

  defp phase_population(lineages, phase_name) when is_atom(phase_name) do
    Enum.sum_by(lineages, &Lineage.abundance_in(&1, phase_name))
  end

  defp phase_richness(lineages, phase_name) when is_atom(phase_name) do
    Enum.count(lineages, &(Lineage.abundance_in(&1, phase_name) > 0))
  end

  defp sorted_phase_abundances(%Lineage{} = lineage) do
    Enum.sort_by(lineage.abundance_by_phase, fn {_phase_name, count} -> count end, :desc)
  end

  defp dominant_phase_label(%Lineage{} = lineage) do
    case sorted_phase_abundances(lineage) do
      [{phase_name, _count} | _] -> phase_label(phase_name)
      [] -> "depleted"
    end
  end

  defp stringify_phase_map(map) when is_map(map) do
    Map.new(map, fn {phase_name, count} -> {Atom.to_string(phase_name), count} end)
  end

  defp sum_pool(map) when is_map(map), do: Enum.sum(Map.values(map))

  defp sum_phage_pool(map) when is_map(map) do
    map
    |> Map.values()
    |> Enum.reduce(0, fn %Arkea.Sim.HGT.Virion{abundance: a}, acc -> acc + a end)
  end

  defp short_id(""), do: ""
  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)

  defp nav_items, do: Shell.nav_items(:none)

  defp bottom_tabs do
    [
      {:events, "Events"},
      {:lineages, "Lineages"},
      {:trends, "Trends"},
      {:phylogeny, "Phylogeny"},
      {:chemistry, "Chemistry"},
      {:interventions, "Interventions"}
    ]
  end

  # Lazily load the time-series + audit data the first time the user
  # opens the Trends tab. The result is cached in `socket.assigns.trends`
  # so subsequent tab switches reuse it; the next tick that hits a
  # sampling boundary will refresh via the `:biotope_tick` PubSub
  # broadcast (see handle_info/2).
  defp maybe_load_trends_data(socket, :trends) do
    biotope_id = socket.assigns.biotope_id

    samples =
      Arkea.Persistence.TimeSeries.list(biotope_id, kind: "abundance")

    audit = recent_audit(biotope_id)
    assign(socket, trends_samples: samples, trends_audit: audit)
  end

  defp maybe_load_trends_data(socket, _other), do: socket

  # Build the phylogeny model from the live BiotopeState plus the
  # `lineage_born` audit entries (which carry the per-edge mutation
  # summary). Cached on the socket and rebuilt on tab activation only —
  # the lineage tree changes infrequently enough that re-deriving on
  # every tick would be wasteful.
  defp maybe_load_phylogeny_data(socket, :phylogeny) do
    biotope_id = socket.assigns.biotope_id
    sim_state = socket.assigns.sim_state

    # We render only currently-alive lineages: after a few thousand
    # ticks the audit log carries enough extinct shells to clutter
    # the dendrogram beyond legibility. The `:extinct_lineages`
    # option of `Phylogeny.build/3` is still available for callers
    # that want the cumulative history (audit-driven exports,
    # post-hoc analysis); the live tab keeps the surface lean.
    audit = lineage_born_audit(biotope_id)
    lineages = if sim_state, do: sim_state.lineages, else: []
    model = Arkea.Views.Phylogeny.build(lineages, audit)

    assign(socket, phylogeny_model: model)
  end

  defp maybe_load_phylogeny_data(socket, _other), do: socket

  defp recent_audit(biotope_id) do
    import Ecto.Query

    Arkea.Repo.all(
      from a in Arkea.Persistence.AuditLog,
        where: a.target_biotope_id == ^biotope_id,
        order_by: [asc: a.occurred_at_tick],
        limit: 200
    )
  end

  defp lineage_born_audit(biotope_id) do
    import Ecto.Query

    Arkea.Repo.all(
      from a in Arkea.Persistence.AuditLog,
        where: a.target_biotope_id == ^biotope_id and a.event_type == "lineage_born",
        order_by: [asc: a.occurred_at_tick]
    )
  end

  defp format_surface_tags([]), do: "—"

  defp format_surface_tags(tags) when is_list(tags) do
    tags |> Enum.take(4) |> Enum.map_join(" · ", &humanize_string(Atom.to_string(&1)))
  end

  defp phase_label(nil), do: "unassigned"

  defp phase_label(value) when is_atom(value) do
    value |> Atom.to_string() |> humanize_string()
  end

  @phase_colors %{
    surface: "#f59e0b",
    water_column: "#22d3ee",
    sediment: "#c2410c",
    biofilm: "#84cc16",
    soil: "#65a30d",
    pore_water: "#14b8a6",
    air: "#f8fafc",
    host: "#fb7185"
  }

  @fallback_colors ["#38bdf8", "#fb7185", "#f97316", "#a3e635", "#facc15"]

  defp phase_color(phase_name) do
    Map.get_lazy(@phase_colors, phase_name, fn ->
      Enum.at(@fallback_colors, rem(:erlang.phash2(phase_name), length(@fallback_colors)))
    end)
  end

  defp phenotype_cluster(nil), do: "cryptic"

  defp phenotype_cluster(%Phenotype{} = phenotype) do
    cond do
      Enum.any?(phenotype.surface_tags, &(&1 in [:adhesin, :matrix, :biofilm])) ->
        "biofilm"

      phenotype.n_transmembrane >= 2 ->
        "motile"

      phenotype.repair_efficiency + phenotype.structural_stability >= 1.35 ->
        "stress-tolerant"

      true ->
        "generalist"
    end
  end

  defp lineage_color(lineage_id, phenotype) do
    palette =
      case phenotype_cluster(phenotype) do
        "biofilm" -> ["#f59e0b", "#eab308", "#84cc16", "#f97316"]
        "motile" -> ["#22d3ee", "#14b8a6", "#38bdf8", "#0ea5e9"]
        "stress-tolerant" -> ["#fb7185", "#ef4444", "#f97316", "#f43f5e"]
        "generalist" -> ["#cbd5e1", "#94a3b8", "#60a5fa", "#a3e635"]
        _ -> ["#e7e5e4", "#fde68a", "#d6d3d1", "#cbd5e1"]
      end

    Enum.at(palette, rem(:erlang.phash2(lineage_id), length(palette)))
  end

  defp intervention_label("nutrient_pulse"), do: "Nutrient pulse"
  defp intervention_label("plasmid_inoculation"), do: "Plasmid inoculation"
  defp intervention_label("mixing_event"), do: "Mixing event"
  defp intervention_label(kind) when is_binary(kind), do: humanize_string(kind)

  defp recolonize_error_message(:not_extinct),
    do: "Recolonization is only allowed when the home biotope is extinct."

  defp recolonize_error_message(:no_home),
    do: "No locked home biotope is associated with this player."

  defp recolonize_error_message(:biotope_missing),
    do: "The home biotope process is no longer running on this node."

  defp recolonize_error_message(:blueprint_unreadable),
    do: "The persisted blueprint could not be decoded; recolonization aborted."

  defp recolonize_error_message(other),
    do: "Recolonization failed: #{inspect(other)}."

  defp atom_to_string(nil), do: ""
  defp atom_to_string(value) when is_atom(value), do: Atom.to_string(value)

  defp format_float(value, decimals) when is_integer(value),
    do: format_float(value * 1.0, decimals)

  defp format_float(value, decimals) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: decimals)

  defp format_duration(seconds) when is_integer(seconds) and seconds >= 0 do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}m #{String.pad_leading(Integer.to_string(secs), 2, "0")}s"
  end

  defp humanize_string(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp round_metric(value) when is_integer(value), do: value
  defp round_metric(value) when is_float(value), do: Float.round(value, 2)

  @metabolites ~w[glucose acetate lactate oxygen no3 so4 h2s nh3 h2 po4 co2 ch4 iron]a

  defp chemistry_matrix(%BiotopeState{phases: []}) do
    # Empty biotope: short-circuit to avoid Enum.max/1 on []. The template
    # already guards `@chem.rows == []`, so callers stay happy.
    %{rows: [], metabolites: @metabolites, max_per_met: List.duplicate(0.0, length(@metabolites))}
  end

  defp chemistry_matrix(%BiotopeState{phases: phases}) do
    rows =
      Enum.map(phases, fn phase ->
        concs = Enum.map(@metabolites, fn m -> Map.get(phase.metabolite_pool, m, 0.0) end)
        %{phase: phase.name, concentrations: concs}
      end)

    max_per_met =
      Enum.map(0..(length(@metabolites) - 1), fn i ->
        rows
        |> Enum.map(&Enum.at(&1.concentrations, i))
        |> Enum.max(fn -> 0.0 end)
      end)

    %{rows: rows, metabolites: @metabolites, max_per_met: max_per_met}
  end

  defp shannon_diversity([], _phase_name), do: 0.0

  defp shannon_diversity(lineages, phase_name) do
    counts = Enum.map(lineages, &Lineage.abundance_in(&1, phase_name))
    total = Enum.sum(counts)

    if total == 0 do
      0.0
    else
      counts
      |> Enum.filter(&(&1 > 0))
      |> Enum.map(fn c ->
        p = c / total
        -p * :math.log(p)
      end)
      |> Enum.sum()
      |> Float.round(2)
    end
  end

  @met_abbrs %{
    glucose: "Glc",
    acetate: "Ace",
    lactate: "Lac",
    oxygen: "O₂",
    no3: "NO₃",
    so4: "SO₄",
    h2s: "H₂S",
    nh3: "NH₃",
    h2: "H₂",
    po4: "PO₄",
    co2: "CO₂",
    ch4: "CH₄",
    iron: "Fe"
  }

  defp met_abbr(metabolite), do: Map.get(@met_abbrs, metabolite, to_string(metabolite))

  defp format_μm(value) when is_float(value) and value >= 1000.0,
    do: "#{:erlang.float_to_binary(value / 1000.0, decimals: 1)}m"

  defp format_μm(value) when is_float(value) and value >= 0.1,
    do: :erlang.float_to_binary(value, decimals: 1)

  defp format_μm(value) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: 2)

  defp format_μm(value) when is_integer(value), do: format_μm(value * 1.0)

  defp format_compact(n) when n >= 1_000_000,
    do: "#{Float.round(n / 1_000_000.0, 1)}M"

  defp format_compact(n) when n >= 1_000,
    do: "#{Float.round(n / 1_000.0, 1)}k"

  defp format_compact(n), do: to_string(n)

  @archetype_colors %{
    eutrophic_pond: "#22c55e",
    oligotrophic_lake: "#38bdf8",
    mesophilic_soil: "#a16207",
    methanogenic_bog: "#7c3aed",
    saline_estuary: "#0891b2",
    marine_sediment: "#1d4ed8",
    hydrothermal_vent: "#dc2626",
    acid_mine_drainage: "#ca8a04"
  }

  defp archetype_color(archetype) do
    Map.get(@archetype_colors, archetype, "#94a3b8")
  end

  defp cluster_badge_color("biofilm"), do: "badge-warning"
  defp cluster_badge_color("motile"), do: "badge-info"
  defp cluster_badge_color("stress-tolerant"), do: "badge-error"
  defp cluster_badge_color("generalist"), do: "badge-neutral"
  defp cluster_badge_color(_), do: "badge-ghost"
end
