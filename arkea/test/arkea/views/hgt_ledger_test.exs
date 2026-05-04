defmodule Arkea.Views.HGTLedgerTest do
  use ExUnit.Case, async: true

  alias Arkea.Persistence.AuditLog
  alias Arkea.Views.HGTLedger

  test "build/2 with no audit returns empty ledger" do
    assert %{entries: [], flows: [], total: 0} = HGTLedger.build([])
  end

  test "filters non-HGT events" do
    audit = [
      audit_entry("hgt_event", 5, "donor-a", "recipient-b"),
      audit_entry("intervention", 6, nil, nil),
      audit_entry("lineage_extinct", 7, nil, "recipient-b")
    ]

    %{entries: entries, total: total} = HGTLedger.build(audit)

    assert total == 1
    assert hd(entries).kind == "hgt_event"
  end

  test "aggregates flows by donor → recipient pair" do
    audit = [
      audit_entry("hgt_event", 1, "donor-a", "recipient-x"),
      audit_entry("hgt_event", 5, "donor-a", "recipient-x"),
      audit_entry("hgt_event", 7, "donor-a", "recipient-y")
    ]

    %{flows: flows} = HGTLedger.build(audit)

    pairs = Map.new(flows, fn f -> {{f.donor_id, f.recipient_id}, f.count} end)
    assert pairs[{"donor-a", "recipient-x"}] == 2
    assert pairs[{"donor-a", "recipient-y"}] == 1
  end

  test "kind filter narrows to a single event type" do
    audit = [
      audit_entry("hgt_event", 1, "a", "b"),
      audit_entry("rm_digestion", 2, "a", "b")
    ]

    %{entries: entries} = HGTLedger.build(audit, kind: "rm_digestion")
    assert length(entries) == 1
    assert hd(entries).kind == "rm_digestion"
  end

  defp audit_entry(type, tick, donor, recipient) do
    %AuditLog{
      event_type: type,
      occurred_at_tick: tick,
      target_lineage_id: recipient,
      payload: %{"parent_id" => donor}
    }
  end
end
