defmodule ArkeaWeb.CommunityLiveTest do
  use ArkeaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Arkea.Persistence.AuditLog
  alias Arkea.Repo

  setup %{conn: conn} do
    # Sandbox rolls back the test transaction on exit; no on_exit cleanup
    # needed (and running it inside the rolled-back sandbox produces
    # sporadic OwnershipError in CI).
    Repo.delete_all(AuditLog)
    {:ok, conn: log_in_prototype_player(conn)}
  end

  test "anonymous player cannot open the community liveview" do
    conn = build_conn()
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/community")
  end

  test "renders an empty state when no community runs exist", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/community")
    assert html =~ "Multi-seed runs"
    assert html =~ "No community runs yet"
  end

  test "lists biotopes that received a community-mode inoculation", %{conn: conn} do
    insert_community_event!("biotope-1", "saline_estuary", ["seed-A", "seed-B"])
    insert_community_event!("biotope-2", "mesophilic_soil", ["seed-X"])

    {:ok, _view, html} = live(conn, ~p"/community")
    assert html =~ "Saline Estuary"
    assert html =~ "Mesophilic Soil"
    assert html =~ "seeds 2"
    assert html =~ "seeds 1"
  end

  defp insert_community_event!(biotope_id, archetype, founders) do
    {:ok, _entry} =
      Repo.insert(
        AuditLog.changeset(%AuditLog{}, %{
          event_type: "community_provisioned",
          target_biotope_id: Ecto.UUID.generate(),
          payload: %{
            "biotope_id" => biotope_id,
            "archetype" => archetype,
            "founders" => founders,
            "phase_name" => "surface"
          },
          occurred_at_tick: 0,
          occurred_at: DateTime.utc_now()
        })
      )
  end
end
