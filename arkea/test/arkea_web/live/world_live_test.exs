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

  test "archetype panel renders the breakdown when biotopes are alive", %{conn: conn} do
    # Provision a home so World.overview returns a non-empty
    # archetype_breakdown — the bug we are guarding against was a
    # FunctionClauseError on the {arch, count} pattern that surfaced
    # only when the breakdown list was non-empty.
    cleanup = fn ->
      Arkea.Repo.delete_all(Arkea.Persistence.PlayerBiotope)
      Arkea.Repo.delete_all(Arkea.Persistence.ArkeonBlueprint)
    end

    cleanup.()
    on_exit(cleanup)

    {:ok, _id} =
      Arkea.Game.SeedLab.provision_home(%{
        "seed_name" => "World Probe",
        "starter_archetype" => "eutrophic_pond",
        "metabolism_profile" => "balanced",
        "membrane_profile" => "porous",
        "regulation_profile" => "responsive",
        "mobile_module" => "none"
      })

    {:ok, _view, html} = conn |> log_in_prototype_player() |> live(~p"/world")

    assert html =~ "Archetypes"
    assert html =~ "arkea-world__archetype-bar"
    # The breakdown surfaces the canonical archetype label.
    assert html =~ "Eutrophic Pond"
    # Each visible biotope marker carries its live lineage count
    # rendered inside the core circle.
    assert html =~ "arkea-world__node-count"
  end
end
