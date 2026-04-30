defmodule ArkeaWeb.PageControllerTest do
  use ArkeaWeb.ConnCase

  # The root route now renders SimLive (replaced PageController in Phase 5 UI).
  # We verify that the LiveView shell is served and contains the simulation title.
  test "GET / renders SimLive", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Arkea Simulation"
  end
end
