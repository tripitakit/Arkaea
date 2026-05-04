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

  @hgt_types ~w(hgt_event hgt_transfer hgt_conjugation_attempt
                hgt_transformation_event hgt_transduction_event
                rm_digestion plasmid_displaced phage_burst phage_infection)

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
      kind: entry.event_type,
      donor_id: payload["parent_id"] || payload["donor_id"],
      recipient_id: entry.target_lineage_id || payload["lineage_id"],
      payload: payload,
      occurred_at: entry.occurred_at
    }
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
