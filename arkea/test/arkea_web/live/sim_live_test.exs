defmodule ArkeaWeb.SimLiveTest do
  use ArkeaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Arkea.Game.PrototypePlayer
  alias Arkea.Game.SeedLab
  alias Arkea.Game.World
  alias Arkea.Sim.SeedScenario

  setup %{conn: conn} do
    cleanup_owned_biotopes()
    on_exit(&cleanup_owned_biotopes/0)
    {:ok, conn: log_in_prototype_player(conn)}
  end

  test "phase selector updates the focused phase", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/biotopes/#{SeedScenario.default_biotope_id()}")

    assert has_element?(view, "#phase-inspector-title", "Surface")
    assert has_element?(view, "#biotope-scene[phx-update='ignore']")
    assert has_element?(view, ".game-nav a[href='/world']", "World")
    assert has_element?(view, ".game-nav a[href='/seed-lab']", "Seed lab")
    assert render(view) =~ "Seed lab"
    assert render(view) =~ "data-selected-phase=\"surface\""
    assert render(view) =~ "Dot = lineage fraction; anchors stay stable across ticks"

    view
    |> element("button[data-phase='sediment']")
    |> render_click()

    assert has_element?(view, "#phase-inspector-title", "Sediment")
    assert render(view) =~ "data-selected-phase=\"sediment\""
  end

  test "operator console applies authoritative interventions on a player-owned biotope", %{
    conn: conn
  } do
    {:ok, biotope_id} =
      SeedLab.provision_home(%{
        "seed_name" => "Viewport Owner",
        "starter_archetype" => "eutrophic_pond",
        "metabolism_profile" => "balanced",
        "membrane_profile" => "porous",
        "regulation_profile" => "responsive",
        "mobile_module" => "none"
      })

    assert Enum.any?(World.list_biotopes(PrototypePlayer.id()), &(&1.id == biotope_id))

    {:ok, view, _html} = live(conn, ~p"/biotopes/#{biotope_id}")

    assert render(view) =~ "Intervention slot open"

    view
    |> element("button[phx-value-kind='nutrient_pulse']")
    |> render_click()

    assert render(view) =~ "Nutrient pulse"
    assert render(view) =~ "Surface"
    assert render(view) =~ "Budget locked for"
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
  end
end
