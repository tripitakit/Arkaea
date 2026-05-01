defmodule Arkea.Persistence.RuntimePersistenceTest do
  use Arkea.DataCase, async: false
  use Oban.Testing, repo: Arkea.Repo

  import Ecto.Query

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Persistence.AuditLog
  alias Arkea.Persistence.BiotopeSnapshot
  alias Arkea.Persistence.BiotopeWalEntry
  alias Arkea.Persistence.Recovery
  alias Arkea.Persistence.Serializer
  alias Arkea.Persistence.SnapshotWorker
  alias Arkea.Sim.Biotope.Server, as: BiotopeServer
  alias Arkea.Sim.Biotope.Supervisor, as: BiotopeSupervisor
  alias Arkea.Sim.BiotopeState

  setup do
    previous = Application.get_env(:arkea, :persistence_enabled)
    Application.put_env(:arkea, :persistence_enabled, true)
    start_supervised!(Arkea.Oban)

    on_exit(fn ->
      if previous == nil do
        Application.delete_env(:arkea, :persistence_enabled)
      else
        Application.put_env(:arkea, :persistence_enabled, previous)
      end
    end)

    :ok
  end

  test "manual_tick persists a WAL row and audit events" do
    state = extinction_state()
    start_biotope(state)
    lineage_id = hd(state.lineages).id

    assert :ok = BiotopeServer.manual_tick(state.id)

    persisted_state = BiotopeServer.get_state(state.id)
    assert persisted_state.tick_count == 1
    assert persisted_state.lineages == []

    wal_entry =
      Repo.one!(
        from entry in BiotopeWalEntry,
          where: entry.biotope_id == ^state.id
      )

    assert wal_entry.tick_count == 1
    assert wal_entry.transition_kind == "tick"
    assert {:ok, restored} = Serializer.load(wal_entry.state_binary)
    assert restored.tick_count == 1
    assert restored.lineages == []

    audit_entry =
      Repo.one!(
        from entry in AuditLog,
          where: entry.target_biotope_id == ^state.id
      )

    assert audit_entry.event_type == "lineage_extinct"
    assert audit_entry.target_lineage_id == lineage_id
    assert audit_entry.occurred_at_tick == 1
  end

  test "tick 10 enqueues and materialises a snapshot" do
    state = stable_state()
    start_biotope(state)

    Enum.each(1..10, fn _ -> assert :ok = BiotopeServer.manual_tick(state.id) end)

    assert_enqueued(
      worker: SnapshotWorker,
      queue: :snapshots,
      args: %{"biotope_id" => state.id, "tick_count" => 10}
    )

    [job] = all_enqueued(worker: SnapshotWorker, queue: :snapshots)
    assert :ok = perform_job(SnapshotWorker, job.args)

    snapshot =
      Repo.one!(
        from row in BiotopeSnapshot,
          where: row.biotope_id == ^state.id and row.tick_count == 10
      )

    assert {:ok, restored} = Serializer.load(snapshot.state_binary)
    assert restored.tick_count == 10
    assert snapshot.source_wal_entry_id != nil
  end

  test "a crashed biotope server restarts from the latest persisted WAL state" do
    state = stable_state()
    pid = start_biotope(state)

    Enum.each(1..3, fn _ -> assert :ok = BiotopeServer.manual_tick(state.id) end)
    before_crash = BiotopeServer.get_state(state.id)
    assert before_crash.tick_count == 3

    Process.exit(pid, :boom)

    restarted_pid = wait_for_restart(state.id, pid)
    assert restarted_pid != pid

    recovered_state = BiotopeServer.get_state(state.id)
    assert recovered_state.tick_count == before_crash.tick_count
    assert recovered_state.lineages == before_crash.lineages
  end

  test "recovery child restores persisted biotopes on startup" do
    state = stable_state()
    pid = start_biotope(state)

    Enum.each(1..2, fn _ -> assert :ok = BiotopeServer.manual_tick(state.id) end)
    expected_state = BiotopeServer.get_state(state.id)

    assert :ok = DynamicSupervisor.terminate_child(BiotopeSupervisor, pid)
    assert :ok = wait_for_stopped(state.id)

    start_supervised!({Recovery, seed_if_empty?: false})

    recovered_pid = wait_for_running(state.id)
    assert Process.alive?(recovered_pid)

    recovered_state = BiotopeServer.get_state(state.id)
    assert recovered_state.tick_count == expected_state.tick_count
    assert recovered_state.lineages == expected_state.lineages
  end

  defp start_biotope(%BiotopeState{} = state) do
    {:ok, pid} = BiotopeSupervisor.start_biotope(state)
    on_exit(fn -> stop_biotope(state.id) end)
    pid
  end

  defp stop_biotope(id) do
    case Registry.lookup(Arkea.Sim.Registry, {:biotope, id}) do
      [{pid, _value}] when is_pid(pid) ->
        if Process.alive?(pid) do
          DynamicSupervisor.terminate_child(BiotopeSupervisor, pid)
        end

        :ok

      _ ->
        :ok
    end
  end

  defp wait_for_restart(id, old_pid, attempts \\ 40)

  defp wait_for_restart(_id, _old_pid, 0) do
    flunk("biotope server did not restart")
  end

  defp wait_for_restart(id, old_pid, attempts) do
    case Registry.lookup(Arkea.Sim.Registry, {:biotope, id}) do
      [{pid, _value}] when is_pid(pid) ->
        if pid != old_pid and Process.alive?(pid) do
          pid
        else
          Process.sleep(50)
          wait_for_restart(id, old_pid, attempts - 1)
        end

      _ ->
        Process.sleep(50)
        wait_for_restart(id, old_pid, attempts - 1)
    end
  end

  defp wait_for_running(id, attempts \\ 40)

  defp wait_for_running(_id, 0) do
    flunk("biotope server did not start during recovery")
  end

  defp wait_for_running(id, attempts) do
    case Registry.lookup(Arkea.Sim.Registry, {:biotope, id}) do
      [{pid, _value}] when is_pid(pid) ->
        if Process.alive?(pid) do
          pid
        else
          Process.sleep(50)
          wait_for_running(id, attempts - 1)
        end

      _ ->
        Process.sleep(50)
        wait_for_running(id, attempts - 1)
    end
  end

  defp wait_for_stopped(id, attempts \\ 40)

  defp wait_for_stopped(_id, 0) do
    flunk("biotope server did not stop")
  end

  defp wait_for_stopped(id, attempts) do
    case Registry.lookup(Arkea.Sim.Registry, {:biotope, id}) do
      [] ->
        :ok

      _ ->
        Process.sleep(50)
        wait_for_stopped(id, attempts - 1)
    end
  end

  defp stable_state do
    build_state("stable", dilution_rate: 0.0, abundance: 80)
  end

  defp extinction_state do
    build_state("extinction", dilution_rate: 1.0, abundance: 20)
  end

  defp build_state(label, opts) do
    dilution_rate = Keyword.fetch!(opts, :dilution_rate)
    abundance = Keyword.fetch!(opts, :abundance)
    phase = Phase.new(:surface, dilution_rate: dilution_rate)
    lineage = Lineage.new_founder(zero_delta_genome(), %{surface: abundance}, 0)

    BiotopeState.new_from_opts(
      id: Arkea.UUID.v4(),
      archetype: :oligotrophic_lake,
      zone: String.to_atom("zone_#{label}"),
      phases: [phase],
      dilution_rate: dilution_rate,
      lineages: [lineage]
    )
  end

  defp zero_delta_genome do
    catalytic = Domain.new([0, 0, 1], List.duplicate(0, 20))
    high_fidelity = Domain.new([0, 1, 9], List.duplicate(19, 20))
    gene = Gene.from_domains([catalytic, high_fidelity])
    Genome.new([gene])
  end
end
