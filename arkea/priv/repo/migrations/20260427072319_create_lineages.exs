defmodule Arkea.Repo.Migrations.CreateLineages do
  use Ecto.Migration

  # DESIGN.md — Blocco 4 (lignaggi attivi, unità evolutiva con genome + abbondanze per fase).
  # biotope_id FK: on_delete :delete_all — un lineage orfano è privo di significato.
  # parent_id FK: on_delete :nilify_all — l'estinzione del parent non rimuove i discendenti;
  #   il campo diventa NULL (il discendente diventa de-facto founder del sotto-albero).
  # clade_ref_id: semplice index non-FK — può puntare a sé stesso (founder) o a un lineage
  #   già estinto (clade reference genome, introdotto in Phase 4 delta-encoding).
  # genome / delta_genome: bytea, serializzati con :erlang.term_to_binary/1 [:compressed].
  # abundance_by_phase: jsonb — mappa %{phase_name_string => integer} per analytics.
  # Indice composito (biotope_id, created_at_tick) per recovery e pruning per-tick.

  def change do
    create table(:lineages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :biotope_id,
          references(:biotopes, type: :binary_id, on_delete: :delete_all),
          null: false

      add :parent_id, references(:lineages, type: :binary_id, on_delete: :nilify_all)
      add :clade_ref_id, :binary_id, null: false

      add :genome, :binary
      add :delta_genome, :binary

      add :abundance_by_phase, :map, null: false
      add :fitness_cache, :float
      add :created_at_tick, :bigint, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:lineages, [:biotope_id])
    create index(:lineages, [:parent_id])
    create index(:lineages, [:clade_ref_id])
    create index(:lineages, [:biotope_id, :created_at_tick])
  end
end
