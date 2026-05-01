defmodule ArkeaWeb.SimLive do
  @moduledoc """
  LiveView that displays the default biotope simulation in real time.

  Subscribes to `"biotope:<id>"` via Phoenix.PubSub and re-renders on every
  `{:biotope_tick, new_state, events}` broadcast from `Biotope.Server`.

  ## Assigns

    - `:biotope_id` — fixed UUID of the default scenario biotope.
    - `:sim_state` — `BiotopeState.t()` or `nil` before the first tick.
    - `:phenotype_cache` — `%{lineage_id => Phenotype.t()}`, avoids recomputing
      phenotypes for lineages that have not changed genomes since the last tick.
    - `:event_log` — last 20 events (`:lineage_born`, `:lineage_extinct`).
    - `:running` — `true` when the LiveView is connected to PubSub.

  ## Pure-tick discipline

  This module contains only UI logic. It does not call any simulation functions
  — it receives pre-computed state from `Biotope.Server` via PubSub, consistent
  with the IMPLEMENTATION-PLAN.md §4.1 pure-tick discipline.
  """

  use ArkeaWeb, :live_view

  alias Arkea.Ecology.Lineage
  alias Arkea.Sim.Biotope.Server, as: BiotopeServer
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Phenotype

  @default_biotope_id "00000000-0000-0000-0000-000000000001"
  @max_event_log 20

  # ---------------------------------------------------------------------------
  # Lifecycle

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    biotope_id = @default_biotope_id

    {sim_state, phenotype_cache} =
      if Phoenix.LiveView.connected?(socket) do
        Phoenix.PubSub.subscribe(Arkea.PubSub, "biotope:#{biotope_id}")
        load_initial_state(biotope_id)
      else
        {nil, %{}}
      end

    socket =
      assign(socket,
        biotope_id: biotope_id,
        sim_state: sim_state,
        phenotype_cache: phenotype_cache,
        event_log: [],
        running: true,
        page_title: "Arkea Simulation"
      )

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # PubSub handler

  @impl Phoenix.LiveView
  def handle_info({:biotope_tick, new_state, events}, socket) do
    cache = update_phenotype_cache(socket.assigns.phenotype_cache, new_state)
    log = prepend_events(socket.assigns.event_log, events)

    socket =
      assign(socket,
        sim_state: new_state,
        phenotype_cache: cache,
        event_log: log
      )

    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Render

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-950 text-gray-100 font-mono p-4">
      <%= if is_nil(@sim_state) do %>
        <.loading_view />
      <% else %>
        <.sim_header sim_state={@sim_state} />
        <div class="flex gap-4 mt-4">
          <div class="w-[65%]">
            <.lineage_table sim_state={@sim_state} phenotype_cache={@phenotype_cache} />
          </div>
          <div class="w-[35%] flex flex-col gap-4">
            <.event_log_panel event_log={@event_log} />
            <.metabolite_panel sim_state={@sim_state} />
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Sub-components

  defp loading_view(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center h-64 gap-4">
      <span class="loading loading-dots loading-lg text-primary"></span>
      <p class="text-gray-400 text-sm">Initializing simulation...</p>
    </div>
    """
  end

  defp sim_header(assigns) do
    total = BiotopeState.total_abundance(assigns.sim_state)
    lineage_count = length(assigns.sim_state.lineages)

    assigns =
      assign(assigns,
        total_population: total,
        lineage_count: lineage_count
      )

    ~H"""
    <div class="bg-gray-900 border border-gray-700 rounded p-3 flex items-center gap-6">
      <span class="text-green-400 font-bold tracking-wider">ARKEA SIMULATION</span>
      <span class="text-gray-400">
        Tick <span class="text-yellow-300 font-bold">#{@sim_state.tick_count}</span>
      </span>
      <span class="text-gray-400">
        Lineages <span class="text-blue-300 font-bold">{@lineage_count}</span>
      </span>
      <span class="text-gray-400">
        Population <span class="text-cyan-300 font-bold">{@total_population}</span>
      </span>
      <span class="text-gray-400">
        Biotope <span class="text-gray-300">{@sim_state.archetype}</span>
      </span>
    </div>
    """
  end

  defp lineage_table(assigns) do
    lineages = assigns.sim_state.lineages

    max_abundance =
      if lineages == [],
        do: 1,
        else: Enum.max_by(lineages, &Lineage.total_abundance/1) |> Lineage.total_abundance()

    max_abundance = max(max_abundance, 1)

    sorted =
      Enum.sort_by(lineages, &Lineage.total_abundance/1, :desc)

    assigns = assign(assigns, sorted_lineages: sorted, max_abundance: max_abundance)

    ~H"""
    <div class="bg-gray-900 border border-gray-700 rounded">
      <div class="px-3 py-2 border-b border-gray-700 text-gray-400 text-xs uppercase tracking-wider">
        Lineages — sorted by abundance
      </div>
      <div class="overflow-x-auto">
        <table class="w-full text-xs">
          <thead>
            <tr class="text-gray-500 border-b border-gray-800">
              <th class="text-left px-3 py-2 w-20">ID</th>
              <th class="text-left px-3 py-2 w-16">Parent</th>
              <th class="text-left px-3 py-2">Abundance</th>
              <th class="text-right px-3 py-2 w-20">Growth</th>
              <th class="text-right px-3 py-2 w-20">Repair</th>
              <th class="text-right px-3 py-2 w-12">Plas.</th>
              <th class="text-right px-3 py-2 w-16">Tick born</th>
            </tr>
          </thead>
          <tbody>
            <%= if @sorted_lineages == [] do %>
              <tr>
                <td colspan="7" class="text-center text-gray-600 py-8">No lineages</td>
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
    </div>
    """
  end

  defp lineage_row(assigns) do
    lineage = assigns.lineage
    phenotype = Map.get(assigns.phenotype_cache, lineage.id)
    abundance = Lineage.total_abundance(lineage)
    pct = Float.round(min(abundance / assigns.max_abundance * 100.0, 100.0), 1)

    short_id = String.slice(lineage.id, 0, 8)

    short_parent =
      case lineage.parent_id do
        nil -> "seed"
        pid -> String.slice(pid, 0, 8)
      end

    growth_str =
      if phenotype,
        do: :erlang.float_to_binary(phenotype.base_growth_rate, decimals: 2),
        else: "—"

    repair_str =
      if phenotype,
        do: :erlang.float_to_binary(phenotype.repair_efficiency, decimals: 2),
        else: "—"

    plasmid_count = if lineage.genome, do: length(lineage.genome.plasmids), else: 0
    plasmid_str = if plasmid_count > 0, do: to_string(plasmid_count), else: "—"

    row_class =
      if plasmid_count > 0,
        do: "border-b border-gray-800 hover:bg-gray-800 bg-orange-950/20 transition-colors",
        else: "border-b border-gray-800 hover:bg-gray-800 transition-colors"

    assigns =
      assign(assigns,
        short_id: short_id,
        short_parent: short_parent,
        abundance: abundance,
        pct: pct,
        growth_str: growth_str,
        repair_str: repair_str,
        plasmid_str: plasmid_str,
        row_class: row_class
      )

    ~H"""
    <tr class={@row_class}>
      <td class="px-3 py-1 text-green-400">{@short_id}</td>
      <td class="px-3 py-1 text-gray-500">{@short_parent}</td>
      <td class="px-3 py-1">
        <div class="flex items-center gap-2">
          <div class="flex-1 bg-gray-800 rounded h-3 overflow-hidden min-w-[60px]">
            <div
              class="h-full bg-cyan-600 rounded transition-all duration-500"
              style={"width: #{@pct}%"}
            />
          </div>
          <span class="text-cyan-300 w-12 text-right">{@abundance}</span>
        </div>
      </td>
      <td class="px-3 py-1 text-right text-yellow-300">{@growth_str}</td>
      <td class="px-3 py-1 text-right text-purple-300">{@repair_str}</td>
      <td class="px-3 py-1 text-right text-orange-300">{@plasmid_str}</td>
      <td class="px-3 py-1 text-right text-gray-500">{@lineage.created_at_tick}</td>
    </tr>
    """
  end

  defp event_log_panel(assigns) do
    ~H"""
    <div class="bg-gray-900 border border-gray-700 rounded h-full">
      <div class="px-3 py-2 border-b border-gray-700 text-gray-400 text-xs uppercase tracking-wider">
        Event log (last {length(@event_log)})
      </div>
      <div class="p-2 space-y-1 overflow-y-auto max-h-96">
        <%= if @event_log == [] do %>
          <p class="text-gray-600 text-xs text-center py-4">Awaiting events...</p>
        <% else %>
          <.event_entry :for={event <- @event_log} event={event} />
        <% end %>
      </div>
    </div>
    """
  end

  defp event_entry(assigns) do
    event = assigns.event
    {icon, color, label, short_id, tick} = format_event(event)

    assigns =
      assign(assigns,
        icon: icon,
        color: color,
        label: label,
        short_id: short_id,
        tick: tick
      )

    ~H"""
    <div class="flex items-center gap-2 text-xs py-0.5 border-b border-gray-800">
      <span class={@color}>{@icon}</span>
      <span class="text-gray-500">tick {@tick}</span>
      <span class={@color}>{@label}</span>
      <span class="text-gray-400 truncate">{@short_id}</span>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers

  defp load_initial_state(biotope_id) do
    state = BiotopeServer.get_state(biotope_id)
    cache = build_phenotype_cache(state.lineages)
    {state, cache}
  rescue
    _ -> {nil, %{}}
  end

  defp update_phenotype_cache(cache, %BiotopeState{lineages: lineages}) do
    current_ids = MapSet.new(lineages, & &1.id)

    # Remove entries for extinct lineages
    pruned = Map.filter(cache, fn {id, _} -> MapSet.member?(current_ids, id) end)

    # Add entries for new lineages that have a genome and are not yet cached
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
    |> Enum.reject(fn l -> is_nil(l.genome) end)
    |> Map.new(fn l -> {l.id, Phenotype.from_genome(l.genome)} end)
  end

  defp prepend_events(log, new_events) do
    (new_events ++ log)
    |> Enum.take(@max_event_log)
  end

  defp format_event(%{type: :lineage_born, payload: %{lineage_id: id, tick: tick}}) do
    {"◉", "text-green-400", "Born", String.slice(id, 0, 8), tick}
  end

  defp format_event(%{type: :lineage_extinct, payload: %{lineage_id: id, tick: tick}}) do
    {"○", "text-red-400", "Extinct", String.slice(id, 0, 8), tick}
  end

  defp format_event(%{type: :hgt_transfer, payload: %{lineage_id: id, tick: tick}}) do
    {"⇢", "text-orange-400", "HGT", String.slice(id, 0, 8), tick}
  end

  defp format_event(%{type: type, payload: payload}) do
    tick = Map.get(payload, :tick, "?")
    id = Map.get(payload, :lineage_id, "") |> String.slice(0, 8)
    {"·", "text-gray-500", to_string(type), id, tick}
  end

  defp metabolite_panel(assigns) do
    ~H"""
    <div class="bg-gray-900 border border-gray-700 rounded">
      <div class="px-3 py-2 border-b border-gray-700 text-gray-400 text-xs uppercase tracking-wider">
        Metabolite pools
      </div>
      <div class="p-2 space-y-3 overflow-y-auto max-h-48">
        <%= if @sim_state.phases == [] do %>
          <p class="text-gray-600 text-xs text-center py-2">No phases</p>
        <% else %>
          <.phase_pool :for={phase <- @sim_state.phases} phase={phase} />
        <% end %>
      </div>
    </div>
    """
  end

  defp phase_pool(assigns) do
    top =
      assigns.phase.metabolite_pool
      |> Enum.filter(fn {_k, v} -> v > 0.01 end)
      |> Enum.sort_by(fn {_k, v} -> v end, :desc)
      |> Enum.take(6)

    assigns = assign(assigns, top_metabolites: top)

    ~H"""
    <div>
      <div class="text-gray-500 text-xs mb-1 uppercase tracking-wider">{@phase.name}</div>
      <%= if @top_metabolites == [] do %>
        <span class="text-gray-700 text-xs italic">depleted</span>
      <% else %>
        <div class="flex flex-wrap gap-1">
          <span
            :for={{met, conc} <- @top_metabolites}
            class="inline-flex items-center gap-1 text-xs bg-gray-800 rounded px-1.5 py-0.5"
          >
            <span class="text-teal-400">{met}</span>
            <span class="text-gray-400">{:erlang.float_to_binary(conc, decimals: 1)}</span>
          </span>
        </div>
      <% end %>
    </div>
    """
  end
end
