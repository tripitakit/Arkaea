defmodule Arkea.Persistence.Recovery do
  @moduledoc """
  Startup recovery for Phase 10 persisted biotopes.
  """

  use GenServer

  import Ecto.Query

  require Logger

  alias Arkea.Persistence
  alias Arkea.Persistence.BiotopeSnapshot
  alias Arkea.Persistence.BiotopeWalEntry
  alias Arkea.Persistence.Serializer
  alias Arkea.Repo
  alias Arkea.Sim.Biotope.Supervisor, as: BiotopeSupervisor
  alias Arkea.Sim.BiotopeState

  @type recovery_result :: {:ok, %{started: non_neg_integer(), skipped: non_neg_integer()}}

  @doc "Start the recovery coordinator."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Re-run recovery synchronously."
  @spec recover_now() :: recovery_result()
  def recover_now do
    GenServer.call(__MODULE__, :recover_now, :infinity)
  end

  @doc """
  Resolve the best persisted state for a biotope id, or `nil` when none exists.
  """
  @spec latest_state(binary()) ::
          {:ok, BiotopeState.t()} | {:error, atom() | tuple()} | nil
  def latest_state(id) when is_binary(id) do
    if Persistence.enabled?() do
      id
      |> latest_records()
      |> choose_record()
      |> load_record()
    else
      nil
    end
  end

  @doc """
  Use the latest persisted state when available, otherwise keep the supplied fallback.
  """
  @spec resolve_start_state(BiotopeState.t()) :: BiotopeState.t()
  def resolve_start_state(%BiotopeState{} = fallback_state) do
    case latest_state(fallback_state.id) do
      {:ok, %BiotopeState{} = restored_state} ->
        restored_state

      {:error, reason} ->
        Logger.warning("recovery fallback for biotope #{fallback_state.id}: #{inspect(reason)}")

        fallback_state

      nil ->
        fallback_state
    end
  end

  @impl GenServer
  def init(_opts) do
    {:ok, %{last_result: recover_all()}}
  end

  @impl GenServer
  def handle_call(:recover_now, _from, state) do
    result = recover_all()
    {:reply, result, %{state | last_result: result}}
  end

  defp recover_all do
    ids = recoverable_ids()

    result =
      Enum.reduce(ids, %{started: 0, skipped: 0}, fn biotope_id, acc ->
        case latest_state(biotope_id) do
          {:ok, %BiotopeState{} = state} ->
            recover_one(biotope_id, state, acc)

          {:error, reason} ->
            Logger.error("recovery skipped corrupted biotope #{biotope_id}: #{inspect(reason)}")
            acc

          nil ->
            acc
        end
      end)

    {:ok, result}
  end

  defp recover_one(biotope_id, state, acc) do
    case BiotopeSupervisor.start_biotope(state) do
      {:ok, _pid} ->
        %{acc | started: acc.started + 1}

      {:error, {:already_started, _pid}} ->
        %{acc | skipped: acc.skipped + 1}

      {:error, reason} ->
        Logger.warning("recovery could not start biotope #{biotope_id}: #{inspect(reason)}")
        acc
    end
  end

  defp recoverable_ids do
    wal_ids =
      Repo.all(
        from entry in BiotopeWalEntry,
          distinct: true,
          select: entry.biotope_id
      )

    snapshot_ids =
      Repo.all(
        from snapshot in BiotopeSnapshot,
          distinct: true,
          select: snapshot.biotope_id
      )

    Enum.uniq(wal_ids ++ snapshot_ids)
  end

  defp latest_records(id) do
    wal =
      Repo.one(
        from entry in BiotopeWalEntry,
          where: entry.biotope_id == ^id,
          order_by: [desc: entry.tick_count, desc: entry.inserted_at],
          limit: 1
      )

    snapshot =
      Repo.one(
        from row in BiotopeSnapshot,
          where: row.biotope_id == ^id,
          order_by: [desc: row.tick_count, desc: row.inserted_at],
          limit: 1
      )

    %{wal: wal, snapshot: snapshot}
  end

  defp choose_record(%{wal: nil, snapshot: nil}), do: nil
  defp choose_record(%{wal: %BiotopeWalEntry{} = wal, snapshot: nil}), do: {:wal, wal}

  defp choose_record(%{wal: nil, snapshot: %BiotopeSnapshot{} = snapshot}),
    do: {:snapshot, snapshot}

  defp choose_record(%{wal: %BiotopeWalEntry{} = wal, snapshot: %BiotopeSnapshot{} = snapshot}) do
    if wal.tick_count >= snapshot.tick_count do
      {:wal, wal}
    else
      {:snapshot, snapshot}
    end
  end

  defp load_record(nil), do: nil
  defp load_record({_kind, %{state_binary: state_binary}}), do: Serializer.load(state_binary)
end
