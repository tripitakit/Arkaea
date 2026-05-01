defmodule Arkea.Persistence.InterventionLog do
  @moduledoc """
  Structured append-only log used for intervention budget enforcement.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @scopes ~w(phase biotope)

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          player_id: Ecto.UUID.t() | nil,
          biotope_id: Ecto.UUID.t() | nil,
          kind: String.t() | nil,
          scope: String.t() | nil,
          phase_name: String.t() | nil,
          payload: map() | nil,
          occurred_at_tick: non_neg_integer() | nil,
          executed_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "intervention_logs" do
    field :kind, :string
    field :scope, :string
    field :phase_name, :string
    field :payload, :map
    field :occurred_at_tick, :integer
    field :executed_at, :utc_datetime_usec

    belongs_to :player, Arkea.Persistence.Player
    belongs_to :biotope, Arkea.Persistence.Biotope

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:player_id, :biotope_id, :kind, :scope, :executed_at]
  @optional_fields [:phase_name, :payload, :occurred_at_tick]

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:kind, min: 1, max: 40)
    |> validate_inclusion(:scope, @scopes)
    |> validate_length(:phase_name, max: 40)
    |> validate_number(:occurred_at_tick, greater_than_or_equal_to: 0)
    |> put_default_payload()
    |> foreign_key_constraint(:player_id)
    |> foreign_key_constraint(:biotope_id)
  end

  defp put_default_payload(changeset) do
    case get_field(changeset, :payload) do
      nil -> put_change(changeset, :payload, %{})
      _ -> changeset
    end
  end
end
