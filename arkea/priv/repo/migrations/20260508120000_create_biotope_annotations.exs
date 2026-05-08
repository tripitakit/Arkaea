defmodule Arkea.Repo.Migrations.CreateBiotopeAnnotations do
  use Ecto.Migration

  # Phase 24 / 6.1 — biotope-level lab notebook.
  #
  # Free-form notes attached by a player to a specific tick of a
  # biotope's history. The text is the smallest possible scientific
  # primitive of a lab notebook: "tick N: I observed X, here's my
  # hypothesis about Y". Tick references in the body become the
  # anchors of the time-aware permalinks delivered in 6.2.
  #
  # Schema:
  # - `id` (uuid)
  # - `biotope_id` (uuid, indexed) — owning biotope
  # - `player_id` (uuid, indexed) — author; only the author may
  #   delete their own note (no shared editing in v1)
  # - `tick` (integer, >= 0) — tick of reference
  # - `body` (text, 1..2000 chars; enforced at the changeset level)
  # - `inserted_at`, `updated_at` (timestamps)
  def change do
    create table(:biotope_annotations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :biotope_id, :binary_id, null: false
      add :player_id, :binary_id, null: false
      add :tick, :integer, null: false
      add :body, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Primary access pattern: list a biotope's notes ordered by tick.
    create index(:biotope_annotations, [:biotope_id, :tick])

    # Author lookups (deletion path; "my notes" listings).
    create index(:biotope_annotations, [:player_id])

    # Tick must never go negative.
    create constraint(:biotope_annotations, :tick_non_negative, check: "tick >= 0")
  end
end
