defmodule ArkeaWeb.API.BiotopeController do
  @moduledoc """
  Read-only export endpoints for one biotope (UI Phase F).

  Endpoints:

  - `GET /api/biotopes/:id/snapshot.json` — full JSON-friendly export
    of the current biotope state, audit log, and time-series samples.
  - `GET /api/biotopes/:id/audit.csv` — flat CSV of the audit log,
    filterable by `?from_tick=&to_tick=&kind=`.
  - `GET /api/biotopes/:id/notebook-export.csv` — long-format CSV of
    the per-lineage `phenotype_trait` samples, suitable for direct
    `pandas.read_csv` / `polars.read_csv`. Columns: `tick,
    lineage_id, trait, value`.
  - `GET /api/biotopes/:id/notebook-export.jsonl` — NDJSON dump of
    the time-series + audit log + lab-notebook annotations, one
    record per line, suitable for `polars.read_ndjson` /
    streaming readers.

  Authentication is enforced upstream by the `:require_authenticated`
  pipeline; the controller itself only verifies that the biotope exists
  and is readable from the audit table.
  """
  use ArkeaWeb, :controller

  import Ecto.Query

  alias Arkea.Notebook
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

  # Phase 24 / 6.8 — long-format CSV of phenotype-trait samples for
  # direct pandas / polars ingestion. Columns: tick, lineage_id,
  # trait, value. Booleans → 0/1 (matches the chart convention); a
  # missing trait skips the row rather than emitting `null`. The
  # caller can do `pl.read_csv(...).pivot(index=…, columns="trait",
  # values="value")` to get a wide matrix.
  def notebook_export_csv(conn, %{"id" => biotope_id}) do
    samples = TimeSeries.list(biotope_id, kind: "phenotype_trait")
    csv = build_trait_csv(samples)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header(
      "content-disposition",
      ~s|attachment; filename="notebook-#{biotope_id}.csv"|
    )
    |> send_resp(200, csv)
  end

  # Phase 24 / 6.8 — NDJSON dump of the lab notebook (annotations +
  # bookmarks + phenotype-trait samples + audit log). One record
  # per line so downstream readers can stream-process. Each record
  # carries a top-level `record_type` discriminator.
  def notebook_export_jsonl(conn, %{"id" => biotope_id}) do
    annotations = Notebook.list_for_biotope(biotope_id)
    samples = TimeSeries.list(biotope_id, kind: "phenotype_trait")
    audit = recent_audit(biotope_id)

    body = build_ndjson(biotope_id, annotations, samples, audit)

    conn
    |> put_resp_content_type("application/x-ndjson")
    |> put_resp_header(
      "content-disposition",
      ~s|attachment; filename="notebook-#{biotope_id}.jsonl"|
    )
    |> send_resp(200, body)
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
    |> Enum.map_join(",", &escape_field/1)
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

  # ---------------------------------------------------------------------------
  # Phase 24 / 6.8 — notebook export builders.

  @trait_csv_header ~w(tick lineage_id trait value)

  defp build_trait_csv(samples) do
    rows =
      samples
      |> Enum.flat_map(&trait_csv_rows/1)
      |> Enum.map_join("\n", &Enum.map_join(&1, ",", fn v -> escape_field(v) end))

    Enum.join(@trait_csv_header, ",") <> "\n" <> rows <> "\n"
  end

  defp trait_csv_rows(sample) when is_map(sample) do
    payload = sample.payload || %{}

    payload
    |> Enum.map(fn {trait, value} -> {trait, trait_value_for_csv(value)} end)
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Enum.map(fn {trait, v} ->
      [Integer.to_string(sample.tick), sample.scope_id || "", trait, format_csv_value(v)]
    end)
  end

  # Boolean → 0 / 1 (chart convention); numbers pass through; other
  # types (lists, maps) are skipped at the long-format level (the
  # snapshot export is the right surface for those).
  defp trait_value_for_csv(true), do: 1
  defp trait_value_for_csv(false), do: 0
  defp trait_value_for_csv(v) when is_number(v), do: v
  defp trait_value_for_csv(_), do: nil

  defp format_csv_value(v) when is_integer(v), do: Integer.to_string(v)
  defp format_csv_value(v) when is_float(v), do: Float.to_string(v)
  defp format_csv_value(v), do: to_string(v)

  defp build_ndjson(biotope_id, annotations, samples, audit) do
    annotation_lines = Enum.map(annotations, &annotation_line(biotope_id, &1))
    sample_lines = Enum.map(samples, &sample_line(biotope_id, &1))
    audit_lines = Enum.map(audit, &audit_line(biotope_id, &1))

    (annotation_lines ++ sample_lines ++ audit_lines)
    |> Enum.map_join("\n", &Jason.encode!/1)
    |> Kernel.<>("\n")
  end

  defp annotation_line(biotope_id, %{} = a) do
    %{
      record_type: "annotation",
      biotope_id: biotope_id,
      annotation_id: a.id,
      tick: a.tick,
      body: a.body,
      bookmark: a.bookmark,
      player_id: a.player_id,
      inserted_at: a.inserted_at && DateTime.to_iso8601(a.inserted_at)
    }
  end

  defp sample_line(biotope_id, sample) do
    %{
      record_type: "phenotype_trait",
      biotope_id: biotope_id,
      tick: sample.tick,
      lineage_id: sample.scope_id,
      payload: sample.payload || %{}
    }
  end

  defp audit_line(biotope_id, %AuditLog{} = entry) do
    %{
      record_type: "audit_event",
      biotope_id: biotope_id,
      tick: entry.occurred_at_tick,
      event_type: entry.event_type,
      target_lineage_id: entry.target_lineage_id,
      payload: entry.payload || %{},
      occurred_at: entry.occurred_at && DateTime.to_iso8601(entry.occurred_at)
    }
  end
end
