defmodule Arkea.Repo.Migrations.CreatePhases do
  use Ecto.Migration

  # DESIGN.md — Blocco 12 (sotto-ambienti del biotopo: surface, water_column, sediment, ecc.).
  # biotope_id FK: on_delete :delete_all — le phases non hanno significato senza il loro biotopo.
  # Unique constraint (biotope_id, name): un biotopo non può avere due fasi con lo stesso nome.
  # I pool (metabolite_pool, signal_pool, phage_pool) sono in-memory durante il tick;
  # vengono serializzati solo nel snapshot di stato completo (Phase 10). Non presenti qui.

  def change do
    create table(:phases, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :biotope_id,
          references(:biotopes, type: :binary_id, on_delete: :delete_all),
          null: false

      add :name, :string, null: false, size: 40
      add :temperature, :float, null: false
      add :ph, :float, null: false
      add :osmolarity, :float, null: false
      add :dilution_rate, :float, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:phases, [:biotope_id, :name])
  end
end
