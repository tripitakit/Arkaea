defmodule Arkea.Game.PlayerAssets do
  @moduledoc """
  Persistence helpers for prototype players, blueprints, and claimed biotopes.
  """

  import Ecto.Query

  alias Arkea.Persistence.ArkeonBlueprint
  alias Arkea.Persistence.Biotope
  alias Arkea.Persistence.Player
  alias Arkea.Persistence.PlayerBiotope
  alias Arkea.Repo
  alias Arkea.Sim.BiotopeState
  alias Ecto.Multi

  @spec ensure_player(map()) :: {:ok, Player.t()} | {:error, term()}
  def ensure_player(%{id: id, email: email, display_name: display_name}) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %Player{id: id}
    |> Player.changeset(%{email: email, display_name: display_name})
    |> Repo.insert(
      on_conflict: [set: [email: email, display_name: display_name, updated_at: now]],
      conflict_target: [:id]
    )
  end

  @spec active_home(binary()) :: PlayerBiotope.t() | nil
  def active_home(player_id) when is_binary(player_id) do
    Repo.one(
      from(row in PlayerBiotope,
        where: row.player_id == ^player_id and row.role == "home"
      )
    )
  end

  @spec active_home_with_blueprint(binary()) :: PlayerBiotope.t() | nil
  def active_home_with_blueprint(player_id) when is_binary(player_id) do
    Repo.one(
      from(row in PlayerBiotope,
        where: row.player_id == ^player_id and row.role == "home",
        preload: [:source_blueprint]
      )
    )
  end

  @spec controls_biotope?(binary(), binary()) :: boolean()
  def controls_biotope?(player_id, biotope_id)
      when is_binary(player_id) and is_binary(biotope_id) do
    Repo.exists?(
      from(row in PlayerBiotope,
        where: row.player_id == ^player_id and row.biotope_id == ^biotope_id
      )
    )
  end

  @spec register_home(map(), map(), term(), BiotopeState.t()) ::
          {:ok, %{blueprint: ArkeonBlueprint.t(), player_biotope: PlayerBiotope.t()}}
          | {:error, atom(), term(), map()}
  def register_home(player_profile, spec, genome, %BiotopeState{} = state) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    player_changeset =
      %Player{id: player_profile.id}
      |> Player.changeset(%{
        email: player_profile.email,
        display_name: player_profile.display_name
      })

    biotope_changeset =
      %Biotope{id: state.id}
      |> Biotope.changeset(%{
        archetype: Atom.to_string(state.archetype),
        zone: Atom.to_string(state.zone),
        x: state.x,
        y: state.y,
        owner_player_id: player_profile.id
      })

    blueprint_attrs = %{
      player_id: player_profile.id,
      name: spec.seed_name,
      starter_archetype: Atom.to_string(spec.starter_archetype),
      phenotype_spec: blueprint_spec(spec),
      genome_binary: ArkeonBlueprint.dump_genome!(genome)
    }

    Multi.new()
    |> Multi.insert(
      :player,
      player_changeset,
      on_conflict: [
        set: [
          email: player_profile.email,
          display_name: player_profile.display_name,
          updated_at: now
        ]
      ],
      conflict_target: [:id]
    )
    |> Multi.insert(
      :biotope,
      biotope_changeset,
      on_conflict: [
        set: [
          archetype: Atom.to_string(state.archetype),
          zone: Atom.to_string(state.zone),
          x: state.x,
          y: state.y,
          owner_player_id: player_profile.id,
          updated_at: now
        ]
      ],
      conflict_target: [:id]
    )
    |> Multi.insert(:blueprint, ArkeonBlueprint.changeset(%ArkeonBlueprint{}, blueprint_attrs))
    |> Multi.insert(:player_biotope, fn %{blueprint: blueprint} ->
      PlayerBiotope.changeset(%PlayerBiotope{}, %{
        player_id: player_profile.id,
        biotope_id: state.id,
        role: "home",
        source_blueprint_id: blueprint.id,
        claimed_at_tick: state.tick_count
      })
    end)
    |> Repo.transaction()
  end

  @doc """
  Insert a new blueprint and re-link the player's existing home biotope to
  it. Used when an extinct home is recolonized with an edited seed: the
  old blueprint stays in the table for audit/history and the
  `player_biotope.source_blueprint_id` foreign key is moved to the new row.
  """
  @spec register_home_recolonization(map(), map(), term()) ::
          {:ok, %{blueprint: ArkeonBlueprint.t(), player_biotope: PlayerBiotope.t()}}
          | {:error, atom(), term(), map()}
  def register_home_recolonization(player_profile, spec, genome) do
    blueprint_attrs = %{
      player_id: player_profile.id,
      name: spec.seed_name,
      starter_archetype: Atom.to_string(spec.starter_archetype),
      phenotype_spec: blueprint_spec(spec),
      genome_binary: ArkeonBlueprint.dump_genome!(genome)
    }

    Multi.new()
    |> Multi.insert(:blueprint, ArkeonBlueprint.changeset(%ArkeonBlueprint{}, blueprint_attrs))
    |> Multi.run(:player_biotope, fn repo, %{blueprint: new_blueprint} ->
      case active_home_with_blueprint(player_profile.id) do
        %PlayerBiotope{} = pb ->
          pb
          |> PlayerBiotope.changeset(%{source_blueprint_id: new_blueprint.id})
          |> repo.update()

        nil ->
          {:error, :no_home}
      end
    end)
    |> Repo.transaction()
  end

  defp blueprint_spec(spec) do
    %{
      "seed_name" => spec.seed_name,
      "starter_archetype" => Atom.to_string(spec.starter_archetype),
      "metabolism_profile" => spec.metabolism_profile,
      "membrane_profile" => spec.membrane_profile,
      "regulation_profile" => spec.regulation_profile,
      "mobile_module" => spec.mobile_module,
      "custom_genes" =>
        Enum.map(spec.custom_genes, fn gene ->
          %{
            "domains" => gene.domains,
            "intergenic" => %{
              "expression" => gene.intergenic.expression,
              "transfer" => gene.intergenic.transfer,
              "duplication" => gene.intergenic.duplication
            }
          }
        end)
    }
  end
end
