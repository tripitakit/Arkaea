defmodule ArkeaWeb.PageControllerTest do
  use ArkeaWeb.ConnCase

  test "GET / renders WorldLive", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "Shared world overview"
    assert html =~ "Biotope network"
    assert html =~ "Open seed lab"
  end
end
