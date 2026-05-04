defmodule ArkeaWeb.HGTLedgerLiveTest do
  use ArkeaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Arkea.Game.PrototypePlayer
  alias Arkea.Game.SeedLab
  alias Arkea.Game.World

  setup %{conn: conn} do
    cleanup_owned_biotopes()
    on_exit(&cleanup_owned_biotopes/0)
    {:ok, biotope_id} = provision_test_biotope()
    {:ok, conn: log_in_prototype_player(conn), biotope_id: biotope_id}
  end

  test "renders the ledger heading and filter chips for an empty audit log",
       %{conn: conn, biotope_id: id} do
    {:ok, _view, html} = live(conn, ~p"/biotopes/#{id}/hgt-ledger")

    assert html =~ "Horizontal gene transfer events"
    assert html =~ "Aggregated flows"
    assert html =~ "HGT event log"
    assert html =~ "All ("
    assert html =~ "No HGT flows yet"
  end

  test "kind=<x> filter chip is reflected in the URL on click",
       %{conn: conn, biotope_id: id} do
    {:ok, view, _html} = live(conn, ~p"/biotopes/#{id}/hgt-ledger")

    view
    |> element(~s|button[phx-click="filter"][phx-value-kind="rm_digestion"]|)
    |> render_click()

    assert_patched(view, ~p"/biotopes/#{id}/hgt-ledger?kind=rm_digestion")
  end

  defp provision_test_biotope do
    SeedLab.provision_home(%{
      "seed_name" => "HGT Ledger Test",
      "starter_archetype" => "eutrophic_pond",
      "metabolism_profile" => "balanced",
      "membrane_profile" => "porous",
      "regulation_profile" => "responsive",
      "mobile_module" => "none"
    })
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
