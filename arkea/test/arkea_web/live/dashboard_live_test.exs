defmodule ArkeaWeb.DashboardLiveTest do
  use ArkeaWeb.ConnCase

  import Phoenix.LiveViewTest

  test "anonymous player cannot open the dashboard", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/dashboard")
  end

  test "authenticated player lands on the dashboard with six panels", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_prototype_player() |> live(~p"/dashboard")

    html = render(view)

    assert html =~ "arkea-dashboard"
    assert html =~ "Dashboard"
    # 6 cards
    assert html =~ "Biotope network"
    assert html =~ "Founder design"
    assert html =~ "Owned runtime nodes"
    assert html =~ "Multi-seed runs"
    assert html =~ "Global event stream"
    assert html =~ "Design &amp; calibration"
  end

  test "dashboard nav marks Dashboard as the active item", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_prototype_player() |> live(~p"/dashboard")

    assert has_element?(view, ~s|.arkea-shell__nav-link[aria-current="page"]|, "Dashboard")
  end

  test "dashboard exposes navigate links to /world and /seed-lab", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_prototype_player() |> live(~p"/dashboard")

    html = render(view)
    assert html =~ ~s|href="/world"|
    assert html =~ ~s|href="/seed-lab"|
  end

  test "authenticated visit to / redirects to /dashboard", %{conn: conn} do
    conn = conn |> log_in_prototype_player() |> get(~p"/")
    assert redirected_to(conn) == "/dashboard"
  end
end
