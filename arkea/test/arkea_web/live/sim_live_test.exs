defmodule ArkeaWeb.SimLiveTest do
  use ArkeaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Arkea.Game.PrototypePlayer
  alias Arkea.Game.SeedLab
  alias Arkea.Game.World

  setup %{conn: conn} do
    cleanup_owned_biotopes()
    on_exit(&cleanup_owned_biotopes/0)
    {:ok, biotope_id} = provision_test_biotope()
    {:ok, conn: log_in_prototype_player(conn), biotope_id: biotope_id}
  end

  test "renders the new biotope shell with sidebar, scene, bottom tabs", %{
    conn: conn,
    biotope_id: id
  } do
    {:ok, view, _html} = live(conn, ~p"/biotopes/#{id}")

    html = render(view)
    assert html =~ "arkea-shell"
    assert html =~ "arkea-biotope__sidebar"
    assert html =~ "arkea-biotope__scene"
    assert html =~ "arkea-biotope__bottom"
    # Scene SVG (replaces the old Pixi canvas)
    assert html =~ ~s|class="arkea-scene__svg"|
    # Phase inspector still in sidebar
    assert has_element?(view, "#phase-inspector-title")
    # Global nav present in shell
    assert has_element?(view, ".arkea-shell__nav-link", "World")
    assert has_element?(view, ".arkea-shell__nav-link", "Seed Lab")
  end

  test "phase list selects a different phase and updates the inspector", %{
    conn: conn,
    biotope_id: id
  } do
    {:ok, view, _html} = live(conn, ~p"/biotopes/#{id}")

    # Eutrophic pond seed has surface/water_column/sediment phases.
    # Default selection is the first phase; click sediment to switch.
    view
    |> element(~s|.arkea-phase-list__item[phx-value-phase="sediment"]|)
    |> render_click()

    assert has_element?(
             view,
             ~s|.arkea-phase-list__item--active[phx-value-phase="sediment"]|
           )

    assert has_element?(view, "#phase-inspector-title", "Sediment")
  end

  test "switching the bottom tab swaps the body content", %{conn: conn, biotope_id: id} do
    {:ok, view, _html} = live(conn, ~p"/biotopes/#{id}")

    # Default tab is events
    assert has_element?(view, ~s|.arkea-tabs__tab--active|, "Events")

    view |> element(~s|.arkea-tabs__tab[phx-value-tab="lineages"]|) |> render_click()
    assert has_element?(view, ~s|.arkea-tabs__tab--active|, "Lineages")
    assert render(view) =~ "Population board"

    view |> element(~s|.arkea-tabs__tab[phx-value-tab="chemistry"]|) |> render_click()
    assert has_element?(view, ~s|.arkea-tabs__tab--active|, "Chemistry")
    assert render(view) =~ "Metabolite pools"
  end

  test "Trends tab renders the population trajectory placeholder when there are no samples yet",
       %{conn: conn, biotope_id: id} do
    {:ok, view, _html} = live(conn, ~p"/biotopes/#{id}")

    view |> element(~s|.arkea-tabs__tab[phx-value-tab="trends"]|) |> render_click()
    assert has_element?(view, ~s|.arkea-tabs__tab--active|, "Trends")

    html = render(view)
    assert html =~ "Population trajectory"
    # A freshly provisioned biotope hasn't crossed a sampling boundary
    # yet, so the chart shows the empty placeholder rather than an SVG.
    assert html =~ "No abundance samples yet"
  end

  test "Phylogeny tab renders the lineage tree for the founder colony", %{
    conn: conn,
    biotope_id: id
  } do
    {:ok, view, _html} = live(conn, ~p"/biotopes/#{id}")

    view |> element(~s|.arkea-tabs__tab[phx-value-tab="phylogeny"]|) |> render_click()
    assert has_element?(view, ~s|.arkea-tabs__tab--active|, "Phylogeny")

    html = render(view)
    assert html =~ "Lineage genealogy"
    # Founder lineage is present so the SVG should render — not the
    # "no lineages" placeholder.
    assert html =~ "arkea-phylogeny__svg"
    refute html =~ "No lineages to plot"
  end

  test "clicking a lineage row opens the right drawer; close dismisses it", %{
    conn: conn,
    biotope_id: id
  } do
    {:ok, view, _html} = live(conn, ~p"/biotopes/#{id}")

    # Switch to lineages tab so rows are visible
    view |> element(~s|.arkea-tabs__tab[phx-value-tab="lineages"]|) |> render_click()

    view
    |> element("tr.arkea-lineage-row")
    |> render_click()

    assert has_element?(view, ".arkea-drawer--right")
    assert render(view) =~ "Selected lineage"

    view |> element(".arkea-drawer--right button", "Close") |> render_click()
    refute has_element?(view, ".arkea-drawer--right")
  end

  test "recolonize banner is hidden while the home colony is alive", %{conn: conn, biotope_id: id} do
    {:ok, _view, html} = live(conn, ~p"/biotopes/#{id}")
    refute html =~ "arkea-recolonize-banner"
    refute html =~ "Recolonize home"
  end

  test "extinct home surfaces the recolonize banner; clicking re-inoculates the biotope",
       %{conn: conn, biotope_id: id} do
    {:ok, view, _html} = live(conn, ~p"/biotopes/#{id}")

    # Force the biotope into extinction without waiting for natural collapse.
    [{pid, _}] = Registry.lookup(Arkea.Sim.Registry, {:biotope, id})
    :sys.replace_state(pid, fn state -> %{state | lineages: []} end)

    # Push a fresh tick into the LiveView so the assigns refresh from the
    # mutated state.
    Phoenix.PubSub.broadcast(
      Arkea.PubSub,
      "biotope:#{id}",
      {:biotope_tick, :sys.get_state(pid), []}
    )

    html_extinct = render(view)
    assert html_extinct =~ "arkea-recolonize-banner"
    assert html_extinct =~ "Colony extinct"
    # Banner exposes BOTH affordances: quick recolonize + edit-in-Seed-Lab.
    assert has_element?(view, "button[phx-click='recolonize_home']")

    assert has_element?(
             view,
             ~s|a[href="/seed-lab?recolonize=#{id}"]|,
             "Edit seed and recolonize"
           )

    view |> element("button[phx-click='recolonize_home']") |> render_click()

    state_after = :sys.get_state(pid)
    assert length(state_after.lineages) == 1
    assert Arkea.Sim.BiotopeState.total_abundance(state_after) == 420
  end

  test "operator console applies an intervention on a player-owned biotope", %{
    conn: conn,
    biotope_id: id
  } do
    {:ok, view, _html} = live(conn, ~p"/biotopes/#{id}")

    # Open the interventions tab to expose the action buttons
    view |> element(~s|.arkea-tabs__tab[phx-value-tab="interventions"]|) |> render_click()

    assert render(view) =~ "Slot open"

    view
    |> element("button[phx-value-kind='nutrient_pulse']")
    |> render_click()

    html = render(view)
    assert html =~ "Nutrient pulse"
    # Status flips to Locked after a successful intervention
    assert html =~ "Locked"
  end

  defp provision_test_biotope do
    SeedLab.provision_home(%{
      "seed_name" => "Sim Test Biotope",
      "starter_archetype" => "eutrophic_pond",
      "metabolism_profile" => "balanced",
      "membrane_profile" => "porous",
      "regulation_profile" => "responsive",
      "mobile_module" => "none"
    })
  end

  defp cleanup_owned_biotopes do
    World.list_biotopes(PrototypePlayer.id())
    |> Enum.filter(&(&1.owner_player_id == PrototypePlayer.id()))
    |> Enum.each(fn biotope ->
      case Registry.lookup(Arkea.Sim.Registry, {:biotope, biotope.id}) do
        [{pid, _value}] ->
          ref = Process.monitor(pid)
          Process.exit(pid, :shutdown)
          assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000

        [] ->
          :ok
      end
    end)
  end
end
