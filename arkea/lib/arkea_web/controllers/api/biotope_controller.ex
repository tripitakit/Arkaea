defmodule ArkeaWeb.API.BiotopeController do
  @moduledoc """
  Read-only export endpoints for one biotope (UI Phase F).

  Endpoints:

  - `GET /api/biotopes/:id/snapshot.json` — full JSON-friendly export
    of the current biotope state, audit log, and time-series samples.
  - `GET /api/biotopes/:id/audit.csv` — flat CSV of the audit log,
    filterable by `?from_tick=&to_tick=&kind=`.

  Authentication is enforced upstream by the `:require_authenticated`
  pipeline; the controller itself only verifies that the biotope exists
  and is readable from the audit table.
  """
  use ArkeaWeb, :controller

  import Ecto.Query

  alias Arkea.Persistence.AuditLog
  alias Arkea.Persistence.TimeSeries
  alias Arkea.Sim.Biotope.Server, as: BiotopeServer
  alias Arkea.Views.SnapshotExport

  @snapshot_audit_limit 1_000

  def snapshot(conn, %{"id" => biotope_id}) do
    case load_state(biotope_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Biotope #{biotope_id} not found or not running."})

      state ->
        audit = recent_audit(biotope_id)
        samples = TimeSeries.list(biotope_id)
        export = SnapshotExport.build(state, audit, samples)

        conn
        |> put_resp_header(
          "content-disposition",
          ~s|attachment; filename="biotope-#{biotope_id}.json"|
        )
        |> json(export)
    end
  end

  def audit(conn, %{"id" => biotope_id} = params) do
    rows = filtered_audit(biotope_id, params)

    csv = build_csv(rows)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s|attachment; filename="audit-#{biotope_id}.csv"|)
    |> send_resp(200, csv)
  end

  # ---------------------------------------------------------------------------

  defp load_state(biotope_id) do
    BiotopeServer.get_state(biotope_id)
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp recent_audit(biotope_id) do
    Arkea.Repo.all(
      from a in AuditLog,
        where: a.target_biotope_id == ^biotope_id,
        order_by: [desc: a.occurred_at_tick],
        limit: @snapshot_audit_limit
    )
  end

  defp filtered_audit(biotope_id, params) do
    from_tick = parse_int(params["from_tick"])
    to_tick = parse_int(params["to_tick"])
    kind = params["kind"]

    query =
      from a in AuditLog,
        where: a.target_biotope_id == ^biotope_id,
        order_by: [asc: a.occurred_at_tick]

    query =
      case from_tick do
        nil -> query
        n -> from(a in query, where: a.occurred_at_tick >= ^n)
      end

    query =
      case to_tick do
        nil -> query
        n -> from(a in query, where: a.occurred_at_tick <= ^n)
      end

    query =
      case kind do
        nil -> query
        "" -> query
        k when is_binary(k) -> from(a in query, where: a.event_type == ^k)
      end

    Arkea.Repo.all(query)
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(n) when is_binary(n) do
    case Integer.parse(n) do
      {value, _} -> value
      _ -> nil
    end
  end

  defp parse_int(n) when is_integer(n), do: n
  defp parse_int(_), do: nil

  @csv_header ~w(occurred_at occurred_at_tick event_type target_lineage_id actor_player_id payload_json)

  defp build_csv(rows) do
    [
      Enum.join(@csv_header, ",")
      | Enum.map(rows, &csv_row/1)
    ]
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp csv_row(%AuditLog{} = entry) do
    [
      DateTime.to_iso8601(entry.occurred_at),
      Integer.to_string(entry.occurred_at_tick),
      entry.event_type,
      entry.target_lineage_id || "",
      entry.actor_player_id || "",
      payload_json(entry.payload)
    ]
    |> Enum.map(&escape_field/1)
    |> Enum.join(",")
  end

  defp payload_json(nil), do: "{}"
  defp payload_json(map) when is_map(map), do: Jason.encode!(map)
  defp payload_json(other), do: Jason.encode!(other)

  defp escape_field(value) when is_binary(value) do
    if String.contains?(value, [",", "\"", "\n"]) do
      escaped = String.replace(value, "\"", "\"\"")
      "\"" <> escaped <> "\""
    else
      value
    end
  end

  defp escape_field(other), do: to_string(other)
end
