defmodule ArkeaWeb.AuditLiveTest do
  use ArkeaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Arkea.Persistence.AuditLog
  alias Arkea.Repo

  setup %{conn: conn} do
    # The Ecto sandbox rolls back the test transaction on exit, so we only
    # need to clear stale rows committed by previous (non-sandboxed) runs at
    # setup. No on_exit cleanup — running it inside the rolled-back sandbox
    # can produce sporadic OwnershipError in CI.
    Repo.delete_all(AuditLog)
    {:ok, conn: log_in_prototype_player(conn)}
  end

  test "anonymous player cannot open the audit liveview", %{conn: _conn} do
    conn = build_conn()
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/audit")
  end

  test "renders an empty state when the audit_log is empty", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/audit")
    assert html =~ "Global event stream"
    assert html =~ "No audit events yet"
  end

  test "lists persisted events and supports filter tabs", %{conn: conn} do
    # Sub-task 1.6 replaced the diff-derived `hgt_event` umbrella with
    # the channel-direct `hgt_transfer` type emitted by AuditWriter.
    insert_event!("hgt_transfer", %{"donor_lineage_id" => "lin-A"})
    insert_event!("mutation_notable", %{"lineage_id" => "lin-B"})
    insert_event!("intervention", %{"kind" => "nutrient_pulse"})

    {:ok, view, html} = live(conn, ~p"/audit")
    assert html =~ "hgt_transfer"
    assert html =~ "mutation_notable"
    assert html =~ "intervention"

    # Filter to Conjugation (hgt_transfer) only — the others should
    # disappear from the table
    view
    |> element(~s|button[phx-click="filter"][phx-value-to="hgt_transfer"]|)
    |> render_click()

    html_filtered = render(view)
    assert html_filtered =~ "hgt_transfer"
    refute html_filtered =~ ">mutation_notable<"
    refute html_filtered =~ ">intervention<"
  end

  test "pager next/prev advances offset", %{conn: conn} do
    # 60 events → 2 pages of 50 + 10 (page_size = 50 internal)
    for i <- 1..60, do: insert_event!("hgt_transfer", %{"i" => i})

    {:ok, view, _html} = live(conn, ~p"/audit")
    assert render(view) =~ "1–50 of 60"

    view
    |> element(~s|button[phx-click="page"][phx-value-to="next"]|)
    |> render_click()

    assert render(view) =~ "51–60 of 60"

    view
    |> element(~s|button[phx-click="page"][phx-value-to="prev"]|)
    |> render_click()

    assert render(view) =~ "1–50 of 60"
  end

  defp insert_event!(type, payload) do
    {:ok, _entry} =
      Repo.insert(
        AuditLog.changeset(%AuditLog{}, %{
          event_type: type,
          target_biotope_id: Ecto.UUID.generate(),
          payload: payload,
          occurred_at_tick: 0,
          occurred_at: DateTime.utc_now()
        })
      )
  end
end
