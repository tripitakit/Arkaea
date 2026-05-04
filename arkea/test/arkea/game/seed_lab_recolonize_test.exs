defmodule Arkea.Game.SeedLab.RecolonizeTest do
  @moduledoc """
  Integration test for `Arkea.Game.SeedLab.recolonize_home/1` and
  `home_extinct?/1`. Exercises the full path:

    1. provision a home via `provision_home/2` (registers a running
       Biotope.Server in `Arkea.Sim.Registry`);
    2. simulate population collapse by mutating the server's state via
       `:sys.replace_state/2` (no production setter exists, by design —
       extinction in normal play arises from selection or stochastic
       drift, not by external write);
    3. assert `home_extinct?/1` flips to `true`;
    4. call `recolonize_home/1` and verify a fresh founder lineage is
       installed at `N=420`.
  """
  use ArkeaWeb.ConnCase

  alias Arkea.Game.PrototypePlayer
  alias Arkea.Game.SeedLab
  alias Arkea.Game.World
  alias Arkea.Sim.Biotope.Server, as: BiotopeServer
  alias Arkea.Sim.BiotopeState

  setup do
    cleanup_owned_biotopes()
    on_exit(&cleanup_owned_biotopes/0)
    :ok
  end

  test "home_extinct?/1 is false on a freshly provisioned home, true once lineages collapse" do
    {:ok, biotope_id} = provision_test_home()
    refute SeedLab.home_extinct?(PrototypePlayer.id())

    force_extinction(biotope_id)
    assert SeedLab.home_extinct?(PrototypePlayer.id())
  end

  test "recolonize_home/1 refuses while the home is alive" do
    {:ok, _biotope_id} = provision_test_home()

    assert {:error, :not_extinct} = SeedLab.recolonize_home(PrototypePlayer.id())
  end

  test "recolonize_home/1 re-inoculates an extinct home with a fresh founder" do
    {:ok, biotope_id} = provision_test_home()
    force_extinction(biotope_id)

    pre_state = BiotopeServer.get_state(biotope_id)
    assert pre_state.lineages == []
    assert BiotopeState.total_abundance(pre_state) == 0

    assert {:ok, %{biotope_id: ^biotope_id, lineage_id: lineage_id, tick: _tick}} =
             SeedLab.recolonize_home(PrototypePlayer.id())

    post_state = BiotopeServer.get_state(biotope_id)
    assert length(post_state.lineages) == 1
    assert hd(post_state.lineages).id == lineage_id
    # The founder is built with N=420 distributed across phases.
    assert BiotopeState.total_abundance(post_state) == 420

    # After recolonization the helper should report the home as alive again.
    refute SeedLab.home_extinct?(PrototypePlayer.id())
  end

  test "recolonize_home/1 returns :no_home for a player with no provisioned home" do
    {:ok, %{id: other_id}} =
      Arkea.Accounts.register_player(%{
        "display_name" => "No Home",
        "email" => "no-home@example.com"
      })

    assert {:error, :no_home} = SeedLab.recolonize_home(other_id)
  end

  defp provision_test_home do
    SeedLab.provision_home(%{
      "seed_name" => "Recolonize Test Seed",
      "starter_archetype" => "eutrophic_pond",
      "metabolism_profile" => "balanced",
      "membrane_profile" => "porous",
      "regulation_profile" => "responsive",
      "mobile_module" => "none"
    })
  end

  defp force_extinction(biotope_id) do
    [{pid, _}] = Registry.lookup(Arkea.Sim.Registry, {:biotope, biotope_id})
    :sys.replace_state(pid, fn state -> %{state | lineages: []} end)
    :ok
  end

  defp cleanup_owned_biotopes do
    World.list_biotopes(PrototypePlayer.id())
    |> Enum.filter(&(&1.owner_player_id == PrototypePlayer.id()))
    |> Enum.each(fn biotope ->
      case Registry.lookup(Arkea.Sim.Registry, {:biotope, biotope.id}) do
        [{pid, _value}] ->
          ref = Process.monitor(pid)
          Process.exit(pid, :shutdown)
          assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000

        [] ->
          :ok
      end
    end)

    Arkea.Repo.delete_all(Arkea.Persistence.PlayerBiotope)
    Arkea.Repo.delete_all(Arkea.Persistence.ArkeonBlueprint)
  end
end
