defmodule ArkeaWeb.WorldLiveTest do
  use ArkeaWeb.ConnCase

  import Phoenix.LiveViewTest

  test "root renders the world overview shell", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert render(view) =~ "Shared world overview"
    assert render(view) =~ "Biotope network"
    assert render(view) =~ "Open seed lab"
    assert has_element?(view, ".world-map")
  end
end
