defmodule Arkea.Repo.Migrations.CreateTimeSeriesSamples do
  use Ecto.Migration

  # Time-series sample table for the UI optimisation Phase B.
  #
  # Stores periodic snapshots of ephemeral simulation state (per-lineage
  # abundance, phase metabolite pools, signal pools, biomass, dna_damage)
  # so that the trends viewer in Phase C can render trajectories.
  #
  # Columns:
  # - `biotope_id` (binary_id) — owning biotope; FK without referential
  #   integrity to keep audit-style append-only semantics.
  # - `tick` (integer) — tick of the source state.
  # - `kind` (string) — sample type: "abundance", "metabolite_pool",
  #   "signal_pool", "biomass", "dna_damage", ...
  # - `scope_id` (binary) — optional secondary key (lineage_id for
  #   abundance/biomass; phase name for pool samples; null for biotope-
  #   scoped aggregates).
  # - `payload` (jsonb) — sample contents.
  # - `inserted_at` (utc) — wall-clock for ordering / pruning by age.
  #
  # Sampling cadence is enforced at the writer (default every 5 ticks);
  # the schema imposes no period.
  def change do
    create table(:time_series_samples, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :biotope_id, :binary_id, null: false
      add :tick, :integer, null: false
      add :kind, :string, null: false, size: 40
      add :scope_id, :string, size: 80
      add :payload, :map, null: false, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false
    end

    # Time-range queries for a biotope are the dominant access pattern
    # (the trends viewer reads N..M ticks for a single biotope).
    create index(:time_series_samples, [:biotope_id, :tick])

    # Per-kind queries (e.g. all metabolite_pool samples for a tick range)
    # benefit from a covering compound index.
    create index(:time_series_samples, [:biotope_id, :kind, :tick])

    # Pruning: when the per-biotope cap is reached the oldest samples
    # need to be deleted by inserted_at.
    create index(:time_series_samples, [:biotope_id, :inserted_at])
  end
end
