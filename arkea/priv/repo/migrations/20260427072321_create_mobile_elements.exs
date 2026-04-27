defmodule Arkea.Repo.Migrations.CreateMobileElements do
  use Ecto.Migration

  # DESIGN.md — Blocco 13 (origin tracking plasmidi/profagi/fagi liberi).
  # origin_lineage_id e origin_biotope_id: nullable, senza FK — il lineage/biotopo di origine
  # può essere estinto o rimosso; conserviamo l'ID come tombstone per il tracciamento storico.
  # genes: bytea serializzato con :erlang.term_to_binary/1 [:compressed].
  # Indice su origin_biotope_id: query di detection ops (quanti elementi mobili provengono
  # da un dato biotopo in un dato intervallo di tick).
  # Indice su kind: filtraggio per tipo (plasmid | prophage | free_phage).

  def change do
    create table(:mobile_elements, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :kind, :string, null: false, size: 20
      add :genes, :binary
      add :origin_lineage_id, :binary_id
      add :origin_biotope_id, :binary_id
      add :created_at_tick, :bigint, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create constraint(:mobile_elements, :kind_valid,
             check: "kind IN ('plasmid', 'prophage', 'free_phage')"
           )

    create index(:mobile_elements, [:origin_biotope_id])
    create index(:mobile_elements, [:kind])
  end
end
