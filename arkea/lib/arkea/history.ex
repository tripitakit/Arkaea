defmodule Arkea.History do
  @moduledoc """
  Historical-state lookup for time-anchored views (Phase 24 / 6.4).

  Given a `(biotope_id, tick)` pair, returns the most-recent
  authoritative `BiotopeState` whose `tick_count <= tick`. The
  function transparently chooses between the two persistence
  surfaces:

    * `biotope_snapshots` — full-state copies materialised every
      `@snapshot_interval` ticks (default 10) by
      `Arkea.Persistence.SnapshotWorker`. Cheap to fetch, but
      coarse.
    * `biotope_wal_entries` — write-ahead-log row per tick
      transition. Always present, finer granularity, but the table
      grows fast (one row per tick per biotope).

  Lookup strategy: prefer the WAL entry at the *exact* tick when
  it exists; fall back to the most recent snapshot ≤ tick; finally
  to the most recent WAL entry ≤ tick. The first hit wins. When no
  row at or before the requested tick exists (e.g. the user
  permalinks to a tick before the biotope was created), the
  function returns `nil`.

  Pure-ish: takes the repo as the second argument so test cases
  can pass a sandboxed connection. The default is `Arkea.Repo`.
  """

  import Ecto.Query

  alias Arkea.Persistence.BiotopeSnapshot
  alias Arkea.Persistence.BiotopeWalEntry
  alias Arkea.Persistence.Serializer
  alias Arkea.Repo
  alias Arkea.Sim.BiotopeState

  @doc """
  Reconstruct the biotope state at-or-before `tick`. Returns the
  deserialised `BiotopeState`, or `nil` if no row at or before
  `tick` exists.
  """
  @spec fetch_state_at(binary(), non_neg_integer(), keyword()) ::
          BiotopeState.t() | nil
  def fetch_state_at(biotope_id, tick, opts \\ [])
      when is_binary(biotope_id) and is_integer(tick) and tick >= 0 do
    repo = Keyword.get(opts, :repo, Repo)

    binary =
      lookup_exact_wal(repo, biotope_id, tick) ||
        lookup_latest_snapshot(repo, biotope_id, tick) ||
        lookup_latest_wal(repo, biotope_id, tick)

    case binary do
      nil ->
        nil

      bin when is_binary(bin) ->
        case Serializer.load(bin) do
          {:ok, %BiotopeState{} = state} -> state
          _ -> nil
        end
    end
  end

  defp lookup_exact_wal(repo, biotope_id, tick) do
    repo.one(
      from w in BiotopeWalEntry,
        where: w.biotope_id == ^biotope_id and w.tick_count == ^tick,
        order_by: [desc: w.inserted_at],
        limit: 1,
        select: w.state_binary
    )
  end

  defp lookup_latest_snapshot(repo, biotope_id, tick) do
    repo.one(
      from s in BiotopeSnapshot,
        where: s.biotope_id == ^biotope_id and s.tick_count <= ^tick,
        order_by: [desc: s.tick_count],
        limit: 1,
        select: s.state_binary
    )
  end

  defp lookup_latest_wal(repo, biotope_id, tick) do
    repo.one(
      from w in BiotopeWalEntry,
        where: w.biotope_id == ^biotope_id and w.tick_count <= ^tick,
        order_by: [desc: w.tick_count, desc: w.inserted_at],
        limit: 1,
        select: w.state_binary
    )
  end
end
