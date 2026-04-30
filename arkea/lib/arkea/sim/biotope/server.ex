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

  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Tick

  # ---------------------------------------------------------------------------
  # Public API

  @doc """
  Start a `Biotope.Server` for the given `BiotopeState`.

  Typically called via `Biotope.Supervisor.start_biotope/1`.
  """
  @spec start_link(BiotopeState.t()) :: GenServer.on_start()
  def start_link(%BiotopeState{} = initial_state) do
    name = via(initial_state.id)
    GenServer.start_link(__MODULE__, initial_state, name: name)
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

    Phoenix.PubSub.broadcast(
      Arkea.PubSub,
      "biotope:#{state.id}",
      {:biotope_tick, new_state, events}
    )

    new_state
  end

  defp via(id) do
    {:via, Registry, {Arkea.Sim.Registry, {:biotope, id}}}
  end
end
