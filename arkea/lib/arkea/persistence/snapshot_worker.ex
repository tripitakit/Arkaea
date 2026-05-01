defmodule Arkea.Persistence.SnapshotWorker do
  @moduledoc """
  Oban worker that materialises periodic snapshots from already-persisted WAL rows.
  """

  use Oban.Worker,
    queue: :snapshots,
    max_attempts: 5,
    unique: [period: 60, fields: [:worker, :args], keys: [:wal_entry_id]]

  alias Arkea.Persistence.BiotopeSnapshot
  alias Arkea.Persistence.BiotopeWalEntry
  alias Arkea.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    wal_entry_id = Map.fetch!(args, "wal_entry_id")
    biotope_id = Map.fetch!(args, "biotope_id")
    tick_count = Map.fetch!(args, "tick_count")

    case Repo.get(BiotopeWalEntry, wal_entry_id) do
      nil ->
        {:error, "missing wal entry #{wal_entry_id}"}

      %BiotopeWalEntry{} = wal_entry ->
        upsert_snapshot(wal_entry, biotope_id, tick_count)
    end
  end

  defp upsert_snapshot(%BiotopeWalEntry{} = wal_entry, biotope_id, tick_count) do
    if wal_entry.biotope_id != biotope_id or wal_entry.tick_count != tick_count do
      {:error, "wal metadata mismatch"}
    else
      attrs = %{
        biotope_id: wal_entry.biotope_id,
        tick_count: wal_entry.tick_count,
        source_wal_entry_id: wal_entry.id,
        state_binary: wal_entry.state_binary
      }

      changeset = BiotopeSnapshot.changeset(%BiotopeSnapshot{}, attrs)

      case Repo.insert(
             changeset,
             on_conflict: [
               set: [
                 source_wal_entry_id: wal_entry.id,
                 state_binary: wal_entry.state_binary
               ]
             ],
             conflict_target: [:biotope_id, :tick_count]
           ) do
        {:ok, _snapshot} -> :ok
        {:error, changeset} -> {:error, inspect(changeset.errors)}
      end
    end
  end
end
