defmodule ArkeaWeb.SeedLabLiveTest do
  use ArkeaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Arkea.Persistence.ArkeonBlueprint
  alias Arkea.Persistence.PlayerBiotope
  alias Arkea.Repo
  alias Arkea.Game.PrototypePlayer
  alias Arkea.Game.SeedLab
  alias Arkea.Game.World

  setup %{conn: conn} do
    cleanup_owned_biotopes()
    on_exit(&cleanup_owned_biotopes/0)
    {:ok, conn: log_in_prototype_player(conn)}
  end

  test "seed lab updates the ecotype preview", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/seed-lab")

    assert render(view) =~ "Seed lab"
    assert render(view) =~ "Eutrophic pond"

    html =
      view
      |> form("form.seed-form", %{
        "seed" => %{
          "starter_archetype" => "oligotrophic_lake",
          "metabolism_profile" => "thrifty",
          "membrane_profile" => "fortified",
          "regulation_profile" => "steady",
          "mobile_module" => "none",
          "seed_name" => "Lake Prime"
        }
      })
      |> render_change()

    assert html =~ "Lake Prime"
    assert html =~ "Oligotrophic lake"
  end

  test "seed lab provisions one owned home biotope and redirects to its viewport", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/seed-lab")

    view
    |> element("button[phx-click=append_domain][phx-value-type=substrate_binding]")
    |> render_click()

    view
    |> element("button[phx-click=append_domain][phx-value-type=dna_binding]")
    |> render_click()

    view
    |> element(
      "button[phx-click=toggle_intergenic][phx-value-family=expression][phx-value-module=sigma_promoter]"
    )
    |> render_click()

    view
    |> element(
      "button[phx-click=toggle_intergenic][phx-value-family=transfer][phx-value-module=orit_site]"
    )
    |> render_click()

    view
    |> element(
      "button[phx-click=toggle_intergenic][phx-value-family=duplication][phx-value-module=repeat_array]"
    )
    |> render_click()

    view
    |> element("button[phx-click=commit_custom_gene]")
    |> render_click()

    view
    |> form("form.seed-form", %{
      "seed" => %{
        "starter_archetype" => "mesophilic_soil",
        "metabolism_profile" => "balanced",
        "membrane_profile" => "salinity_tuned",
        "regulation_profile" => "responsive",
        "mobile_module" => "conjugative_plasmid",
        "seed_name" => "Soil Pioneer"
      }
    })
    |> render_change()

    view
    |> form("form.seed-form")
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    assert path =~ "/biotopes/"

    biotope_id = String.replace_prefix(path, "/biotopes/", "")
    assert Enum.any?(World.list_biotopes(PrototypePlayer.id()), &(&1.id == biotope_id))

    blueprint = Repo.one!(ArkeonBlueprint)
    player_biotope = Repo.one!(PlayerBiotope)

    assert blueprint.player_id == PrototypePlayer.id()
    assert blueprint.name == "Soil Pioneer"

    assert blueprint.phenotype_spec["custom_genes"] == [
             %{
               "domains" => ["substrate_binding", "dna_binding"],
               "intergenic" => %{
                 "expression" => ["sigma_promoter"],
                 "transfer" => ["orit_site"],
                 "duplication" => ["repeat_array"]
               }
             }
           ]

    assert player_biotope.player_id == PrototypePlayer.id()
    assert player_biotope.biotope_id == biotope_id
    assert player_biotope.role == "home"
    assert player_biotope.source_blueprint_id == blueprint.id

    {:ok, biotope_view, _html} = live(conn, path)
    assert render(biotope_view) =~ "Procedural biotope viewport"
    assert render(biotope_view) =~ "Mesophilic Soil"
  end

  test "seed lab becomes read-only after the first home is provisioned", %{conn: conn} do
    {:ok, biotope_id} =
      SeedLab.provision_home(%{
        "seed_name" => "Locked Seed",
        "starter_archetype" => "oligotrophic_lake",
        "metabolism_profile" => "thrifty",
        "membrane_profile" => "fortified",
        "regulation_profile" => "steady",
        "mobile_module" => "latent_prophage"
      })

    {:ok, view, html} = live(conn, ~p"/seed-lab")

    assert html =~ "Arkeon seed locked"
    assert html =~ "Locked Seed"

    assert html =~
             "This committed atlas is now read-only, but gene composition and intergenic blocks remain inspectable."

    assert html =~ "Arkeon phenotype portrait"
    assert html =~ ~s(href="/biotopes/#{biotope_id}")
    assert html =~ "<fieldset disabled"

    changed_html =
      view
      |> form("form.seed-form", %{
        "seed" => %{
          "starter_archetype" => "mesophilic_soil",
          "metabolism_profile" => "bloom",
          "membrane_profile" => "porous",
          "regulation_profile" => "mutator",
          "mobile_module" => "none",
          "seed_name" => "Mutation Attempt"
        }
      })
      |> render_change()

    assert changed_html =~ "Locked Seed"
    refute changed_html =~ "Mutation Attempt"
    assert Repo.aggregate(ArkeonBlueprint, :count) == 1
    assert Repo.aggregate(PlayerBiotope, :count) == 1
  end

  test "seed lab custom gene editor composes domains and intergenic blocks", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/seed-lab")

    assert html =~ "Chromosome atlas"
    assert html =~ "Custom chromosome gene designer"
    assert html =~ "Expression control"
    assert html =~ "Transfer"
    assert html =~ "Duplication"

    view
    |> element("button[phx-click=append_domain][phx-value-type=substrate_binding]")
    |> render_click()

    view
    |> element("button[phx-click=append_domain][phx-value-type=dna_binding]")
    |> render_click()

    view
    |> element(
      "button[phx-click=toggle_intergenic][phx-value-family=expression][phx-value-module=sigma_promoter]"
    )
    |> render_click()

    view
    |> element(
      "button[phx-click=toggle_intergenic][phx-value-family=transfer][phx-value-module=orit_site]"
    )
    |> render_click()

    view
    |> element(
      "button[phx-click=toggle_intergenic][phx-value-family=duplication][phx-value-module=repeat_array]"
    )
    |> render_click()

    html_before_commit = render(view)
    assert html_before_commit =~ "expr:sigma"
    assert html_before_commit =~ "xfer:oriT"
    assert html_before_commit =~ "dup:repeat"

    view
    |> element("button[phx-click=commit_custom_gene]")
    |> render_click()

    html_after_commit = render(view)
    assert html_after_commit =~ "Custom gene 1"
    assert html_after_commit =~ "Custom G2"
    assert html_after_commit =~ "Custom chromosome cassette"
    assert html_after_commit =~ "Substrate Binding"
    assert html_after_commit =~ "DNA Binding"
    assert html_after_commit =~ "expr:sigma"
    assert html_after_commit =~ "xfer:oriT"
    assert html_after_commit =~ "dup:repeat"
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

    Repo.delete_all(PlayerBiotope)
    Repo.delete_all(ArkeonBlueprint)
  end
end
