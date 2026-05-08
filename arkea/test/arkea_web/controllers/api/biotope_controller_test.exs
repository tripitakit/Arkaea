defmodule ArkeaWeb.API.BiotopeControllerTest do
  use ArkeaWeb.ConnCase

  alias Arkea.Game.PrototypePlayer
  alias Arkea.Game.SeedLab
  alias Arkea.Game.World

  setup %{conn: conn} do
    cleanup_owned_biotopes()
    on_exit(&cleanup_owned_biotopes/0)
    {:ok, biotope_id} = provision_test_biotope()
    {:ok, conn: log_in_prototype_player(conn), biotope_id: biotope_id}
  end

  test "GET /api/biotopes/:id/snapshot returns the JSON-friendly export", %{
    conn: conn,
    biotope_id: id
  } do
    conn = get(conn, ~p"/api/biotopes/#{id}/snapshot")
    assert response(conn, 200)

    body = json_response(conn, 200)
    assert body["format_version"] == 1
    assert body["biotope"]["id"] == id
    assert is_list(body["phases"])
    assert is_list(body["lineages"])
    assert is_list(body["audit_log"])
    assert is_list(body["time_series"])
  end

  test "GET /api/biotopes/:id/snapshot 404s for an unknown biotope", %{conn: conn} do
    conn = get(conn, ~p"/api/biotopes/00000000-0000-0000-0000-000000000000/snapshot")
    assert json_response(conn, 404)["error"] =~ "not found"
  end

  test "GET /api/biotopes/:id/audit returns CSV with header + payload column", %{
    conn: conn,
    biotope_id: id
  } do
    conn = get(conn, ~p"/api/biotopes/#{id}/audit")
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> List.first() =~ "text/csv"

    body = response(conn, 200)
    [header | _] = String.split(body, "\n")

    assert header ==
             "occurred_at,occurred_at_tick,event_type,target_lineage_id,actor_player_id,payload_json"
  end

  describe "Phase 24 / 6.8 — notebook exports" do
    test "GET /api/biotopes/:id/notebook-export.csv returns long-format trait CSV", %{
      conn: conn,
      biotope_id: id
    } do
      conn = get(conn, ~p"/api/biotopes/#{id}/notebook-export.csv")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> List.first() =~ "text/csv"
      assert get_resp_header(conn, "content-disposition") |> List.first() =~ "notebook-#{id}.csv"

      body = response(conn, 200)
      [header | _] = String.split(body, "\n")
      assert header == "tick,lineage_id,trait,value"
    end

    test "GET /api/biotopes/:id/notebook-export.jsonl returns NDJSON with header", %{
      conn: conn,
      biotope_id: id
    } do
      conn = get(conn, ~p"/api/biotopes/#{id}/notebook-export.jsonl")
      assert conn.status == 200

      assert get_resp_header(conn, "content-type") |> List.first() =~ "application/x-ndjson"

      assert get_resp_header(conn, "content-disposition") |> List.first() =~
               "notebook-#{id}.jsonl"

      body = response(conn, 200)
      # Empty body is acceptable on a freshly-provisioned biotope
      # (no annotations / no samples / no audit yet); when present,
      # every non-empty line must parse as JSON with the documented
      # `record_type` discriminator.
      lines = body |> String.split("\n", trim: true)

      for line <- lines do
        decoded = Jason.decode!(line)
        assert decoded["record_type"] in ["annotation", "phenotype_trait", "audit_event"]
        assert decoded["biotope_id"] == id
      end
    end
  end

  defp provision_test_biotope do
    SeedLab.provision_home(%{
      "seed_name" => "Export Test",
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
