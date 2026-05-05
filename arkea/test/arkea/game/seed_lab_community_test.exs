defmodule Arkea.Game.SeedLab.CommunityTest do
  @moduledoc """
  End-to-end tests for `Arkea.Game.SeedLab.provision_community/2`:
  the multi-founder counterpart of `provision_home/2`.
  """
  use ArkeaWeb.ConnCase

  alias Arkea.Game.PrototypePlayer
  alias Arkea.Game.SeedLab
  alias Arkea.Game.World
  alias Arkea.Persistence.ArkeonBlueprint
  alias Arkea.Persistence.PlayerBiotope
  alias Arkea.Sim.BiotopeState

  setup do
    cleanup_owned_biotopes()
    on_exit(&cleanup_owned_biotopes/0)
    :ok
  end

  test "provisions a single biotope colonised by 3 distinct founders" do
    specs = [
      build_spec("alpha", "eutrophic_pond", "bloom"),
      build_spec("beta", "eutrophic_pond", "balanced"),
      build_spec("gamma", "eutrophic_pond", "thrifty")
    ]

    {:ok, biotope_id} = SeedLab.provision_community(PrototypePlayer.profile(), specs)

    state = Arkea.Sim.Biotope.Server.get_state(biotope_id)
    assert length(state.lineages) == 3

    # Each founder carries a distinct `original_seed_id`.
    seed_ids = Enum.map(state.lineages, & &1.original_seed_id)
    assert length(Enum.uniq(seed_ids)) == 3
    assert Enum.all?(seed_ids, &is_binary/1)

    assert BiotopeState.total_abundance(state) > 0

    # Three blueprints persisted (1 primary + 2 auxiliary), all
    # owned by the player.
    assert Arkea.Repo.aggregate(ArkeonBlueprint, :count) == 3

    # Only one player_biotope row — the auxiliary blueprints are
    # standalone, recoverable via the audit event payload.
    assert Arkea.Repo.aggregate(PlayerBiotope, :count) == 1
  end

  test "rejects communities exceeding the cap of 3" do
    specs =
      Enum.map(0..3, fn i ->
        build_spec("seed-#{i}", "eutrophic_pond", "balanced")
      end)

    assert {:error, %{starter_archetype: msg}} =
             SeedLab.provision_community(PrototypePlayer.profile(), specs)

    assert msg =~ "at most 3"
  end

  test "rejects communities whose founders use different archetypes" do
    specs = [
      build_spec("alpha", "eutrophic_pond", "balanced"),
      build_spec("beta", "saline_estuary", "balanced")
    ]

    assert {:error, %{starter_archetype: msg}} =
             SeedLab.provision_community(PrototypePlayer.profile(), specs)

    assert msg =~ "same biotope archetype"
  end

  test "single-founder community is equivalent to provision_home (still inside the cap)" do
    specs = [build_spec("solo", "eutrophic_pond", "balanced")]

    assert {:ok, biotope_id} =
             SeedLab.provision_community(PrototypePlayer.profile(), specs)

    state = Arkea.Sim.Biotope.Server.get_state(biotope_id)
    assert length(state.lineages) == 1
  end

  defp build_spec(name, archetype, metabolism) do
    %{
      "seed_name" => name,
      "starter_archetype" => archetype,
      "metabolism_profile" => metabolism,
      "membrane_profile" => "porous",
      "regulation_profile" => "responsive",
      "mobile_module" => "none"
    }
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

    Arkea.Repo.delete_all(PlayerBiotope)
    Arkea.Repo.delete_all(ArkeonBlueprint)
  end
end
