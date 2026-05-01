defmodule Arkea.Sim.Migration.CoordinatorTest do
  use ExUnit.Case, async: false

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Sim.Biotope.Server, as: BiotopeServer
  alias Arkea.Sim.Biotope.Supervisor, as: BiotopeSupervisor
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Migration.Coordinator

  @moduletag :sim

  test "coordinator diffuses a lineage across a 5-biotope chain one hop per tick" do
    previous_base_flow = Application.get_env(:arkea, :migration_base_flow)
    Application.put_env(:arkea, :migration_base_flow, 0.5)

    on_exit(fn ->
      if previous_base_flow == nil do
        Application.delete_env(:arkea, :migration_base_flow)
      else
        Application.put_env(:arkea, :migration_base_flow, previous_base_flow)
      end
    end)

    ids = Enum.map(1..5, fn _ -> Arkea.UUID.v4() end)

    states = [
      build_state(Enum.at(ids, 0), [Enum.at(ids, 1)], 5_000),
      build_state(Enum.at(ids, 1), [Enum.at(ids, 2)], 0),
      build_state(Enum.at(ids, 2), [Enum.at(ids, 3)], 0),
      build_state(Enum.at(ids, 3), [Enum.at(ids, 4)], 0),
      build_state(Enum.at(ids, 4), [], 0)
    ]

    pids =
      Enum.map(states, fn state ->
        {:ok, pid} = BiotopeSupervisor.start_biotope(state)
        pid
      end)

    on_exit(fn ->
      Enum.each(pids, fn pid ->
        if Process.alive?(pid) do
          DynamicSupervisor.terminate_child(BiotopeSupervisor, pid)
        end
      end)
    end)

    totals_by_round =
      Enum.reduce(1..4, %{}, fn round, acc ->
        Enum.each(ids, &BiotopeServer.manual_tick/1)
        assert Coordinator.run_migration(round) in [:ok, :noop]

        round_totals =
          ids
          |> Enum.map(fn id ->
            state = BiotopeServer.get_state(id)
            {id, state.lineages |> Enum.sum_by(&Lineage.total_abundance/1)}
          end)
          |> Map.new()

        Map.put(acc, round, round_totals)
      end)

    assert totals_by_round[1][Enum.at(ids, 1)] > 0
    assert totals_by_round[1][Enum.at(ids, 2)] == 0

    assert totals_by_round[2][Enum.at(ids, 2)] > 0
    assert totals_by_round[2][Enum.at(ids, 3)] == 0

    assert totals_by_round[3][Enum.at(ids, 3)] > 0
    assert totals_by_round[3][Enum.at(ids, 4)] == 0

    assert totals_by_round[4][Enum.at(ids, 4)] > 0

    Enum.each(totals_by_round, fn {_round, totals} ->
      assert Enum.sum(Map.values(totals)) == 5_000
    end)
  end

  defp build_state(id, neighbor_ids, abundance) do
    lineage =
      if abundance > 0 do
        [Lineage.new_founder(zero_delta_genome(), %{surface: abundance}, 0)]
      else
        []
      end

    BiotopeState.new_from_opts(
      id: id,
      archetype: :oligotrophic_lake,
      x: 0.0,
      y: 0.0,
      zone: :chain_zone,
      phases: [Phase.new(:surface, dilution_rate: 0.0)],
      dilution_rate: 0.0,
      neighbor_ids: neighbor_ids,
      lineages: lineage
    )
  end

  defp zero_delta_genome do
    catalytic = Domain.new([0, 0, 1], List.duplicate(0, 20))
    high_fidelity = Domain.new([0, 1, 9], List.duplicate(19, 20))
    gene = Gene.from_domains([catalytic, high_fidelity])
    Genome.new([gene])
  end
end
