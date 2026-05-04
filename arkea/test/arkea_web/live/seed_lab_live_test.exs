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

    assert render(view) =~ "Seed Lab"
    assert render(view) =~ "Visual genome editor"
    assert render(view) =~ "Unnamed seed"
    assert render(view) =~ "Choose a starter biotope archetype to preview insertion coordinates"

    html =
      view
      |> form("form.arkea-seed-form", %{
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
    assert html =~ "Spawn zone"
    assert html =~ "phases"
  end

  test "seed lab requires an explicit biotope choice before colonization", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/seed-lab")

    html =
      view
      |> form("form.arkea-seed-form", %{
        "seed" => %{
          "metabolism_profile" => "balanced",
          "membrane_profile" => "porous",
          "regulation_profile" => "responsive",
          "mobile_module" => "none",
          "seed_name" => "Explicit Choice Only"
        }
      })
      |> render_submit()

    assert html =~ "Choose the first biotope to colonize."
    assert html =~ "Choose a starter biotope"
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
    |> form("form.arkea-seed-form", %{
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
    |> form("form.arkea-seed-form")
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
    # Biotope view shell post-U4: SVG scene + arkea-biotope layout, archetype chip
    assert render(biotope_view) =~ "arkea-biotope__scene"
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

    # Lock banner copy (preserved from pre-U5 wording)
    assert html =~ "This phenotype/genome configuration is already bound"

    assert html =~ "Arkeon phenotype portrait"
    assert html =~ ~s(href="/biotopes/#{biotope_id}")
    assert html =~ "<fieldset disabled"

    changed_html =
      view
      |> form("form.arkea-seed-form", %{
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

    # Expand the gene inspector so the cassette manifest is rendered.
    view
    |> element("button[phx-click=toggle_inspector]")
    |> render_click()

    html_after_commit = render(view)
    # Custom gene committed: cassette manifest in the inspector
    assert html_after_commit =~ "Custom chromosome cassette"
    assert html_after_commit =~ "Substrate Binding"
    assert html_after_commit =~ "DNA Binding"
    assert html_after_commit =~ "expr:sigma"
    assert html_after_commit =~ "xfer:oriT"
    assert html_after_commit =~ "dup:repeat"
    # Circular chromosome canvas is rendered (U5)
    assert html_after_commit =~ "arkea-genome-canvas"
  end

  test "draft gene domain reorder buttons swap order; remove drops a domain", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/seed-lab")

    # Compose: substrate_binding then dna_binding
    view
    |> element("button[phx-click=append_domain][phx-value-type=substrate_binding]")
    |> render_click()

    view
    |> element("button[phx-click=append_domain][phx-value-type=dna_binding]")
    |> render_click()

    html = render(view)
    # Each draft domain row appears with ↑/↓/× controls
    assert html =~ ~s|phx-click="move_draft_domain"|
    assert html =~ ~s|phx-click="remove_draft_domain"|

    # Move the first domain (idx 0) down → order becomes dna_binding, substrate_binding
    view
    |> element(
      ~s|button[phx-click="move_draft_domain"][phx-value-index="0"][phx-value-to="down"]|
    )
    |> render_click()

    # The first rendered label after the move must be "DNA Binding"
    # (it was at idx 1 before the swap; now it sits at idx 0).
    new_html = render(view)

    [_, first_label_block | _] =
      String.split(new_html, "arkea-draft-domain__label", parts: 3)

    assert first_label_block =~ "DNA Binding"

    # Remove index 0 (currently dna_binding) → only substrate_binding remains
    view
    |> element(~s|button[phx-click="remove_draft_domain"][phx-value-index="0"]|)
    |> render_click()

    final_html = render(view)
    # Exactly one draft row remains; it carries Substrate Binding at index 0.
    assert final_html =~ ~s|data-draft-index="0"|
    refute final_html =~ ~s|data-draft-index="1"|

    [_, draft_li | _] =
      String.split(final_html, ~s|data-draft-index="0"|, parts: 2) ++ [""]

    [draft_li_content | _] = String.split(draft_li, "</li>", parts: 2)
    assert draft_li_content =~ "Substrate Binding"
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
