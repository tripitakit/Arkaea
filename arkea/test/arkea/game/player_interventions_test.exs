defmodule Arkea.Game.PlayerInterventionsTest do
  use Arkea.DataCase, async: false

  import Ecto.Query

  alias Arkea.Game.PlayerInterventions
  alias Arkea.Game.PrototypePlayer
  alias Arkea.Game.SeedLab
  alias Arkea.Game.World
  alias Arkea.Persistence.InterventionLog
  alias Arkea.Sim.Biotope.Server, as: BiotopeServer

  setup do
    cleanup_owned_biotopes()
    on_exit(&cleanup_owned_biotopes/0)
    :ok
  end

  test "player intervention mutates the authoritative biotope and consumes the local budget" do
    {:ok, biotope_id} = SeedLab.provision_home(SeedLab.form_defaults())
    before_state = BiotopeServer.get_state(biotope_id)

    before_glucose =
      before_state.phases
      |> Enum.find(&(&1.name == :surface))
      |> then(&Map.fetch!(&1.metabolite_pool, :glucose))

    assert %{allowed?: true, owner?: true} =
             PlayerInterventions.status(PrototypePlayer.id(), biotope_id)

    assert {:ok, %{payload: payload}} =
             PlayerInterventions.apply(PrototypePlayer.profile(), biotope_id, %{
               kind: :nutrient_pulse,
               scope: :phase,
               phase_name: :surface
             })

    assert payload.kind == "nutrient_pulse"
    assert payload.phase_name == "surface"

    after_state = BiotopeServer.get_state(biotope_id)

    after_glucose =
      after_state.phases
      |> Enum.find(&(&1.name == :surface))
      |> then(&Map.fetch!(&1.metabolite_pool, :glucose))

    assert after_glucose == before_glucose + 12.0

    log =
      Repo.one!(
        from row in InterventionLog,
          where:
            row.player_id == ^PrototypePlayer.id() and row.biotope_id == ^biotope_id and
              row.kind == "nutrient_pulse"
      )

    assert log.phase_name == "surface"
    assert log.occurred_at_tick == after_state.tick_count
    assert log.payload["kind"] == "nutrient_pulse"

    assert %{allowed?: false, owner?: true, last_kind: "nutrient_pulse"} =
             PlayerInterventions.status(PrototypePlayer.id(), biotope_id)

    assert {:error, :budget_locked} =
             PlayerInterventions.apply(PrototypePlayer.profile(), biotope_id, %{
               kind: :nutrient_pulse,
               scope: :phase,
               phase_name: :surface
             })
  end

  defp cleanup_owned_biotopes do
    World.list_biotopes(PrototypePlayer.id())
    |> Enum.filter(&(&1.owner_player_id == PrototypePlayer.id()))
    |> Enum.each(fn biotope ->
      case Registry.lookup(Arkea.Sim.Registry, {:biotope, biotope.id}) do
        [{pid, _value}] when is_pid(pid) ->
          Process.exit(pid, :shutdown)
          wait_for_stopped(biotope.id)

        [] ->
          :ok
      end
    end)
  end

  defp wait_for_stopped(id, attempts \\ 20)

  defp wait_for_stopped(_id, 0), do: :ok

  defp wait_for_stopped(id, attempts) do
    case Registry.lookup(Arkea.Sim.Registry, {:biotope, id}) do
      [] ->
        :ok

      _ ->
        Process.sleep(25)
        wait_for_stopped(id, attempts - 1)
    end
  end
end
