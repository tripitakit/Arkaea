defmodule Arkea.Repo.Migrations.AddPlayerAssetsAndInterventionLogs do
  use Ecto.Migration

  def up do
    create table(:arkeon_blueprints, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :player_id,
          references(:players, type: :binary_id, on_delete: :delete_all),
          null: false

      add :name, :string, null: false, size: 80
      add :starter_archetype, :string, null: false, size: 40
      add :phenotype_spec, :map, null: false
      add :genome_binary, :binary, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:arkeon_blueprints, [:player_id])
    create index(:arkeon_blueprints, [:player_id, :inserted_at])

    create table(:player_biotopes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :player_id,
          references(:players, type: :binary_id, on_delete: :delete_all),
          null: false

      add :biotope_id,
          references(:biotopes, type: :binary_id, on_delete: :delete_all),
          null: false

      add :role, :string, null: false, size: 16

      add :source_blueprint_id,
          references(:arkeon_blueprints, type: :binary_id, on_delete: :nilify_all)

      add :claimed_at_tick, :bigint

      timestamps(type: :utc_datetime_usec)
    end

    create index(:player_biotopes, [:player_id])
    create unique_index(:player_biotopes, [:biotope_id])

    create unique_index(
             :player_biotopes,
             [:player_id],
             name: :player_biotopes_one_active_home_idx,
             where: "role = 'home'"
           )

    create table(:intervention_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :player_id,
          references(:players, type: :binary_id, on_delete: :delete_all),
          null: false

      add :biotope_id,
          references(:biotopes, type: :binary_id, on_delete: :delete_all),
          null: false

      add :kind, :string, null: false, size: 40
      add :scope, :string, null: false, size: 16
      add :phase_name, :string, size: 40
      add :payload, :map, null: false, default: %{}
      add :occurred_at_tick, :bigint
      add :executed_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:intervention_logs, [:biotope_id, :executed_at])
    create index(:intervention_logs, [:player_id, :executed_at])
    create index(:intervention_logs, [:kind, :executed_at])
  end

  def down do
    drop_if_exists index(:intervention_logs, [:kind, :executed_at])
    drop_if_exists index(:intervention_logs, [:player_id, :executed_at])
    drop_if_exists index(:intervention_logs, [:biotope_id, :executed_at])
    drop_if_exists table(:intervention_logs)

    drop_if_exists index(:player_biotopes, [:player_id])
    drop_if_exists index(:player_biotopes, [:biotope_id])

    drop_if_exists index(:player_biotopes, [:player_id],
                     name: :player_biotopes_one_active_home_idx
                   )

    drop_if_exists table(:player_biotopes)

    drop_if_exists index(:arkeon_blueprints, [:player_id, :inserted_at])
    drop_if_exists index(:arkeon_blueprints, [:player_id])
    drop_if_exists table(:arkeon_blueprints)
  end
end
