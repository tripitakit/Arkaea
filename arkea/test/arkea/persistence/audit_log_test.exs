defmodule Arkea.Persistence.AuditLogTest do
  use Arkea.DataCase, async: true

  alias Arkea.Persistence.AuditLog

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        event_type: "colonization",
        occurred_at_tick: 10,
        occurred_at: ~U[2026-04-26 09:00:00.000000Z]
      },
      overrides
    )
  end

  describe "changeset/2" do
    test "valida un evento valido" do
      changeset = AuditLog.changeset(%AuditLog{}, valid_attrs())
      assert changeset.valid?
    end

    test "richiede event_type, occurred_at_tick, occurred_at" do
      changeset = AuditLog.changeset(%AuditLog{}, %{})
      refute changeset.valid?
      assert errors_on(changeset).event_type
      assert errors_on(changeset).occurred_at_tick
      assert errors_on(changeset).occurred_at
    end

    test "rifiuta occurred_at_tick negativo" do
      changeset = AuditLog.changeset(%AuditLog{}, valid_attrs(%{occurred_at_tick: -1}))
      refute changeset.valid?
      assert errors_on(changeset).occurred_at_tick
    end

    test "defaulta payload a mappa vuota se assente" do
      changeset = AuditLog.changeset(%AuditLog{}, valid_attrs())
      assert get_change(changeset, :payload) == %{}
    end

    test "accetta payload popolato" do
      payload = %{"lineage_id" => "abc-123", "delta_fitness" => 0.15}
      changeset = AuditLog.changeset(%AuditLog{}, valid_attrs(%{payload: payload}))
      assert changeset.valid?
    end

    test "accetta actor_player_id nullable" do
      changeset =
        AuditLog.changeset(%AuditLog{}, valid_attrs(%{actor_player_id: nil}))

      assert changeset.valid?
    end
  end

  describe "insert + get" do
    test "inserisce e rilancia un evento di audit" do
      attrs =
        valid_attrs(%{
          event_type: "hgt_event",
          actor_player_id: Ecto.UUID.generate(),
          target_biotope_id: Ecto.UUID.generate(),
          target_lineage_id: Ecto.UUID.generate(),
          payload: %{"mechanism" => "conjugation"},
          occurred_at_tick: 42
        })

      {:ok, entry} =
        %AuditLog{}
        |> AuditLog.changeset(attrs)
        |> Repo.insert()

      fetched = Repo.get!(AuditLog, entry.id)
      assert fetched.event_type == "hgt_event"
      assert fetched.occurred_at_tick == 42
      assert fetched.payload == %{"mechanism" => "conjugation"}
    end

    test "inserisce evento senza actor (wild event)" do
      {:ok, entry} =
        %AuditLog{}
        |> AuditLog.changeset(valid_attrs(%{event_type: "mass_lysis"}))
        |> Repo.insert()

      fetched = Repo.get!(AuditLog, entry.id)
      assert fetched.actor_player_id == nil
    end
  end
end
