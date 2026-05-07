defmodule Arkea.Persistence.AuditWriterTest do
  use Arkea.DataCase, async: true

  alias Arkea.Persistence.AuditLog
  alias Arkea.Persistence.AuditWriter

  @occurred_at ~U[2026-05-06 10:00:00.000000Z]

  defp insert!(events, biotope_id, tick) do
    {:ok, rows} = AuditWriter.insert_events(Repo, biotope_id, tick, events, @occurred_at)
    rows
  end

  defp fetch_one!(event_type, biotope_id) do
    Repo.one!(
      from a in AuditLog,
        where: a.event_type == ^event_type and a.target_biotope_id == ^biotope_id
    )
  end

  describe "new event types: HGT/transduction/phage" do
    test ":transformation_event persists with recipient as target lineage" do
      biotope_id = Ecto.UUID.generate()
      recipient_id = Ecto.UUID.generate()
      origin_id = Ecto.UUID.generate()

      events = [
        %{
          type: :transformation_event,
          tick: 42,
          recipient_lineage_id: recipient_id,
          origin_lineage_id: origin_id,
          gene_index: 5
        }
      ]

      insert!(events, biotope_id, 42)
      row = fetch_one!("transformation_event", biotope_id)

      assert row.target_lineage_id == recipient_id
      assert row.target_biotope_id == biotope_id
      assert row.occurred_at_tick == 42
      assert row.payload["origin_lineage_id"] == origin_id
      assert row.payload["gene_index"] == 5
    end

    test ":phage_infection (lytic) persists with recipient as target and stringified mode" do
      biotope_id = Ecto.UUID.generate()
      recipient_id = Ecto.UUID.generate()
      origin_id = Ecto.UUID.generate()
      virion_id = Ecto.UUID.generate()

      events = [
        %{
          type: :phage_infection,
          tick: 7,
          mode: :lytic,
          recipient_lineage_id: recipient_id,
          virion_id: virion_id,
          origin_lineage_id: origin_id
        }
      ]

      insert!(events, biotope_id, 7)
      row = fetch_one!("phage_infection", biotope_id)

      assert row.target_lineage_id == recipient_id
      assert row.payload["mode"] == "lytic"
      assert row.payload["virion_id"] == virion_id
      assert row.payload["origin_lineage_id"] == origin_id
    end

    test ":phage_infection (lysogenic) persists with stringified mode" do
      biotope_id = Ecto.UUID.generate()
      recipient_id = Ecto.UUID.generate()
      virion_id = Ecto.UUID.generate()

      events = [
        %{
          type: :phage_infection,
          tick: 8,
          mode: :lysogenic,
          recipient_lineage_id: recipient_id,
          virion_id: virion_id,
          origin_lineage_id: nil
        }
      ]

      insert!(events, biotope_id, 8)
      row = fetch_one!("phage_infection", biotope_id)

      assert row.payload["mode"] == "lysogenic"
      assert row.payload["origin_lineage_id"] == nil
    end

    test ":rm_digestion persists with recipient as target lineage" do
      biotope_id = Ecto.UUID.generate()
      recipient_id = Ecto.UUID.generate()
      origin_id = Ecto.UUID.generate()
      virion_id = Ecto.UUID.generate()

      events = [
        %{
          type: :rm_digestion,
          tick: 11,
          recipient_lineage_id: recipient_id,
          virion_id: virion_id,
          origin_lineage_id: origin_id
        }
      ]

      insert!(events, biotope_id, 11)
      row = fetch_one!("rm_digestion", biotope_id)

      assert row.target_lineage_id == recipient_id
      assert row.payload["virion_id"] == virion_id
      assert row.payload["origin_lineage_id"] == origin_id
    end

    test ":hgt_transfer persists with recipient as target and stringified channel" do
      biotope_id = Ecto.UUID.generate()
      donor_id = Ecto.UUID.generate()
      recipient_id = Ecto.UUID.generate()

      events = [
        %{
          type: :hgt_transfer,
          channel: :conjugation,
          donor_lineage_id: donor_id,
          recipient_lineage_id: recipient_id,
          # inc_group is non_neg_integer in production (see Arkea.Genome).
          plasmid_inc_group: 3,
          tick: 15
        }
      ]

      insert!(events, biotope_id, 15)

      # Channel-direct handler emits "hgt_transfer" as the event_type.
      row = fetch_one!("hgt_transfer", biotope_id)

      assert row.target_lineage_id == recipient_id
      assert row.payload["channel"] == "conjugation"
      assert row.payload["donor_lineage_id"] == donor_id
      assert row.payload["plasmid_inc_group"] == 3
    end

    test ":plasmid_displaced persists with recipient as target" do
      biotope_id = Ecto.UUID.generate()
      recipient_id = Ecto.UUID.generate()
      new_donor_id = Ecto.UUID.generate()

      events = [
        %{
          type: :plasmid_displaced,
          tick: 20,
          recipient_lineage_id: recipient_id,
          # inc_group is non_neg_integer in production (see Arkea.Genome).
          displaced_inc_group: 5,
          new_donor_lineage_id: new_donor_id
        }
      ]

      insert!(events, biotope_id, 20)
      row = fetch_one!("plasmid_displaced", biotope_id)

      assert row.target_lineage_id == recipient_id
      assert row.payload["displaced_inc_group"] == 5
      assert row.payload["new_donor_lineage_id"] == new_donor_id
    end

    test ":transduction_event persists with recipient as target and stringified payload_kind" do
      biotope_id = Ecto.UUID.generate()
      donor_id = Ecto.UUID.generate()
      recipient_id = Ecto.UUID.generate()

      events = [
        %{
          type: :transduction_event,
          tick: 30,
          donor_lineage_id: donor_id,
          recipient_lineage_id: recipient_id,
          payload_kind: :generalized
        }
      ]

      insert!(events, biotope_id, 30)
      row = fetch_one!("transduction_event", biotope_id)

      assert row.target_lineage_id == recipient_id
      assert row.payload["donor_lineage_id"] == donor_id
      assert row.payload["payload_kind"] == "generalized"
    end
  end

  describe "new event types: bacteriocin and error catastrophe" do
    test ":bacteriocin_kill persists with victim as target lineage" do
      biotope_id = Ecto.UUID.generate()
      victim_id = Ecto.UUID.generate()
      producer_a = Ecto.UUID.generate()
      producer_b = Ecto.UUID.generate()

      events = [
        %{
          type: :bacteriocin_kill,
          tick: 33,
          victim_lineage_id: victim_id,
          producer_lineage_ids: [producer_a, producer_b],
          surface_tag_target: "tag_alpha"
        }
      ]

      insert!(events, biotope_id, 33)
      row = fetch_one!("bacteriocin_kill", biotope_id)

      assert row.target_lineage_id == victim_id
      assert row.payload["producer_lineage_ids"] == [producer_a, producer_b]
      assert row.payload["surface_tag_target"] == "tag_alpha"
    end

    test ":error_catastrophe_death persists with parent lineage as target" do
      biotope_id = Ecto.UUID.generate()
      parent_id = Ecto.UUID.generate()

      events = [
        %{
          type: :error_catastrophe_death,
          tick: 99,
          lineage_id: parent_id,
          mu: 0.42,
          genome_size: 1024
        }
      ]

      insert!(events, biotope_id, 99)
      row = fetch_one!("error_catastrophe_death", biotope_id)

      assert row.target_lineage_id == parent_id
      assert row.payload["mu"] == 0.42
      assert row.payload["genome_size"] == 1024
    end
  end

  describe "nil origin_lineage_id" do
    test ":transformation_event with nil origin persists without crash" do
      biotope_id = Ecto.UUID.generate()
      recipient_id = Ecto.UUID.generate()

      events = [
        %{
          type: :transformation_event,
          tick: 50,
          recipient_lineage_id: recipient_id,
          origin_lineage_id: nil,
          gene_index: 0
        }
      ]

      insert!(events, biotope_id, 50)
      row = fetch_one!("transformation_event", biotope_id)

      assert row.target_lineage_id == recipient_id
      # JSON null round-trips as Elixir nil
      assert Map.fetch!(row.payload, "origin_lineage_id") == nil
      assert row.payload["gene_index"] == 0
    end
  end

  describe "pre-existing diff-derived events still handled" do
    test ":lineage_extinct (payload-shape) still persists with target_lineage_id" do
      biotope_id = Ecto.UUID.generate()
      lineage_id = Ecto.UUID.generate()

      events = [
        %{
          type: :lineage_extinct,
          payload: %{lineage_id: lineage_id, tick: 5}
        }
      ]

      insert!(events, biotope_id, 5)
      row = fetch_one!("lineage_extinct", biotope_id)

      assert row.target_lineage_id == lineage_id
      assert row.occurred_at_tick == 5
    end

    test ":lineage_born (payload-shape) still persists" do
      biotope_id = Ecto.UUID.generate()
      lineage_id = Ecto.UUID.generate()
      parent_id = Ecto.UUID.generate()

      events = [
        %{
          type: :lineage_born,
          payload: %{
            lineage_id: lineage_id,
            parent_id: parent_id,
            original_seed_id: nil,
            tick: 6
          }
        }
      ]

      insert!(events, biotope_id, 6)
      row = fetch_one!("lineage_born", biotope_id)

      assert row.target_lineage_id == lineage_id
      assert row.payload["parent_id"] == parent_id
    end
  end
end
