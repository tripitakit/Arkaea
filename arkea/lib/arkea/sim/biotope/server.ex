defmodule Arkea.Sim.Biotope.Server do
  @moduledoc """
  GenServer that owns the in-memory state of one biotope and drives its
  simulation tick (IMPLEMENTATION-PLAN.md §4, Active Record pattern).

  ## State

  The process state is an `Arkea.Sim.BiotopeState.t()`. No other process
  reads or writes this state directly (state ownership rule).

  ## Registration

  Each server registers itself in `Arkea.Sim.Registry` under the key
  `{:biotope, id}` where `id` is `state.id`. This allows address-by-id
  without tracking PIDs:

      {:via, Registry, {Arkea.Sim.Registry, {:biotope, "some-uuid"}}}

  ## Tick subscription

  On `init/1` the server subscribes to the PubSub topic `"world:tick"`.
  `WorldClock` broadcasts `{:tick, tick_number}` every interval; the server
  handles it via `handle_info({:tick, _n}, state)`.

  ## Pure tick discipline

  The tick calculation is delegated to `Arkea.Sim.Tick.tick/1` — a pure
  function. All side-effects happen **after** the pure calculation returns:

    1. Compute `{new_state, events}` = `Tick.tick(state)` — pure, no I/O.
    2. Broadcast `{:biotope_tick, new_state, events}` on `"biotope:<id>"` — PubSub.
    3. (Phase 4+) Persist audit events to `AuditLog`.
    4. (Phase 10) Trigger snapshot if `new_state.tick_count rem 10 == 0`.

  ## Public API

  - `start_link/1` — start under `Biotope.Supervisor`.
  - `get_state/1` — synchronous query of the current `BiotopeState`.
  - `current_tick/1` — convenience for `get_state(id).tick_count`.
  - `manual_tick/1` — trigger one tick synchronously (for tests; bypasses
    WorldClock so tests do not need to wait for the global interval).

  ## Fault tolerance

  `restart: :transient` — a `Biotope.Server` crash is abnormal and should be
  restarted. We use `:transient` rather than `:permanent` because a biotope
  whose state is irrecoverable (e.g. badly corrupted) should not loop-restart
  indefinitely; Phase 10 recovery will reload from the last snapshot instead.

  Until Phase 10 is implemented, a crashed server loses its in-memory state.
  This is documented as a known limitation of Phase 2.
  """

  use GenServer, restart: :transient

  require Logger

  alias Arkea.Persistence.Recovery
  alias Arkea.Persistence.Store
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Intervention
  alias Arkea.Sim.Migration
  alias Arkea.Sim.Tick

  # ---------------------------------------------------------------------------
  # Public API

  @doc """
  Start a `Biotope.Server` for the given `BiotopeState`.

  Typically called via `Biotope.Supervisor.start_biotope/1`.
  """
  @spec start_link(BiotopeState.t()) :: GenServer.on_start()
  def start_link(%BiotopeState{} = initial_state) do
    restored_state = Recovery.resolve_start_state(initial_state)
    name = via(restored_state.id)
    GenServer.start_link(__MODULE__, restored_state, name: name)
  end

  @doc """
  Return the current `BiotopeState` for the biotope with the given id.

  Raises `ArgumentError` if no server for that id is registered.
  """
  @spec get_state(binary()) :: BiotopeState.t()
  def get_state(id) when is_binary(id) do
    GenServer.call(via(id), :get_state)
  end

  @doc """
  Return the current tick count for the biotope with the given id.
  """
  @spec current_tick(binary()) :: non_neg_integer()
  def current_tick(id) when is_binary(id) do
    GenServer.call(via(id), :current_tick)
  end

  @doc """
  Trigger one tick synchronously, bypassing the WorldClock broadcast.

  Intended **only** for integration tests where waiting for the global
  tick interval would make tests slow. Not called in production code paths.
  """
  @spec manual_tick(binary()) :: :ok
  def manual_tick(id) when is_binary(id) do
    GenServer.call(via(id), :manual_tick)
  end

  @doc """
  Apply a Phase 8 migration transfer produced by `Migration.Coordinator`.

  The transfer must target the biotope's current tick; stale transfers are
  rejected to preserve the ordering `local tick -> coordinated migration`.
  """
  @spec apply_migration(binary(), Migration.transfer(), non_neg_integer()) ::
          :ok | {:error, atom()}
  def apply_migration(id, transfer, tick)
      when is_binary(id) and is_map(transfer) and is_integer(tick) and tick >= 0 do
    GenServer.call(via(id), {:apply_migration, transfer, tick})
  end

  @doc """
  Apply an authoritative player intervention outside the pure tick pipeline.
  """
  @spec apply_intervention(binary(), Intervention.command()) ::
          {:ok, %{payload: map(), tick: non_neg_integer()}} | {:error, atom()}
  def apply_intervention(id, command) when is_binary(id) and is_map(command) do
    GenServer.call(via(id), {:apply_intervention, command})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks

  @impl GenServer
  def init(%BiotopeState{id: id} = state) do
    Phoenix.PubSub.subscribe(Arkea.PubSub, "world:tick")
    Logger.debug("Biotope.Server started for #{id}")
    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl GenServer
  def handle_call(:current_tick, _from, state) do
    {:reply, state.tick_count, state}
  end

  @impl GenServer
  def handle_call(:manual_tick, _from, state) do
    new_state = do_tick(state)
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call({:apply_migration, transfer, expected_tick}, _from, state) do
    cond do
      expected_tick != state.tick_count ->
        {:reply, {:error, :stale_tick}, state}

      Migration.empty_transfer?(transfer) ->
        {:reply, :ok, state}

      true ->
        new_state = Migration.apply_transfer(state, transfer)

        events = [
          %{
            type: :migration,
            payload: Map.put(Migration.transfer_summary(transfer), :tick, expected_tick)
          }
        ]

        post_transition(state.id, new_state, events, :migration)
        {:reply, :ok, new_state}
    end
  end

  @impl GenServer
  def handle_call({:apply_intervention, command}, _from, state) do
    case Intervention.apply(state, command) do
      {:ok, new_state, events, payload} ->
        post_transition(state.id, new_state, events, :intervention)
        {:reply, {:ok, %{payload: payload, tick: new_state.tick_count}}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_info({:tick, _n}, state) do
    new_state = do_tick(state)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl GenServer
  def terminate(reason, %BiotopeState{id: id}) do
    Logger.info("Biotope.Server for #{id} terminating: #{inspect(reason)}")
    :ok
  end

  # ---------------------------------------------------------------------------
  # Private helpers

  defp do_tick(state) do
    {new_state, events} = Tick.tick(state)
    post_transition(state.id, new_state, events, :tick)
    new_state
  end

  defp post_transition(id, new_state, events, transition_kind) do
    broadcast_biotope_update(id, new_state, events)
    _ = Store.persist_transition(new_state, events, transition_kind)
  end

  defp broadcast_biotope_update(id, new_state, events) do
    Phoenix.PubSub.broadcast(Arkea.PubSub, "biotope:#{id}", {:biotope_tick, new_state, events})
  end

  defp via(id) do
    {:via, Registry, {Arkea.Sim.Registry, {:biotope, id}}}
  end
end
