defmodule Arkea.HistoryTest do
  use Arkea.DataCase, async: false

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.History
  alias Arkea.Persistence.BiotopeSnapshot
  alias Arkea.Persistence.BiotopeWalEntry
  alias Arkea.Persistence.Serializer
  alias Arkea.Sim.BiotopeState

  defp catalytic_domain, do: Domain.new([0, 0, 1], List.duplicate(10, 20))

  defp sample_state(id, tick) do
    gene = Gene.from_domains([catalytic_domain()])
    genome = Genome.new([gene])
    lineage = Lineage.new_founder(genome, %{surface: 100}, 0)

    BiotopeState.new_from_opts(
      id: id,
      archetype: :eutrophic_pond,
      phases: [Phase.new(:surface)],
      dilution_rate: 0.0,
      tick_count: tick,
      lineages: [lineage]
    )
  end

  defp insert_wal!(biotope_id, tick) do
    state = sample_state(biotope_id, tick)

    Repo.insert!(%BiotopeWalEntry{
      biotope_id: biotope_id,
      tick_count: tick,
      transition_kind: "tick",
      state_binary: Serializer.dump!(state)
    })

    state
  end

  defp insert_snapshot!(biotope_id, tick) do
    state = sample_state(biotope_id, tick)

    wal =
      Repo.insert!(%BiotopeWalEntry{
        biotope_id: biotope_id,
        tick_count: tick,
        transition_kind: "tick",
        state_binary: Serializer.dump!(state)
      })

    Repo.insert!(%BiotopeSnapshot{
      biotope_id: biotope_id,
      tick_count: tick,
      source_wal_entry_id: wal.id,
      state_binary: Serializer.dump!(state)
    })

    state
  end

  test "fetch_state_at/2 returns nil when there is no row at or before the requested tick" do
    biotope_id = Ecto.UUID.generate()
    assert is_nil(History.fetch_state_at(biotope_id, 5))
  end

  test "fetch_state_at/2 returns the WAL entry at the exact tick when present" do
    biotope_id = Ecto.UUID.generate()
    insert_wal!(biotope_id, 10)

    state = History.fetch_state_at(biotope_id, 10)
    assert %BiotopeState{tick_count: 10} = state
  end

  test "fetch_state_at/2 falls back to the latest snapshot ≤ tick when no exact WAL exists" do
    biotope_id = Ecto.UUID.generate()
    insert_snapshot!(biotope_id, 10)
    # No WAL entry at tick 15 — the snapshot at 10 must satisfy.
    state = History.fetch_state_at(biotope_id, 15)
    assert %BiotopeState{tick_count: 10} = state
  end

  test "fetch_state_at/2 falls back to the latest WAL ≤ tick when no snapshot exists" do
    biotope_id = Ecto.UUID.generate()
    insert_wal!(biotope_id, 5)
    insert_wal!(biotope_id, 7)
    # Requested tick 9, no snapshot, latest WAL ≤ 9 is at 7.
    state = History.fetch_state_at(biotope_id, 9)
    assert %BiotopeState{tick_count: 7} = state
  end

  test "fetch_state_at/2 prefers the exact WAL row over an earlier snapshot" do
    biotope_id = Ecto.UUID.generate()
    insert_snapshot!(biotope_id, 10)
    insert_wal!(biotope_id, 12)

    state = History.fetch_state_at(biotope_id, 12)
    assert %BiotopeState{tick_count: 12} = state
  end

  test "fetch_state_at/2 isolates by biotope_id" do
    biotope_a = Ecto.UUID.generate()
    biotope_b = Ecto.UUID.generate()
    insert_wal!(biotope_a, 10)

    assert is_nil(History.fetch_state_at(biotope_b, 10))
    assert %BiotopeState{tick_count: 10} = History.fetch_state_at(biotope_a, 10)
  end
end
