defmodule Arkea.Repo.Migrations.CreateAuditLog do
  use Ecto.Migration

  # DESIGN.md — Blocco 13 (audit log anti-griefing, origin tracking elementi mobili).
  # Tabella append-only: nessun UPDATE né DELETE nel flusso normale.
  # Niente FK esterne: actor/target_biotope/target_lineage sono nullable e i referenti
  # possono venire prunati; manteniamo i valori come tombstone IDs senza integrità referenziale
  # (l'audit log deve sopravvivere alla cancellazione dei referenti).
  # Indice su (target_biotope_id, occurred_at_tick): query per detection pattern per-biotopo.
  # occurred_at è utc_datetime_usec per ordering preciso tra eventi dello stesso tick.

  def change do
    create table(:audit_log, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_type, :string, null: false, size: 60
      add :actor_player_id, :binary_id
      add :target_biotope_id, :binary_id
      add :target_lineage_id, :binary_id
      add :payload, :map, null: false, default: %{}
      add :occurred_at_tick, :bigint, null: false
      add :occurred_at, :utc_datetime_usec, null: false
    end

    create index(:audit_log, [:event_type])
    create index(:audit_log, [:actor_player_id])
    create index(:audit_log, [:target_biotope_id, :occurred_at_tick])
  end
end
