defmodule ArkeaWeb.HelpLiveTest do
  use ArkeaWeb.ConnCase

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    {:ok, conn: log_in_prototype_player(conn)}
  end

  test "GET /help renders the user manual by default", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/help")

    assert html =~ "Documentazione Arkea"
    assert html =~ "User manual"
    assert html =~ "<h1>"
    # Manual table-of-contents should expose the language switcher anchor.
    assert html =~ "arkea-help__toc"
  end

  test "GET /help/design renders the DESIGN document", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/help/design")

    assert html =~ "Biological model (DESIGN)"
    assert html =~ "<h1>"
  end

  test "unknown doc slug shows an error", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/help/does-not-exist")
    assert html =~ "Documento non trovato"
  end

  test "all live views link to the unified Help nav entry", %{conn: conn} do
    for path <- [
          "/dashboard",
          "/world",
          "/seed-lab",
          "/audit",
          "/community",
          "/help"
        ] do
      conn = get(conn, path)
      html = html_response(conn, 200)
      assert html =~ ~s|href="/help"|, "missing /help link in #{path}"
      assert html =~ ~s|href="/dashboard"|, "missing /dashboard link in #{path}"
      assert html =~ ~s|href="/audit"|, "missing /audit link in #{path}"
    end
  end
end
