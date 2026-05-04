defmodule ArkeaWeb.WorldLiveTest do
  use ArkeaWeb.ConnCase

  import Phoenix.LiveViewTest

  test "anonymous player cannot open the world liveview", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/world")
  end

  test "authenticated player renders the world shell with graph and side panels", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_prototype_player() |> live(~p"/world")
    html = render(view)

    # New shell structure
    assert html =~ "arkea-shell"
    assert html =~ "arkea-world"
    assert html =~ "arkea-world__graph"
    assert html =~ "arkea-world__side"

    # World nav item is active
    assert has_element?(view, ~s|.arkea-shell__nav-link[aria-current="page"]|, "World")

    # Operator panel CTA points to seed lab
    assert html =~ ~s|href="/seed-lab"|

    # Filter tabs
    assert has_element?(view, ".arkea-world__filter", "All")
    assert has_element?(view, ".arkea-world__filter", "Mine")
    assert has_element?(view, ".arkea-world__filter", "Wild")
  end

  test "filter tab updates the active filter", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_prototype_player() |> live(~p"/world")

    view |> element(~s|button[phx-click="filter"][phx-value-to="mine"]|) |> render_click()

    assert has_element?(view, ".arkea-world__filter--active", "Mine")
    refute has_element?(view, ".arkea-world__filter--active", "All")
  end

  test "selected_panel shows empty placeholder until a node is clicked", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_prototype_player() |> live(~p"/world")
    assert render(view) =~ "Nothing selected"
  end
end
