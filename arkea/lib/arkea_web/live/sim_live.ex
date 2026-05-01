defmodule ArkeaWeb.SimLive do
  @moduledoc """
  LiveView shell for the default biotope simulation.

  The simulation remains server-authoritative: this module subscribes to
  `"biotope:<id>"`, receives `{:biotope_tick, new_state, events}` from
  `Arkea.Sim.Biotope.Server`, and turns the current `BiotopeState` into:

    - a LiveView dashboard for operator-facing telemetry
    - a PixiJS snapshot consumed by a `phx-hook` for the procedural 2D scene

  No tick logic runs here. The browser scene is a pure visualization derived
  from per-phase authoritative state, consistent with DESIGN.md Blocks 12 and 14.
  """

  use ArkeaWeb, :live_view

  alias Arkea.Ecology.Lineage
  alias Arkea.Sim.Biotope.Server, as: BiotopeServer
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Phenotype

  @default_biotope_id "00000000-0000-0000-0000-000000000001"
  @max_event_log 20
  @max_operator_log 8

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    biotope_id = @default_biotope_id

    if Phoenix.LiveView.connected?(socket) do
      Phoenix.PubSub.subscribe(Arkea.PubSub, "biotope:#{biotope_id}")
    end

    {sim_state, phenotype_cache} = load_initial_state(biotope_id)

    socket =
      socket
      |> assign(
        biotope_id: biotope_id,
        sim_state: sim_state,
        phenotype_cache: phenotype_cache,
        selected_phase_name: resolve_selected_phase(nil, sim_state),
        event_log: [],
        operator_log: [],
        running: Phoenix.LiveView.connected?(socket),
        scene_snapshot_json: "{}",
        page_title: "Arkea Biotope"
      )
      |> assign_scene_snapshot()

    {:ok, socket}
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
        running: true
      )
      |> assign_scene_snapshot()

    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

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

  def handle_event("queue_intervention", %{"kind" => kind} = params, socket) do
    scope =
      case Map.get(params, "scope", "phase") do
        "biotope" -> "whole biotope"
        _ -> phase_label(socket.assigns.selected_phase_name)
      end

    entry = %{
      id: System.unique_integer([:positive]),
      kind: intervention_label(kind),
      scope: scope,
      tick: socket.assigns.sim_state && socket.assigns.sim_state.tick_count
    }

    {:noreply,
     assign(socket, operator_log: prepend_operator_log(socket.assigns.operator_log, entry))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="sim-shell" data-selected-phase={atom_to_string(@selected_phase_name)}>
      <div class="sim-shell__aurora sim-shell__aurora--west"></div>
      <div class="sim-shell__aurora sim-shell__aurora--east"></div>
      <div class="sim-shell__grid"></div>
      <div class="sim-shell__content">
        <%= if is_nil(@sim_state) do %>
          <.loading_view />
        <% else %>
          <.sim_header sim_state={@sim_state} running={@running} />

          <div class="sim-main-grid mt-6">
            <.scene_panel
              sim_state={@sim_state}
              selected_phase_name={@selected_phase_name}
              scene_snapshot_json={@scene_snapshot_json}
            />

            <div class="sim-sidebar">
              <.phase_inspector
                sim_state={@sim_state}
                selected_phase_name={@selected_phase_name}
              />
              <.topology_panel sim_state={@sim_state} />
              <.operator_panel
                selected_phase_name={@selected_phase_name}
                operator_log={@operator_log}
              />
            </div>
          </div>

          <div class="sim-lower-grid mt-6">
            <.lineage_table sim_state={@sim_state} phenotype_cache={@phenotype_cache} />
            <.chemistry_panel sim_state={@sim_state} />
            <.event_log_panel event_log={@event_log} />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp loading_view(assigns) do
    ~H"""
    <div class="sim-loading">
      <span class="loading loading-dots loading-lg text-primary"></span>
      <h2 class="sim-loading__title">Bootstrapping biotope viewport</h2>
      <p class="sim-loading__copy">
        Waiting for the authoritative biotope process to publish its first state.
      </p>
    </div>
    """
  end

  defp sim_header(assigns) do
    total_population = BiotopeState.total_abundance(assigns.sim_state)
    lineage_count = length(assigns.sim_state.lineages)

    assigns =
      assign(assigns,
        total_population: total_population,
        lineage_count: lineage_count
      )

    ~H"""
    <section class="sim-hero">
      <div>
        <div class="sim-hero__eyebrow">Arkea prototype · phase 9 console</div>
        <h1 class="sim-hero__title">Procedural biotope viewport</h1>
        <p class="sim-hero__copy">
          The canvas is a derived scene. Population, chemistry and migration-facing phases remain authoritative on the server.
        </p>
      </div>

      <div class="sim-stat-strip">
        <.stat_chip label="tick" value={@sim_state.tick_count} tone="gold" />
        <.stat_chip label="lineages" value={@lineage_count} tone="teal" />
        <.stat_chip label="population" value={@total_population} tone="sky" />
        <.stat_chip label="archetype" value={phase_label(@sim_state.archetype)} tone="slate" />
        <.stat_chip label="stream" value={if(@running, do: "live", else: "shell")} tone="amber" />
      </div>
    </section>
    """
  end

  defp stat_chip(assigns) do
    ~H"""
    <div class={["sim-stat-chip", "sim-stat-chip--#{@tone}"]}>
      <span class="sim-stat-chip__label">{@label}</span>
      <span class="sim-stat-chip__value">{@value}</span>
    </div>
    """
  end

  defp scene_panel(assigns) do
    phase_count = length(assigns.sim_state.phases)

    assigns = assign(assigns, phase_count: phase_count)

    ~H"""
    <section class="sim-card sim-scene-card">
      <div class="sim-card__header">
        <div>
          <div class="sim-card__eyebrow">Biotope viewport</div>
          <h2 class="sim-card__title">PixiJS scene hook</h2>
        </div>
        <div class="sim-card__meta">{@phase_count} phase pockets</div>
      </div>

      <div class="sim-scene-frame">
        <div
          id="biotope-scene"
          class="sim-scene-canvas"
          phx-hook="BiotopeScene"
          phx-update="ignore"
          data-biotope-snapshot={@scene_snapshot_json}
        >
        </div>
      </div>

      <div class="sim-phase-tabs">
        <button
          :for={phase <- @sim_state.phases}
          type="button"
          phx-click="select_phase"
          phx-value-phase={Atom.to_string(phase.name)}
          class={[
            "sim-phase-tab",
            @selected_phase_name == phase.name && "sim-phase-tab--active"
          ]}
          data-phase={Atom.to_string(phase.name)}
        >
          <span class="sim-phase-tab__swatch" style={"background: #{phase_color(phase.name)}"}></span>
          <span>{phase_label(phase.name)}</span>
          <span class="sim-phase-tab__count">
            {phase_population(@sim_state.lineages, phase.name)}
          </span>
        </button>
      </div>

      <div class="sim-scene-note">
        Click a rendered band or a phase tab to focus the inspector. Direct cell picking stays intentionally unavailable.
      </div>
    </section>
    """
  end

  defp phase_inspector(assigns) do
    phase = selected_phase(assigns.sim_state, assigns.selected_phase_name)
    total_population = phase && phase_population(assigns.sim_state.lineages, phase.name)
    richness = phase && phase_richness(assigns.sim_state.lineages, phase.name)
    top_metabolites = phase && top_entries(phase.metabolite_pool, 4)
    signal_load = phase && round_metric(sum_pool(phase.signal_pool))
    phage_load = phase && round_metric(sum_pool(phase.phage_pool))

    assigns =
      assign(assigns,
        phase: phase,
        total_population: total_population,
        richness: richness,
        top_metabolites: top_metabolites,
        signal_load: signal_load,
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
            <span class="sim-mini-stat__label">population</span>
            <span class="sim-mini-stat__value">{@total_population}</span>
          </div>
          <div class="sim-mini-stat">
            <span class="sim-mini-stat__label">richness</span>
            <span class="sim-mini-stat__value">{@richness}</span>
          </div>
          <div class="sim-mini-stat">
            <span class="sim-mini-stat__label">signals</span>
            <span class="sim-mini-stat__value">{@signal_load}</span>
          </div>
          <div class="sim-mini-stat">
            <span class="sim-mini-stat__label">phages</span>
            <span class="sim-mini-stat__value">{@phage_load}</span>
          </div>
        </div>

        <div class="sim-phase-environment">
          <.env_reading label="temperature" value={format_float(@phase.temperature, 1) <> " °C"} />
          <.env_reading label="pH" value={format_float(@phase.ph, 1)} />
          <.env_reading label="osmolarity" value={format_float(@phase.osmolarity, 0) <> " mOsm"} />
          <.env_reading label="dilution" value={format_float(@phase.dilution_rate * 100.0, 1) <> "%"} />
        </div>

        <div>
          <div class="sim-card__eyebrow mb-2">Dominant metabolites</div>
          <%= if @top_metabolites == [] do %>
            <p class="sim-muted">No metabolite pool registered for this phase.</p>
          <% else %>
            <div class="sim-token-cloud">
              <span :for={{metabolite, conc} <- @top_metabolites} class="sim-token">
                <span class="sim-token__label">{metabolite}</span>
                <span class="sim-token__value">{format_float(conc, 1)}</span>
              </span>
            </div>
          <% end %>
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

  defp topology_panel(assigns) do
    owner =
      case assigns.sim_state.owner_player_id do
        nil -> "wild"
        owner_id -> short_id(owner_id)
      end

    assigns = assign(assigns, owner: owner)

    ~H"""
    <section class="sim-card">
      <div class="sim-card__header">
        <div>
          <div class="sim-card__eyebrow">Topology</div>
          <h2 class="sim-card__title">Network-facing metadata</h2>
        </div>
        <div class="sim-card__meta">{length(@sim_state.neighbor_ids)} outgoing arcs</div>
      </div>

      <div class="sim-topology-grid">
        <.env_reading label="biotope" value={short_id(@sim_state.id)} />
        <.env_reading label="zone" value={phase_label(@sim_state.zone)} />
        <.env_reading
          label="coords"
          value={format_float(@sim_state.x, 1) <> ", " <> format_float(@sim_state.y, 1)}
        />
        <.env_reading label="owner" value={@owner} />
      </div>

      <div>
        <div class="sim-card__eyebrow mb-2">Neighbor ids</div>
        <%= if @sim_state.neighbor_ids == [] do %>
          <p class="sim-muted">No migration edge is attached to this seed biotope yet.</p>
        <% else %>
          <div class="sim-token-cloud">
            <span :for={neighbor_id <- @sim_state.neighbor_ids} class="sim-token sim-token--ghost">
              {short_id(neighbor_id)}
            </span>
          </div>
        <% end %>
      </div>
    </section>
    """
  end

  defp operator_panel(assigns) do
    ~H"""
    <section class="sim-card">
      <div class="sim-card__header">
        <div>
          <div class="sim-card__eyebrow">Operator console</div>
          <h2 class="sim-card__title">Intervention shell</h2>
        </div>
        <div class="sim-card__meta">{phase_label(@selected_phase_name)}</div>
      </div>

      <p class="sim-muted mb-4">
        UI-only queue for phase-level actions. Simulation mutations stay deferred until persistence and audit plumbing is in place.
      </p>

      <div class="sim-action-grid">
        <button
          type="button"
          class="sim-action-button"
          phx-click="queue_intervention"
          phx-value-kind="antibiotic_dose"
        >
          Dose antibiotic
        </button>
        <button
          type="button"
          class="sim-action-button"
          phx-click="queue_intervention"
          phx-value-kind="plasmid_inoculation"
        >
          Inoculate plasmid
        </button>
        <button
          type="button"
          class="sim-action-button sim-action-button--wide"
          phx-click="queue_intervention"
          phx-value-kind="mixing_event"
          phx-value-scope="biotope"
        >
          Trigger mixing event
        </button>
      </div>

      <div class="mt-4">
        <div class="sim-card__eyebrow mb-2">Queued intents</div>
        <%= if @operator_log == [] do %>
          <p class="sim-muted">No operator intents recorded in this session.</p>
        <% else %>
          <div class="space-y-2">
            <div :for={entry <- @operator_log} class="sim-operator-entry">
              <div>
                <div class="sim-operator-entry__kind">{entry.kind}</div>
                <div class="sim-operator-entry__scope">{entry.scope}</div>
              </div>
              <div class="sim-operator-entry__tick">tick {entry.tick || "?"}</div>
            </div>
          </div>
        <% end %>
      </div>
    </section>
    """
  end

  defp lineage_table(assigns) do
    lineages = Enum.sort_by(assigns.sim_state.lineages, &Lineage.total_abundance/1, :desc)

    max_abundance =
      lineages |> Enum.map(&Lineage.total_abundance/1) |> Enum.max(fn -> 1 end) |> max(1)

    assigns = assign(assigns, sorted_lineages: lineages, max_abundance: max_abundance)

    ~H"""
    <section class="sim-card sim-card--wide">
      <div class="sim-card__header">
        <div>
          <div class="sim-card__eyebrow">Lineages</div>
          <h2 class="sim-card__title">Population board</h2>
        </div>
        <div class="sim-card__meta">sorted by abundance</div>
      </div>

      <div class="overflow-x-auto">
        <table class="sim-table">
          <thead>
            <tr>
              <th>Lineage</th>
              <th>Cluster</th>
              <th>Phase split</th>
              <th>Abundance</th>
              <th>Growth</th>
              <th>Repair</th>
              <th>Plasm.</th>
              <th>Born</th>
            </tr>
          </thead>
          <tbody>
            <%= if @sorted_lineages == [] do %>
              <tr>
                <td colspan="8" class="sim-table__empty">No lineages present.</td>
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
    plasmid_count = if lineage.genome, do: length(lineage.genome.plasmids), else: 0

    assigns =
      assign(assigns,
        short_id: short_id(lineage.id),
        short_parent: short_parent(lineage.parent_id),
        abundance: abundance,
        pct: pct,
        growth_str: (phenotype && format_float(phenotype.base_growth_rate, 2)) || "—",
        repair_str: (phenotype && format_float(phenotype.repair_efficiency, 2)) || "—",
        plasmid_str: if(plasmid_count > 0, do: to_string(plasmid_count), else: "—"),
        color: lineage_color(lineage.id, phenotype),
        cluster: phenotype_cluster(phenotype),
        dominant_phase: dominant_phase_label(lineage)
      )

    ~H"""
    <tr>
      <td>
        <div class="sim-lineage-id">
          <span class="sim-lineage-swatch" style={"background: #{@color}"}></span>
          <div>
            <div class="sim-lineage-id__main">{@short_id}</div>
            <div class="sim-lineage-id__sub">parent {@short_parent}</div>
          </div>
        </div>
      </td>
      <td>
        <div class="sim-cluster-tag">{@cluster}</div>
      </td>
      <td>
        <div class="sim-phase-split">
          <span class="sim-phase-split__dominant">{@dominant_phase}</span>
          <div class="sim-phase-split__chips">
            <span
              :for={{phase_name, count} <- sorted_phase_abundances(@lineage)}
              :if={count > 0}
              class="sim-phase-chip"
            >
              {phase_label(phase_name)} {count}
            </span>
          </div>
        </div>
      </td>
      <td>
        <div class="sim-abundance-bar">
          <div class="sim-abundance-bar__track">
            <div
              class="sim-abundance-bar__fill"
              style={"width: #{@pct}%; background: #{@color}"}
            />
          </div>
          <span class="sim-abundance-bar__value">{@abundance}</span>
        </div>
      </td>
      <td>{@growth_str}</td>
      <td>{@repair_str}</td>
      <td>{@plasmid_str}</td>
      <td>{@lineage.created_at_tick}</td>
    </tr>
    """
  end

  defp chemistry_panel(assigns) do
    ~H"""
    <section class="sim-card">
      <div class="sim-card__header">
        <div>
          <div class="sim-card__eyebrow">Chemistry</div>
          <h2 class="sim-card__title">Phase pools</h2>
        </div>
        <div class="sim-card__meta">{length(@sim_state.phases)} authoritative pockets</div>
      </div>

      <div class="space-y-3">
        <.phase_pool :for={phase <- @sim_state.phases} phase={phase} lineages={@sim_state.lineages} />
      </div>
    </section>
    """
  end

  defp phase_pool(assigns) do
    top_metabolites = top_entries(assigns.phase.metabolite_pool, 4)
    signal_load = round_metric(sum_pool(assigns.phase.signal_pool))
    phage_load = round_metric(sum_pool(assigns.phase.phage_pool))
    abundance = phase_population(assigns.lineages, assigns.phase.name)

    assigns =
      assign(assigns,
        top_metabolites: top_metabolites,
        signal_load: signal_load,
        phage_load: phage_load,
        abundance: abundance
      )

    ~H"""
    <div class="sim-phase-pool">
      <div class="sim-phase-pool__header">
        <div class="sim-phase-pool__title">
          <span class="sim-phase-mark" style={"background: #{phase_color(@phase.name)}"}></span>
          {phase_label(@phase.name)}
        </div>
        <div class="sim-phase-pool__meta">
          N {@abundance} · sig {@signal_load} · phage {@phage_load}
        </div>
      </div>

      <%= if @top_metabolites == [] do %>
        <p class="sim-muted">No metabolite pool tracked.</p>
      <% else %>
        <div class="sim-token-cloud">
          <span :for={{metabolite, conc} <- @top_metabolites} class="sim-token sim-token--ghost">
            <span class="sim-token__label">{metabolite}</span>
            <span class="sim-token__value">{format_float(conc, 1)}</span>
          </span>
        </div>
      <% end %>
    </div>
    """
  end

  defp event_log_panel(assigns) do
    ~H"""
    <section class="sim-card">
      <div class="sim-card__header">
        <div>
          <div class="sim-card__eyebrow">Events</div>
          <h2 class="sim-card__title">Recent simulation log</h2>
        </div>
        <div class="sim-card__meta">last {length(@event_log)}</div>
      </div>

      <%= if @event_log == [] do %>
        <p class="sim-muted">Awaiting broadcast events from the biotope server.</p>
      <% else %>
        <div class="space-y-2">
          <.event_entry :for={event <- @event_log} event={event} />
        </div>
      <% end %>
    </section>
    """
  end

  defp event_entry(assigns) do
    {icon, tone, label, short_lineage, tick} = format_event(assigns.event)

    assigns =
      assign(assigns,
        icon: icon,
        tone: tone,
        label: label,
        short_lineage: short_lineage,
        tick: tick
      )

    ~H"""
    <div class="sim-event-entry">
      <span class={["sim-event-entry__icon", "sim-event-entry__icon--#{@tone}"]}>{@icon}</span>
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

  defp format_event(%{type: :lineage_born, payload: %{lineage_id: id, tick: tick}}) do
    {"◉", "green", "Lineage born", short_id(id), tick}
  end

  defp format_event(%{type: :lineage_extinct, payload: %{lineage_id: id, tick: tick}}) do
    {"○", "red", "Lineage extinct", short_id(id), tick}
  end

  defp format_event(%{type: :hgt_transfer, payload: %{lineage_id: id, tick: tick}}) do
    {"⇢", "amber", "Horizontal transfer", short_id(id), tick}
  end

  defp format_event(%{type: type, payload: payload}) do
    {"·", "slate", phase_label(type), short_id(Map.get(payload, :lineage_id, "")),
     Map.get(payload, :tick, "?")}
  end

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

  defp top_entries(map, limit) when is_map(map) do
    map
    |> Enum.filter(fn {_key, value} -> value > 0 end)
    |> Enum.sort_by(fn {_key, value} -> value end, :desc)
    |> Enum.take(limit)
  end

  defp sum_pool(map) when is_map(map), do: Enum.sum(Map.values(map))

  defp short_parent(nil), do: "seed"
  defp short_parent(parent_id), do: short_id(parent_id)

  defp short_id(""), do: ""
  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)

  defp phase_label(nil), do: "unassigned"

  defp phase_label(value) when is_atom(value) do
    value |> Atom.to_string() |> humanize_string()
  end

  defp phase_color(phase_name) do
    case phase_name do
      :surface ->
        "#f59e0b"

      :water_column ->
        "#22d3ee"

      :sediment ->
        "#c2410c"

      :biofilm ->
        "#84cc16"

      :soil ->
        "#65a30d"

      :pore_water ->
        "#14b8a6"

      :air ->
        "#f8fafc"

      :host ->
        "#fb7185"

      _ ->
        Enum.at(
          ["#38bdf8", "#fb7185", "#f97316", "#a3e635", "#facc15"],
          rem(:erlang.phash2(phase_name), 5)
        )
    end
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

  defp intervention_label("antibiotic_dose"), do: "Antibiotic dose"
  defp intervention_label("plasmid_inoculation"), do: "Plasmid inoculation"
  defp intervention_label("mixing_event"), do: "Mixing event"
  defp intervention_label(kind) when is_binary(kind), do: humanize_string(kind)

  defp atom_to_string(nil), do: ""
  defp atom_to_string(value) when is_atom(value), do: Atom.to_string(value)

  defp format_float(value, decimals) when is_integer(value),
    do: format_float(value * 1.0, decimals)

  defp format_float(value, decimals) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: decimals)

  defp humanize_string(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp round_metric(value) when is_integer(value), do: value
  defp round_metric(value) when is_float(value), do: Float.round(value, 2)
end
