defmodule Arkea.Repo.Migrations.CreateBiotopes do
  use Ecto.Migration

  # DESIGN.md — Blocco 10 (nodi del world graph, 8 archetipi, zone, coordinate planari).
  # owner_player_id FK: on_delete :nilify_all — il biotopo sopravvive come "wild" se il
  # player viene rimosso (campo diventa NULL). Conforme alla spec "wild quando player rimosso".
  # Constraint CHECK su archetype inline: evita enum Postgres per flessibilità futura.

  @archetypes ~w(
    oligotrophic_lake
    eutrophic_pond
    marine_sediment
    hydrothermal_vent
    acid_mine_drainage
    methanogenic_bog
    mesophilic_soil
    saline_estuary
  )

  def change do
    create table(:biotopes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :archetype, :string, null: false, size: 40
      add :zone, :string, null: false, size: 40
      add :x, :float, null: false
      add :y, :float, null: false

      add :owner_player_id,
          references(:players, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:biotopes, :archetype_valid,
             check: "archetype IN (#{Enum.map_join(@archetypes, ", ", &"'#{&1}'")})"
           )

    create index(:biotopes, [:owner_player_id])
    create index(:biotopes, [:zone, :archetype])
  end
end
