defmodule ArkeaWeb.SimLive do
  @moduledoc """
  Detailed LiveView viewport for one authoritative biotope.

  The simulation remains server-authoritative: this module subscribes to the
  selected `"biotope:<id>"`, receives `{:biotope_tick, new_state, events}` from
  `Arkea.Sim.Biotope.Server`, and turns the current `BiotopeState` into:

    - a LiveView dashboard for operator-facing telemetry
    - a PixiJS snapshot consumed by a `phx-hook` for the procedural 2D scene

  No tick logic runs here. The browser scene is a pure visualization derived
  from per-phase authoritative state, consistent with DESIGN.md Blocks 12 and 14.
  """

  use ArkeaWeb, :live_view

  alias Arkea.Ecology.Lineage
  alias Arkea.Game.PlayerInterventions
  alias Arkea.Sim.Biotope.Server, as: BiotopeServer
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Phenotype
  alias ArkeaWeb.GameChrome

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
       scene_snapshot_json: "{}",
       not_found?: false,
       lineage_sort: :abundance,
       bottom_tab: :events,
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

    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def handle_params(%{"id" => biotope_id}, _uri, socket) do
    if Phoenix.LiveView.connected?(socket) and socket.assigns.biotope_id != biotope_id do
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
    sort = if field in ~w[abundance growth repair born], do: String.to_existing_atom(field), else: :abundance
    {:noreply, assign(socket, lineage_sort: sort)}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab_atom = if tab == "interventions", do: :interventions, else: :events
    {:noreply, assign(socket, bottom_tab: tab_atom)}
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
    ~H"""
    <div class="sim-shell" data-selected-phase={atom_to_string(@selected_phase_name)}>
      <div class="sim-shell__grid"></div>
      <div class="sim-shell__content">
        <GameChrome.top_nav
          active={:biotope}
          player_name={@player.display_name}
          biotope_label={biotope_nav_label(@sim_state, @biotope_id)}
        />

        <%= cond do %>
          <% @not_found? -> %>
            <.missing_view biotope_id={@biotope_id} />
          <% is_nil(@sim_state) -> %>
            <.loading_view />
          <% true -> %>
            <div class="biotope-shell">
              <.biotope_header
                sim_state={@sim_state}
                running={@running}
                intervention_status={@intervention_status}
              />

              <div class="biotope-grid">
                <div class="biotope-canvas-col">
                  <.scene_panel
                    sim_state={@sim_state}
                    selected_phase_name={@selected_phase_name}
                    scene_snapshot_json={@scene_snapshot_json}
                  />
                </div>

                <div class="biotope-right-col">
                  <.phase_inspector
                    sim_state={@sim_state}
                    selected_phase_name={@selected_phase_name}
                  />
                  <.lineage_table
                    sim_state={@sim_state}
                    phenotype_cache={@phenotype_cache}
                    lineage_sort={@lineage_sort}
                  />
                  <.chemistry_panel sim_state={@sim_state} />
                  <.bottom_tabs
                    event_log={@event_log}
                    operator_log={@operator_log}
                    operator_error={@operator_error}
                    intervention_status={@intervention_status}
                    selected_phase_name={@selected_phase_name}
                    active_tab={@bottom_tab}
                  />
                </div>
              </div>

              <.topology_modal sim_state={@sim_state} />
            </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp loading_view(assigns) do
    ~H"""
    <div class="sim-loading mt-6">
      <span class="loading loading-dots loading-lg text-primary"></span>
      <h2 class="sim-loading__title">Loading biotope viewport</h2>
      <p class="sim-loading__copy">
        Waiting for the authoritative biotope process to publish its first state.
      </p>
    </div>
    """
  end

  defp missing_view(assigns) do
    ~H"""
    <div class="sim-loading mt-6">
      <h2 class="sim-loading__title">Biotope not found</h2>
      <p class="sim-loading__copy">
        No active `Biotope.Server` is registered for {@biotope_id || "this route"}.
      </p>
      <div class="world-cta-stack">
        <.link href={~p"/world"} class="sim-action-button sim-action-button--wide">
          Return to world overview
        </.link>
        <.link href={~p"/seed-lab"} class="sim-action-button sim-action-button--wide">
          Open seed lab
        </.link>
      </div>
    </div>
    """
  end

  defp biotope_header(assigns) do
    total_population = BiotopeState.total_abundance(assigns.sim_state)
    lineage_count = length(assigns.sim_state.lineages)
    phase_count = length(assigns.sim_state.phases)
    budget_label = if assigns.intervention_status.allowed?, do: "open", else: "locked"

    assigns =
      assign(assigns,
        total_population: total_population,
        lineage_count: lineage_count,
        phase_count: phase_count,
        budget_label: budget_label
      )

    ~H"""
    <header class="biotope-header">
      <span
        class="biotope-header__dot"
        style={"background: #{archetype_color(@sim_state.archetype)}"}
      ></span>
      <span class="biotope-header__name">{phase_label(@sim_state.archetype)}</span>
      <div class="biotope-header__chips">
        <.header_chip label="tick" value={@sim_state.tick_count} tone="gold" />
        <.header_chip label="lineages" value={@lineage_count} tone="teal" />
        <.header_chip label="N" value={format_compact(@total_population)} tone="teal" />
        <.header_chip label="phases" value={@phase_count} tone="slate" />
        <.header_chip label="stream" value={if(@running, do: "live", else: "shell")} tone={if @running, do: "green", else: "amber"} />
        <.header_chip label="budget" value={@budget_label} tone={if @intervention_status.allowed?, do: "green", else: "amber"} />
      </div>
      <button
        type="button"
        class="biotope-header__detail-btn"
        onclick="document.getElementById('topology-modal').showModal()"
        title="Topology details"
      >
        <span class="hero-cog-6-tooth w-4 h-4"></span>
      </button>
    </header>
    """
  end

  defp header_chip(assigns) do
    ~H"""
    <span class={["sim-header-chip", "sim-header-chip--#{@tone}"]}>
      <span class="sim-header-chip__label">{@label}</span>
      <span class="sim-header-chip__value">{@value}</span>
    </span>
    """
  end

  defp scene_panel(assigns) do
    ~H"""
    <section class="sim-card sim-scene-card" style="flex: 1; min-height: 0; display: flex; flex-direction: column;">
      <div
        class="sim-scene-frame"
        style="flex: 1; min-height: 0;"
        title="Procedural render derived from authoritative phase aggregates. Click a band to select the phase."
      >
        <div
          id="biotope-scene"
          class="sim-scene-canvas"
          phx-hook="BiotopeScene"
          phx-update="ignore"
          data-biotope-snapshot={@scene_snapshot_json}
        >
        </div>
      </div>

      <div class="sim-phase-tabs--inline">
        <button
          :for={phase <- @sim_state.phases}
          type="button"
          phx-click="select_phase"
          phx-value-phase={Atom.to_string(phase.name)}
          class={["sim-phase-tab--inline", @selected_phase_name == phase.name && "active"]}
          data-phase={Atom.to_string(phase.name)}
        >
          <span class="sim-phase-tab__swatch" style={"background: #{phase_color(phase.name)}"}></span>
          <span class="label">{phase_label(phase.name)}</span>
          <span class="meta">
            T {format_float(phase.temperature, 1)}°C &nbsp;pH {format_float(phase.ph, 1)} &nbsp;N {format_compact(phase_population(@sim_state.lineages, phase.name))}
          </span>
        </button>
      </div>
    </section>
    """
  end

  defp phase_inspector(assigns) do
    phase = selected_phase(assigns.sim_state, assigns.selected_phase_name)
    phase_lineages = phase && Enum.filter(assigns.sim_state.lineages, &(Lineage.abundance_in(&1, phase.name) > 0))
    total_population = phase && phase_population(assigns.sim_state.lineages, phase.name)
    richness = phase && length(phase_lineages)
    shannon = phase && shannon_diversity(phase_lineages, phase.name)
    phage_load = phase && round_metric(sum_pool(phase.phage_pool))

    assigns =
      assign(assigns,
        phase: phase,
        total_population: total_population,
        richness: richness,
        shannon: shannon,
        phage_load: phage_load
      )

    ~H"""
    <section class="sim-card">
      <%= if @phase do %>
        <div class="sim-card__header">
          <div>
            <div class="sim-card__eyebrow">Focused phase</div>
            <h2 id="phase-inspector-title" class="sim-card__title">{phase_label(@phase.name)}</h2>
          </div>
          <div class="sim-phase-mark" style={"background: #{phase_color(@phase.name)}"}></div>
        </div>

        <div class="sim-phase-kpis">
          <div class="sim-mini-stat">
            <span class="sim-mini-stat__label">N</span>
            <span class="sim-mini-stat__value">{format_compact(@total_population)}</span>
          </div>
          <div class="sim-mini-stat">
            <span class="sim-mini-stat__label">richness</span>
            <span class="sim-mini-stat__value">{@richness}</span>
          </div>
          <div class="sim-mini-stat">
            <span class="sim-mini-stat__label">H′ (Shannon)</span>
            <span class="sim-mini-stat__value">{@shannon}</span>
          </div>
          <div class="sim-mini-stat">
            <span class="sim-mini-stat__label">phages</span>
            <span class="sim-mini-stat__value">{@phage_load}</span>
          </div>
        </div>

        <div class="sim-phase-environment">
          <.env_reading label="T (°C)" value={format_float(@phase.temperature, 1)} />
          <.env_reading label="pH" value={format_float(@phase.ph, 1)} />
          <.env_reading label="Osm (mOsm/L)" value={format_float(@phase.osmolarity, 0)} />
          <.env_reading label="D (%/tick)" value={format_float(@phase.dilution_rate * 100.0, 1)} />
        </div>
      <% else %>
        <div class="sim-card__header">
          <div>
            <div class="sim-card__eyebrow">Focused phase</div>
            <h2 id="phase-inspector-title" class="sim-card__title">No phase available</h2>
          </div>
        </div>
        <p class="sim-muted">
          This biotope does not currently expose any authoritative phase pocket.
        </p>
      <% end %>
    </section>
    """
  end

  defp env_reading(assigns) do
    ~H"""
    <div class="sim-env-reading">
      <span class="sim-env-reading__label">{@label}</span>
      <span class="sim-env-reading__value">{@value}</span>
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
    <dialog id="topology-modal" class="modal">
      <div class="modal-box biotope-modal" style="background: var(--sim-panel); border: 1px solid var(--sim-panel-border);">
        <form method="dialog">
          <button class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2">✕</button>
        </form>
        <div class="sim-card__eyebrow mb-1">Topology</div>
        <h3 class="sim-card__title mb-4">Network-facing metadata</h3>

        <div class="sim-topology-grid">
          <.env_reading label="biotope" value={short_id(@sim_state.id)} />
          <.env_reading label="zone" value={phase_label(@sim_state.zone)} />
          <.env_reading
            label="coords"
            value={format_float(@sim_state.x, 1) <> ", " <> format_float(@sim_state.y, 1)}
          />
          <.env_reading label="owner" value={@owner} />
        </div>

        <div class="mt-3">
          <div class="sim-card__eyebrow mb-2">Neighbor ids ({length(@sim_state.neighbor_ids)})</div>
          <%= if @sim_state.neighbor_ids == [] do %>
            <p class="sim-muted">No migration edge attached yet.</p>
          <% else %>
            <div class="sim-token-cloud">
              <span :for={nid <- @sim_state.neighbor_ids} class="sim-token sim-token--ghost">
                {short_id(nid)}
              </span>
            </div>
          <% end %>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop"><button>close</button></form>
    </dialog>
    """
  end

  defp bottom_tabs(assigns) do
    ~H"""
    <section class="sim-card biotope-bottom-tabs">
      <div role="tablist" class="tabs tabs-box">
        <button
          role="tab"
          class={["tab", @active_tab == :events && "tab-active"]}
          phx-click="switch_tab"
          phx-value-tab="events"
        >
          Events
        </button>
        <button
          role="tab"
          class={["tab", @active_tab == :interventions && "tab-active"]}
          phx-click="switch_tab"
          phx-value-tab="interventions"
        >
          Interventions
        </button>
      </div>

      <div class="mt-3">
        <%= if @active_tab == :events do %>
          <.event_log_content event_log={@event_log} />
        <% else %>
          <.operator_content
            selected_phase_name={@selected_phase_name}
            operator_log={@operator_log}
            operator_error={@operator_error}
            intervention_status={@intervention_status}
          />
        <% end %>
      </div>
    </section>
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
      <div class="sim-operator-status mb-3">
        <%= cond do %>
          <% not @intervention_status.owner? -> %>
            <span class="sim-token sim-token--ghost">Read-only · not owner</span>
          <% @intervention_status.allowed? -> %>
            <span class="sim-token">Slot open · {phase_label(@selected_phase_name)}</span>
          <% true -> %>
            <span class="sim-token sim-token--ghost">
              Locked {format_duration(@intervention_status.remaining_seconds)}
            </span>
        <% end %>
      </div>

      <div class="sim-action-grid">
        <button
          type="button"
          class="sim-action-button"
          phx-click="apply_intervention"
          phx-value-kind="nutrient_pulse"
          disabled={@phase_actions_disabled}
          phx-confirm={"Pulse nutrients into #{phase_label(@selected_phase_name)}?"}
        >
          Pulse nutrients
        </button>
        <button
          type="button"
          class="sim-action-button"
          phx-click="apply_intervention"
          phx-value-kind="plasmid_inoculation"
          disabled={@phase_actions_disabled}
          phx-confirm={"Inoculate plasmid into #{phase_label(@selected_phase_name)}?"}
        >
          Inoculate plasmid
        </button>
        <button
          type="button"
          class="sim-action-button sim-action-button--wide"
          phx-click="apply_intervention"
          phx-value-kind="mixing_event"
          phx-value-scope="biotope"
          disabled={@biotope_actions_disabled}
          phx-confirm="Trigger mixing event for the whole biotope?"
        >
          Trigger mixing event
        </button>
      </div>

      <%= if @operator_error do %>
        <p class="sim-muted mt-3">{@operator_error}</p>
      <% end %>

      <%= if @operator_log != [] do %>
        <div class="mt-3">
          <div class="sim-card__eyebrow mb-2">Recent interventions</div>
          <table class="sim-table">
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
                <td style="font-size: var(--text-sm); font-variant-numeric: tabular-nums; color: var(--sim-muted)">{entry.tick || "?"}</td>
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
          Enum.sort_by(assigns.sim_state.lineages, fn l ->
            phenotype = Map.get(assigns.phenotype_cache, l.id)
            if phenotype, do: phenotype.base_growth_rate, else: 0.0
          end, :desc)
        :repair ->
          Enum.sort_by(assigns.sim_state.lineages, fn l ->
            phenotype = Map.get(assigns.phenotype_cache, l.id)
            if phenotype, do: phenotype.repair_efficiency, else: 0.0
          end, :desc)
        :born ->
          Enum.sort_by(assigns.sim_state.lineages, & &1.created_at_tick, :asc)
        _ ->
          Enum.sort_by(assigns.sim_state.lineages, &Lineage.total_abundance/1, :desc)
      end

    max_abundance =
      lineages |> Enum.map(&Lineage.total_abundance/1) |> Enum.max(fn -> 1 end) |> max(1)

    assigns = assign(assigns, sorted_lineages: lineages, max_abundance: max_abundance)

    ~H"""
    <section class="sim-card">
      <div class="sim-card__header">
        <div>
          <div class="sim-card__eyebrow">Lineages</div>
          <h2 class="sim-card__title">Population board</h2>
        </div>
        <div class="sim-card__meta">{length(@sorted_lineages)}</div>
      </div>

      <div class="overflow-x-auto" style="max-height: 20rem; overflow-y: auto;">
        <table class="sim-table">
          <thead>
            <tr>
              <th>ID</th>
              <th>Cluster</th>
              <th>Phase</th>
              <th>
                <button type="button" phx-click="sort_lineages" phx-value-by="abundance">
                  N <%= if @lineage_sort == :abundance, do: "↓" %>
                </button>
              </th>
              <th>
                <button type="button" phx-click="sort_lineages" phx-value-by="growth">
                  µ (h⁻¹) <%= if @lineage_sort == :growth, do: "↓" %>
                </button>
              </th>
              <th>
                <button type="button" phx-click="sort_lineages" phx-value-by="repair">
                  ε <%= if @lineage_sort == :repair, do: "↓" %>
                </button>
              </th>
              <th>
                <button type="button" phx-click="sort_lineages" phx-value-by="born">
                  Born <%= if @lineage_sort == :born, do: "↑" %>
                </button>
              </th>
            </tr>
          </thead>
          <tbody>
            <%= if @sorted_lineages == [] do %>
              <tr>
                <td colspan="7" class="sim-table__empty">No lineages present.</td>
              </tr>
            <% else %>
              <.lineage_row
                :for={lineage <- @sorted_lineages}
                lineage={lineage}
                phenotype_cache={@phenotype_cache}
                max_abundance={@max_abundance}
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
        dominant_phase: dominant_phase_label(lineage)
      )

    ~H"""
    <tr style="height: 2rem;">
      <td style="padding: 0.45rem 0.5rem;">
        <div class="sim-lineage-id">
          <span class="sim-lineage-swatch" style={"background: #{@color}"}></span>
          <span class="sim-lineage-id__main">{@short_id}</span>
        </div>
      </td>
      <td style="padding: 0.45rem 0.5rem;">
        <span class={"badge badge-xs #{@cluster_color}"}>{@cluster}</span>
      </td>
      <td style="padding: 0.45rem 0.5rem; color: var(--sim-muted); font-size: var(--text-sm);">
        {@dominant_phase}
      </td>
      <td style="padding: 0.45rem 0.5rem;">
        <div class="sim-abundance-bar">
          <div class="sim-abundance-bar__track" style="min-width: 3rem;">
            <div class="sim-abundance-bar__fill" style={"width: #{@pct}%; background: #{@color}"} />
          </div>
          <span class="sim-abundance-bar__value" style="font-size: var(--text-sm);">{@abundance}</span>
        </div>
      </td>
      <td style="padding: 0.45rem 0.5rem; font-variant-numeric: tabular-nums; font-size: var(--text-sm);">{@growth_str}</td>
      <td style="padding: 0.45rem 0.5rem; font-variant-numeric: tabular-nums; font-size: var(--text-sm);">{@repair_str}</td>
      <td style="padding: 0.45rem 0.5rem; font-variant-numeric: tabular-nums; font-size: var(--text-sm); color: var(--sim-muted);">{@lineage.created_at_tick}</td>
    </tr>
    """
  end

  defp chemistry_panel(assigns) do
    chem = chemistry_matrix(assigns.sim_state)
    assigns = assign(assigns, chem: chem)

    ~H"""
    <section class="sim-card">
      <div class="sim-card__header">
        <div>
          <div class="sim-card__eyebrow">Chemistry</div>
          <h2 class="sim-card__title">Metabolite pools</h2>
        </div>
        <div class="sim-card__meta">{length(@sim_state.phases)} phases × {length(@chem.metabolites)} metabolites</div>
      </div>

      <%= if @chem.rows == [] do %>
        <p class="sim-muted">No phase pools available.</p>
      <% else %>
        <div class="overflow-x-auto">
          <table class="sim-heatmap">
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
                  class="sim-heatmap__cell"
                  style={"--fill: #{Float.round(if(max_c > 0, do: conc / max_c, else: 0.0), 2)}"}
                >
                  {if conc > 0, do: format_μm(conc)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="sim-token-cloud mt-3">
          <span :for={phase <- @sim_state.phases} class="sim-token sim-token--ghost">
            <span class="sim-token__label">{phase_label(phase.name)}</span>
            <span class="sim-token__value">
              sig {round_metric(sum_pool(phase.signal_pool))} · phage {round_metric(sum_pool(phase.phage_pool))}
            </span>
          </span>
        </div>
      <% end %>
    </section>
    """
  end

  defp event_log_content(assigns) do
    ~H"""
    <div>
      <%= if @event_log == [] do %>
        <p class="sim-muted">Awaiting broadcast events from the biotope server.</p>
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
    <div class="sim-event-entry" style="padding: 0.5rem 0.75rem;">
      <span class={["sim-event-entry__icon w-4 h-4 flex-shrink-0", "sim-event-entry__icon--#{@tone}"]}>
        <span class={@icon_class}></span>
      </span>
      <div class="sim-event-entry__body">
        <div class="sim-event-entry__label">{@label}</div>
        <div class="sim-event-entry__meta">
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

  defp biotope_nav_label(nil, biotope_id), do: "Biotope " <> short_id(biotope_id || "")

  defp biotope_nav_label(%BiotopeState{} = state, _biotope_id) do
    phase_label(state.archetype)
  end

  defp assign_scene_snapshot(%{assigns: %{sim_state: nil}} = socket) do
    assign(socket, scene_snapshot_json: "{}")
  end

  defp assign_scene_snapshot(socket) do
    snapshot =
      build_scene_snapshot(
        socket.assigns.sim_state,
        socket.assigns.phenotype_cache,
        socket.assigns.selected_phase_name
      )

    socket = assign(socket, scene_snapshot_json: Jason.encode!(snapshot))

    if Phoenix.LiveView.connected?(socket) do
      push_event(socket, "biotope_snapshot", snapshot)
    else
      socket
    end
  end

  defp build_scene_snapshot(%BiotopeState{} = state, phenotype_cache, selected_phase_name) do
    %{
      "biotopeId" => state.id,
      "tick" => state.tick_count,
      "archetype" => phase_label(state.archetype),
      "selectedPhase" => atom_to_string(selected_phase_name),
      "phases" =>
        Enum.map(state.phases, fn phase ->
          %{
            "name" => Atom.to_string(phase.name),
            "label" => phase_label(phase.name),
            "color" => phase_color(phase.name),
            "temperature" => round_metric(phase.temperature),
            "ph" => round_metric(phase.ph),
            "osmolarity" => round_metric(phase.osmolarity),
            "dilutionRate" => round_metric(phase.dilution_rate),
            "totalAbundance" => phase_population(state.lineages, phase.name),
            "lineageCount" => phase_richness(state.lineages, phase.name),
            "metaboliteLoad" => round_metric(sum_pool(phase.metabolite_pool)),
            "signalLoad" => round_metric(sum_pool(phase.signal_pool)),
            "phageLoad" => round_metric(sum_pool(phase.phage_pool))
          }
        end),
      "lineages" =>
        Enum.map(Enum.sort_by(state.lineages, &Lineage.total_abundance/1, :desc), fn lineage ->
          phenotype = Map.get(phenotype_cache, lineage.id)

          %{
            "id" => lineage.id,
            "shortId" => short_id(lineage.id),
            "totalAbundance" => Lineage.total_abundance(lineage),
            "cluster" => phenotype_cluster(phenotype),
            "color" => lineage_color(lineage.id, phenotype),
            "phaseAbundance" => stringify_phase_map(lineage.abundance_by_phase)
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
    do: "No suitable lineage host is present in the focused phase."

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

  defp short_id(""), do: ""
  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)

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

  defp chemistry_matrix(%BiotopeState{phases: phases}) do
    rows =
      Enum.map(phases, fn phase ->
        concs = Enum.map(@metabolites, fn m -> Map.get(phase.metabolite_pool, m, 0.0) end)
        %{phase: phase.name, concentrations: concs}
      end)

    max_per_met =
      Enum.map(0..(length(@metabolites) - 1), fn i ->
        rows |> Enum.map(&Enum.at(&1.concentrations, i)) |> Enum.max()
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
