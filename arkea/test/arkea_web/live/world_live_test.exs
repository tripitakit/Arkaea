defmodule ArkeaWeb.WorldLiveTest do
  use ArkeaWeb.ConnCase

  import Phoenix.LiveViewTest

  test "anonymous player cannot open the world liveview", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/world")
  end

  test "authenticated player renders the world overview shell", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_prototype_player() |> live(~p"/world")

    assert render(view) =~ "Shared world overview"
    assert render(view) =~ "Biotope network"
    assert render(view) =~ "Open seed lab"
    assert has_element?(view, ".world-map")
  end
end
