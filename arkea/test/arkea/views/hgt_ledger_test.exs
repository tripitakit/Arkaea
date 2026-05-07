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

  describe "Sub-task 1.6 channel-direct event types" do
    test "transformation_event row appears with origin as donor" do
      audit = [
        %AuditLog{
          event_type: "transformation_event",
          occurred_at_tick: 42,
          target_lineage_id: "r-1",
          payload: %{"origin_lineage_id" => "o-1", "gene_index" => 5}
        }
      ]

      %{entries: entries, total: total} = HGTLedger.build(audit)
      assert total == 1
      [entry] = entries
      assert entry.kind == "transformation_event"
      assert entry.recipient_id == "r-1"
      assert entry.donor_id == "o-1"
      assert entry.payload["gene_index"] == 5
    end

    test "transduction_event row appears with donor_lineage_id as donor" do
      audit = [
        %AuditLog{
          event_type: "transduction_event",
          occurred_at_tick: 30,
          target_lineage_id: "r-2",
          payload: %{"donor_lineage_id" => "d-2", "payload_kind" => "generalized"}
        }
      ]

      %{entries: entries, total: total} = HGTLedger.build(audit)
      assert total == 1
      [entry] = entries
      assert entry.kind == "transduction_event"
      assert entry.recipient_id == "r-2"
      assert entry.donor_id == "d-2"
    end

    test "phage_infection row appears with origin as donor" do
      audit = [
        %AuditLog{
          event_type: "phage_infection",
          occurred_at_tick: 7,
          target_lineage_id: "r-3",
          payload: %{
            "mode" => "lytic",
            "virion_id" => "v-1",
            "origin_lineage_id" => "o-3"
          }
        }
      ]

      %{entries: entries, total: total} = HGTLedger.build(audit)
      assert total == 1
      [entry] = entries
      assert entry.kind == "phage_infection"
      assert entry.recipient_id == "r-3"
      assert entry.donor_id == "o-3"
    end

    test "rm_digestion row appears with origin as donor" do
      audit = [
        %AuditLog{
          event_type: "rm_digestion",
          occurred_at_tick: 11,
          target_lineage_id: "r-4",
          payload: %{"virion_id" => "v-2", "origin_lineage_id" => "o-4"}
        }
      ]

      %{entries: entries, total: total} = HGTLedger.build(audit)
      assert total == 1
      [entry] = entries
      assert entry.kind == "rm_digestion"
      assert entry.recipient_id == "r-4"
      assert entry.donor_id == "o-4"
    end

    test "hgt_transfer row appears with donor_lineage_id as donor" do
      audit = [
        %AuditLog{
          event_type: "hgt_transfer",
          occurred_at_tick: 15,
          target_lineage_id: "r-5",
          payload: %{
            "channel" => "conjugation",
            "donor_lineage_id" => "d-5",
            "plasmid_inc_group" => 3
          }
        }
      ]

      %{entries: entries, total: total} = HGTLedger.build(audit)
      assert total == 1
      [entry] = entries
      assert entry.kind == "hgt_transfer"
      assert entry.recipient_id == "r-5"
      assert entry.donor_id == "d-5"
      assert entry.payload["plasmid_inc_group"] == 3
    end

    test "plasmid_displaced row appears with new_donor as donor" do
      audit = [
        %AuditLog{
          event_type: "plasmid_displaced",
          occurred_at_tick: 20,
          target_lineage_id: "r-6",
          payload: %{
            "displaced_inc_group" => 5,
            "new_donor_lineage_id" => "d-6"
          }
        }
      ]

      %{entries: entries, total: total} = HGTLedger.build(audit)
      assert total == 1
      [entry] = entries
      assert entry.kind == "plasmid_displaced"
      assert entry.recipient_id == "r-6"
      assert entry.donor_id == "d-6"
    end
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
