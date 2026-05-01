defmodule Arkea.Persistence.PlayerBiotope do
  @moduledoc """
  Explicit relation between a player and a currently controlled biotope.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @roles ~w(home colonized)

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          player_id: Ecto.UUID.t() | nil,
          biotope_id: Ecto.UUID.t() | nil,
          role: String.t() | nil,
          source_blueprint_id: Ecto.UUID.t() | nil,
          claimed_at_tick: non_neg_integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "player_biotopes" do
    field :role, :string
    field :claimed_at_tick, :integer

    belongs_to :player, Arkea.Persistence.Player
    belongs_to :biotope, Arkea.Persistence.Biotope
    belongs_to :source_blueprint, Arkea.Persistence.ArkeonBlueprint

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:player_id, :biotope_id, :role]
  @optional_fields [:source_blueprint_id, :claimed_at_tick]

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(player_biotope, attrs) do
    player_biotope
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:role, @roles)
    |> validate_number(:claimed_at_tick, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:player_id)
    |> foreign_key_constraint(:biotope_id)
    |> foreign_key_constraint(:source_blueprint_id)
    |> unique_constraint(:biotope_id)
    |> unique_constraint(:player_id, name: :player_biotopes_one_active_home_idx)
  end
end
