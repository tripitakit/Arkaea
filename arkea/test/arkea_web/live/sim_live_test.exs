defmodule ArkeaWeb.SimLiveTest do
  use ArkeaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "phase selector updates the focused phase", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#phase-inspector-title", "Surface")
    assert has_element?(view, "#biotope-scene[phx-update='ignore']")
    assert render(view) =~ "data-selected-phase=\"surface\""

    view
    |> element("button[data-phase='sediment']")
    |> render_click()

    assert has_element?(view, "#phase-inspector-title", "Sediment")
    assert render(view) =~ "data-selected-phase=\"sediment\""
  end

  test "operator console records queued interventions", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("button[phx-value-kind='antibiotic_dose']")
    |> render_click()

    assert render(view) =~ "Antibiotic dose"
    assert render(view) =~ "Surface"
  end
end
