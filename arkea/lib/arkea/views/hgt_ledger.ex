defmodule Arkea.Views.HGTLedger do
  @moduledoc """
  Pure shaper for the HGT ledger view (UI Phase E).

  Given a list of `Arkea.Persistence.AuditLog` entries, picks out the
  HGT-related events and produces:

  - `entries`: a flat per-event list (one row per audit entry) with
    donor / recipient / payload extracted into top-level fields.
  - `flows`: an aggregated `{donor, recipient}` rollup with the count
    of payloads transferred between the pair.
  - `kind_counts`: per-event-type counts for filter chips.

  This is the shaping layer for both the per-biotope ledger live view
  and the (future) Sankey provenance diagram.
  """

  alias Arkea.Persistence.AuditLog

  # Includes both legacy strings (`hgt_event`, `hgt_conjugation_attempt`,
  # `hgt_transformation_event`, `hgt_transduction_event`, `phage_burst`)
  # for back-compat with audit_log rows persisted before Sub-task 1.4
  # promoted channel-direct shapes, and the post-1.6 strings emitted by
  # `Arkea.Persistence.AuditWriter`: `hgt_transfer`, `transformation_event`,
  # `transduction_event`, `phage_infection`, `rm_digestion`,
  # `plasmid_displaced`.
  #
  # Phase 21 (Top 5 action #2 — channel disambiguation): generic
  # `hgt_transfer` rows whose payload carries `"channel" => <ch>` are
  # *promoted* to a channel-named kind in the view (today: `"conjugation"`).
  # `hgt_transfer` is still listed below so legacy permalinks (`?kind=
  # hgt_transfer`) keep matching, but new UI surfaces should prefer the
  # channel name.
  @hgt_types ~w(hgt_event hgt_transfer hgt_conjugation_attempt
                hgt_transformation_event hgt_transduction_event
                conjugation transformation_event transduction_event
                rm_digestion plasmid_displaced phage_burst phage_infection)

  # Channel names valid in the `payload["channel"]` field of `hgt_transfer`
  # rows. Each one also appears in `@hgt_types` so it can drive a filter
  # chip directly.
  @channel_kinds ~w(conjugation)

  @type entry :: %{
          id: String.t() | nil,
          tick: non_neg_integer(),
          kind: String.t(),
          donor_id: String.t() | nil,
          recipient_id: String.t(),
          payload: map(),
          occurred_at: DateTime.t() | nil
        }

  @type flow :: %{
          donor_id: String.t() | nil,
          recipient_id: String.t(),
          count: pos_integer(),
          last_tick: non_neg_integer(),
          kinds: [String.t()]
        }

  @type t :: %{
          entries: [entry()],
          flows: [flow()],
          kind_counts: %{required(String.t()) => non_neg_integer()},
          total: non_neg_integer()
        }

  @spec build([AuditLog.t()], keyword()) :: t()
  def build(audit, opts \\ []) when is_list(audit) do
    kind_filter = Keyword.get(opts, :kind)

    entries =
      audit
      |> Enum.filter(&hgt_event?/1)
      |> Enum.map(&entry_for/1)
      |> filter_by_kind(kind_filter)
      |> Enum.sort_by(& &1.tick, :desc)

    %{
      entries: entries,
      flows: aggregate_flows(entries),
      kind_counts: count_by_kind(entries),
      total: length(entries)
    }
  end

  defp hgt_event?(%AuditLog{event_type: type}), do: type in @hgt_types
  defp hgt_event?(_), do: false

  defp entry_for(%AuditLog{} = entry) do
    payload = entry.payload || %{}

    %{
      id: entry.id,
      tick: entry.occurred_at_tick,
      kind: derive_kind(entry.event_type, payload),
      donor_id: extract_donor_id(payload),
      recipient_id: entry.target_lineage_id || payload["lineage_id"],
      payload: payload,
      occurred_at: entry.occurred_at
    }
  end

  # Phase 21: promote a generic `hgt_transfer` row to its channel name when
  # the payload tags one. This lets the ledger UI show `conjugation (n)`
  # filter chips instead of an opaque `hgt_transfer (n)`. Rows without
  # `payload["channel"]` (legacy data, or future non-channel-tagged
  # transfers) keep `kind == "hgt_transfer"` for back-compat.
  defp derive_kind("hgt_transfer", payload) do
    case payload["channel"] do
      ch when is_binary(ch) and ch in @channel_kinds -> ch
      _ -> "hgt_transfer"
    end
  end

  defp derive_kind(event_type, _payload), do: event_type

  # Channel-direct shapes (Sub-task 1.6) hoist the upstream lineage under
  # type-specific keys: `donor_lineage_id` (hgt_transfer, transduction),
  # `origin_lineage_id` (transformation, phage_infection, rm_digestion),
  # `new_donor_lineage_id` (plasmid_displaced). Legacy diff-derived shapes
  # used `parent_id` / `donor_id` inside `payload`. Pick the first key
  # that resolves to a non-nil value.
  defp extract_donor_id(payload) do
    payload["donor_lineage_id"] ||
      payload["origin_lineage_id"] ||
      payload["new_donor_lineage_id"] ||
      payload["parent_id"] ||
      payload["donor_id"]
  end

  defp filter_by_kind(entries, nil), do: entries

  defp filter_by_kind(entries, kind) when is_binary(kind) do
    Enum.filter(entries, &(&1.kind == kind))
  end

  defp filter_by_kind(entries, kinds) when is_list(kinds) do
    set = MapSet.new(kinds)
    Enum.filter(entries, fn e -> MapSet.member?(set, e.kind) end)
  end

  defp aggregate_flows(entries) do
    entries
    |> Enum.group_by(fn e -> {e.donor_id, e.recipient_id} end)
    |> Enum.map(fn {{donor, recipient}, group} ->
      %{
        donor_id: donor,
        recipient_id: recipient,
        count: length(group),
        last_tick: Enum.max_by(group, & &1.tick).tick,
        kinds: group |> Enum.map(& &1.kind) |> Enum.uniq() |> Enum.sort()
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  defp count_by_kind(entries) do
    entries
    |> Enum.group_by(& &1.kind)
    |> Map.new(fn {kind, group} -> {kind, length(group)} end)
  end

  @doc "Canonical list of HGT-related event types (for filter UI chips)."
  @spec hgt_types() :: [String.t()]
  def hgt_types, do: @hgt_types
end
