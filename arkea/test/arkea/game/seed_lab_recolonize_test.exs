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

  test "recolonize_home_with_spec/2 swaps the blueprint and re-inoculates an extinct home" do
    {:ok, biotope_id} = provision_test_home()
    force_extinction(biotope_id)

    pre_blueprint = Arkea.Repo.one!(Arkea.Persistence.ArkeonBlueprint)

    new_params = %{
      "seed_name" => "Recolonize Variant",
      "starter_archetype" => "eutrophic_pond",
      "metabolism_profile" => "thrifty",
      "membrane_profile" => "fortified",
      "regulation_profile" => "responsive",
      "mobile_module" => "conjugative_plasmid"
    }

    assert {:ok,
            %{
              biotope_id: ^biotope_id,
              lineage_id: lineage_id,
              tick: _tick,
              blueprint_id: new_blueprint_id
            }} = SeedLab.recolonize_home_with_spec(PrototypePlayer.id(), new_params)

    assert new_blueprint_id != pre_blueprint.id

    # Two blueprints persisted: the old one stays for audit, the new one
    # is now linked to the home.
    assert Arkea.Repo.aggregate(Arkea.Persistence.ArkeonBlueprint, :count) == 2

    pb = Arkea.Repo.one!(Arkea.Persistence.PlayerBiotope)
    assert pb.source_blueprint_id == new_blueprint_id

    state_after = BiotopeServer.get_state(biotope_id)
    assert length(state_after.lineages) == 1
    assert hd(state_after.lineages).id == lineage_id
    # The recolonized founder is built with the new metabolism/membrane
    # profile, so its phenotype must reflect the edited spec — we don't
    # check the genome bytes here (they're a different blueprint anyway),
    # we just confirm the founder is fresh.
    assert BiotopeState.total_abundance(state_after) == 420
  end

  test "recolonize_home_with_spec/2 refuses to change the starter_archetype" do
    {:ok, biotope_id} = provision_test_home()
    force_extinction(biotope_id)

    other_archetype_params = %{
      "seed_name" => "Different Archetype",
      "starter_archetype" => "mesophilic_soil",
      "metabolism_profile" => "balanced",
      "membrane_profile" => "porous",
      "regulation_profile" => "responsive",
      "mobile_module" => "none"
    }

    assert {:error, :archetype_mismatch} =
             SeedLab.recolonize_home_with_spec(PrototypePlayer.id(), other_archetype_params)
  end

  test "recolonize_home_with_spec/2 refuses on a non-extinct home" do
    {:ok, _biotope_id} = provision_test_home()

    params = %{
      "seed_name" => "Won't Apply",
      "starter_archetype" => "eutrophic_pond",
      "metabolism_profile" => "balanced",
      "membrane_profile" => "porous",
      "regulation_profile" => "responsive",
      "mobile_module" => "none"
    }

    assert {:error, :not_extinct} =
             SeedLab.recolonize_home_with_spec(PrototypePlayer.id(), params)
  end

  test "recolonize_home/1 returns :no_home for a player with no provisioned home" do
    {:ok, %{id: other_id}} =
      Arkea.Accounts.register_player(%{
        "display_name" => "No Home",
        "email" => "no-home@example.com"
      })

    assert {:error, :no_home} = SeedLab.recolonize_home(other_id)
  end

  test "a player can claim up to 3 homes; the 4th is rejected" do
    archetypes = ["oligotrophic_lake", "mesophilic_soil", "saline_estuary"]

    for archetype <- archetypes do
      assert {:ok, _id} =
               SeedLab.provision_home(%{
                 "seed_name" => "Home #{archetype}",
                 "starter_archetype" => archetype,
                 "metabolism_profile" => "balanced",
                 "membrane_profile" => "porous",
                 "regulation_profile" => "responsive",
                 "mobile_module" => "none"
               })
    end

    assert SeedLab.home_count(PrototypePlayer.id()) == 3
    refute SeedLab.can_provision_home?(PrototypePlayer.id())

    assert {:error, %{starter_archetype: _}} =
             SeedLab.provision_home(%{
               "seed_name" => "Fourth Home",
               "starter_archetype" => "marine_sediment",
               "metabolism_profile" => "balanced",
               "membrane_profile" => "porous",
               "regulation_profile" => "responsive",
               "mobile_module" => "none"
             })

    assert SeedLab.home_count(PrototypePlayer.id()) == 3
  end

  test "recolonize_home/2 with explicit biotope_id targets that home only" do
    {:ok, first_id} =
      SeedLab.provision_home(%{
        "seed_name" => "First",
        "starter_archetype" => "oligotrophic_lake",
        "metabolism_profile" => "balanced",
        "membrane_profile" => "porous",
        "regulation_profile" => "responsive",
        "mobile_module" => "none"
      })

    {:ok, second_id} =
      SeedLab.provision_home(%{
        "seed_name" => "Second",
        "starter_archetype" => "mesophilic_soil",
        "metabolism_profile" => "balanced",
        "membrane_profile" => "porous",
        "regulation_profile" => "responsive",
        "mobile_module" => "none"
      })

    # Kill only the first home; the second stays alive.
    force_extinction(first_id)

    refute SeedLab.home_extinct?(PrototypePlayer.id(), second_id)
    assert SeedLab.home_extinct?(PrototypePlayer.id(), first_id)

    # Recolonizing the second (alive) home must refuse.
    assert {:error, :not_extinct} =
             SeedLab.recolonize_home(PrototypePlayer.id(), second_id)

    # Recolonizing the first (extinct) home must succeed.
    assert {:ok, %{biotope_id: ^first_id}} =
             SeedLab.recolonize_home(PrototypePlayer.id(), first_id)
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
