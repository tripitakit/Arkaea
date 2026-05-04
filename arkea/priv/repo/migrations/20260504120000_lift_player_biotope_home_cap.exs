defmodule Arkea.Repo.Migrations.LiftPlayerBiotopeHomeCap do
  use Ecto.Migration

  # Replace the partial unique index that allowed exactly one `role = 'home'`
  # row per player with a regular partial index (still useful for per-player
  # home-count lookups). The application enforces the new cap (max 3 homes)
  # in `Arkea.Game.SeedLab.can_provision_home?/1`.
  def up do
    drop_if_exists index(:player_biotopes, [:player_id],
                     name: :player_biotopes_one_active_home_idx
                   )

    create_if_not_exists index(:player_biotopes, [:player_id],
                           name: :player_biotopes_home_lookup_idx,
                           where: "role = 'home'"
                         )
  end

  def down do
    drop_if_exists index(:player_biotopes, [:player_id], name: :player_biotopes_home_lookup_idx)

    create_if_not_exists unique_index(
                           :player_biotopes,
                           [:player_id],
                           name: :player_biotopes_one_active_home_idx,
                           where: "role = 'home'"
                         )
  end
end
