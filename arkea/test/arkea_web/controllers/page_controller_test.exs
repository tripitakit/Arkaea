defmodule ArkeaWeb.PageControllerTest do
  use ArkeaWeb.ConnCase

  # The root route renders SimLive.
  # We verify that the LiveView shell contains the Phase 9 viewport chrome.
  test "GET / renders SimLive", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "Procedural biotope viewport"
    assert html =~ "PixiJS scene hook"
    assert html =~ "phx-hook=\"BiotopeScene\""
  end
end
