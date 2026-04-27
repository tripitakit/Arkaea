defmodule Arkea.Repo.Migrations.CreatePlayers do
  use Ecto.Migration

  # DESIGN.md — Blocco 11 (player accounts, colonization cooldown).
  # Phase 1 minimale: email normalizzata (lowercase) via changeset + display_name + cooldown.
  # Niente citext: normalizzazione a lowercase gestita lato Elixir in Phase 1.
  # Auth completa (hash password, sessioni, token) rinviata a Phase 9.

  def change do
    create table(:players, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false, size: 320
      add :display_name, :string, null: false, size: 80
      add :colonization_cooldown_until, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:players, [:email])
  end
end
