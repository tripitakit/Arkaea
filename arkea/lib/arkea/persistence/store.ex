defmodule Arkea.Persistence.Store do
  @moduledoc """
  Transactional runtime persistence for post-tick and post-migration transitions.
  """

  require Logger

  alias Arkea.Oban
  alias Arkea.Persistence
  alias Arkea.Persistence.AuditWriter
  alias Arkea.Persistence.BiotopeWalEntry
  alias Arkea.Persistence.Serializer
  alias Arkea.Persistence.SnapshotWorker
  alias Arkea.Repo
  alias Arkea.Sim.BiotopeState
  alias Ecto.Multi

  @snapshot_interval 10

  @doc """
  Persist a new authoritative biotope state, the related audit events, and
  optionally enqueue a periodic snapshot job.
  """
  @spec persist_transition(BiotopeState.t(), [map()], atom()) :: :ok | {:error, term()}
  def persist_transition(%BiotopeState{} = state, events, transition_kind)
      when is_list(events) and is_atom(transition_kind) do
    if Persistence.enabled?() do
      occurred_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      multi =
        Multi.new()
        |> Multi.insert(
          :wal_entry,
          BiotopeWalEntry.changeset(%BiotopeWalEntry{}, %{
            biotope_id: state.id,
            tick_count: state.tick_count,
            transition_kind: Atom.to_string(transition_kind),
            state_binary: Serializer.dump!(state)
          })
        )
        |> Multi.run(:audit_log, fn repo, _changes ->
          AuditWriter.insert_events(repo, state.id, state.tick_count, events, occurred_at)
        end)
        |> maybe_enqueue_snapshot(state)

      case Repo.transaction(multi) do
        {:ok, _changes} ->
          :ok

        {:error, operation, reason, _changes} ->
          Logger.error(
            "runtime persistence failed for biotope #{state.id} at tick #{state.tick_count}: " <>
              "#{inspect(operation)} #{inspect(reason)}"
          )

          {:error, {operation, reason}}
      end
    else
      :ok
    end
  end

  defp maybe_enqueue_snapshot(multi, %BiotopeState{tick_count: tick_count} = state) do
    if rem(tick_count, @snapshot_interval) == 0 do
      Oban.insert(multi, :snapshot_job, fn %{wal_entry: wal_entry} ->
        SnapshotWorker.new(%{
          wal_entry_id: wal_entry.id,
          biotope_id: state.id,
          tick_count: state.tick_count
        })
      end)
    else
      multi
    end
  end
end
