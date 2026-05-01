defmodule Arkea.Sim.Migration.Coordinator do
  @moduledoc """
  GenServer that orchestrates Phase 8 migration after each world tick.

  The coordinator subscribes to `"world:tick"`, waits until every migration-
  participating biotope has completed its local pure tick for that tick number,
  then:

  1. fetches their `BiotopeState`
  2. computes a pure migration plan via `Arkea.Sim.Migration.plan/2`
  3. applies the resulting transfers back to the owning `Biotope.Server`

  This keeps inter-biotopo effects outside `Arkea.Sim.Tick`, preserving the
  pure tick boundary mandated by the implementation plan.
  """

  use GenServer

  require Logger

  alias Arkea.Sim.Biotope.Server, as: BiotopeServer
  alias Arkea.Sim.Migration

  @default_settle_delay_ms 10
  @default_max_retries 25

  @type state :: %{
          last_migrated_tick: non_neg_integer(),
          max_retries: pos_integer(),
          settle_delay_ms: pos_integer()
        }

  @doc "Start the coordinator under the application supervisor."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Run migration synchronously for a given tick.

  Intended for integration tests that use `manual_tick/1` instead of the
  asynchronous `WorldClock` PubSub path.
  """
  @spec run_migration(non_neg_integer()) :: :ok | :noop | {:error, atom()}
  def run_migration(tick) when is_integer(tick) and tick >= 0 do
    GenServer.call(__MODULE__, {:run_migration, tick}, 15_000)
  end

  @impl GenServer
  def init(_opts) do
    Phoenix.PubSub.subscribe(Arkea.PubSub, "world:tick")

    {:ok,
     %{
       last_migrated_tick: 0,
       settle_delay_ms:
         Application.get_env(:arkea, :migration_settle_delay_ms, @default_settle_delay_ms),
       max_retries: Application.get_env(:arkea, :migration_max_retries, @default_max_retries)
     }}
  end

  @impl GenServer
  def handle_call({:run_migration, tick}, _from, state) do
    case reconcile_tick(tick) do
      :ok ->
        {:reply, :ok, %{state | last_migrated_tick: max(state.last_migrated_tick, tick)}}

      :noop ->
        {:reply, :noop, %{state | last_migrated_tick: max(state.last_migrated_tick, tick)}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_info({:tick, tick}, %{last_migrated_tick: last_tick} = state)
      when tick > last_tick do
    Process.send_after(self(), {:reconcile_tick, tick, 0}, state.settle_delay_ms)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:reconcile_tick, tick, retry}, state) do
    case reconcile_tick(tick) do
      :ok ->
        {:noreply, %{state | last_migrated_tick: max(state.last_migrated_tick, tick)}}

      :noop ->
        {:noreply, %{state | last_migrated_tick: max(state.last_migrated_tick, tick)}}

      {:error, :tick_not_ready} when retry < state.max_retries ->
        Process.send_after(self(), {:reconcile_tick, tick, retry + 1}, state.settle_delay_ms)
        {:noreply, state}

      {:error, :tick_not_ready} ->
        Logger.warning("Migration.Coordinator: timed out waiting for tick #{tick}")
        {:noreply, %{state | last_migrated_tick: max(state.last_migrated_tick, tick)}}

      {:error, reason} ->
        Logger.warning("Migration.Coordinator: tick #{tick} failed: #{inspect(reason)}")
        {:noreply, %{state | last_migrated_tick: max(state.last_migrated_tick, tick)}}
    end
  end

  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp reconcile_tick(tick) do
    states = participating_states()

    cond do
      states == [] ->
        :noop

      Enum.any?(states, &(&1.tick_count != tick)) ->
        {:error, :tick_not_ready}

      true ->
        states
        |> Migration.plan(migration_opts())
        |> Enum.reject(fn {_id, transfer} -> Migration.empty_transfer?(transfer) end)
        |> apply_plan(tick)
    end
  end

  defp apply_plan([], _tick), do: :noop

  defp apply_plan(transfers, tick) do
    Enum.reduce_while(transfers, :ok, fn {biotope_id, transfer}, _acc ->
      case BiotopeServer.apply_migration(biotope_id, transfer, tick) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp participating_states do
    states = registered_states()
    incoming_targets = MapSet.new(Enum.flat_map(states, & &1.neighbor_ids))

    Enum.filter(states, fn state ->
      state.neighbor_ids != [] or MapSet.member?(incoming_targets, state.id)
    end)
  end

  defp registered_states do
    biotope_ids()
    |> Enum.map(&safe_get_state/1)
    |> Enum.reject(&is_nil/1)
  end

  defp biotope_ids do
    Registry.select(Arkea.Sim.Registry, [{{{:biotope, :"$1"}, :_, :_}, [], [:"$1"]}])
  end

  defp safe_get_state(id) do
    BiotopeServer.get_state(id)
  rescue
    ArgumentError -> nil
  end

  defp migration_opts do
    [
      base_flow: Application.get_env(:arkea, :migration_base_flow, 0.12),
      metabolite_flow_scale: Application.get_env(:arkea, :migration_metabolite_flow_scale, 0.45),
      signal_flow_scale: Application.get_env(:arkea, :migration_signal_flow_scale, 0.70),
      phage_flow_scale: Application.get_env(:arkea, :migration_phage_flow_scale, 0.30)
    ]
  end
end
