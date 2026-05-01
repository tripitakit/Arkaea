defmodule Arkea.Repo.Migrations.AddRuntimePersistence do
  use Ecto.Migration

  def up do
    create table(:biotope_wal_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :biotope_id, :binary_id, null: false
      add :tick_count, :bigint, null: false
      add :transition_kind, :string, null: false, size: 32
      add :state_binary, :binary, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:biotope_wal_entries, [:biotope_id, :tick_count])
    create index(:biotope_wal_entries, [:biotope_id, :inserted_at])

    create table(:biotope_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :biotope_id, :binary_id, null: false
      add :tick_count, :bigint, null: false
      add :source_wal_entry_id, :binary_id, null: false
      add :state_binary, :binary, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:biotope_snapshots, [:biotope_id, :tick_count])
    create unique_index(:biotope_snapshots, [:source_wal_entry_id])
    create index(:biotope_snapshots, [:biotope_id, :inserted_at])

    Oban.Migrations.up()
  end

  def down do
    Oban.Migrations.down()

    drop_if_exists index(:biotope_snapshots, [:biotope_id, :inserted_at])
    drop_if_exists unique_index(:biotope_snapshots, [:source_wal_entry_id])
    drop_if_exists unique_index(:biotope_snapshots, [:biotope_id, :tick_count])
    drop_if_exists table(:biotope_snapshots)

    drop_if_exists index(:biotope_wal_entries, [:biotope_id, :inserted_at])
    drop_if_exists index(:biotope_wal_entries, [:biotope_id, :tick_count])
    drop_if_exists table(:biotope_wal_entries)
  end
end
