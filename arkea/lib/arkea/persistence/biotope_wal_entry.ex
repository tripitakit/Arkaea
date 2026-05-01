defmodule Arkea.Persistence.BiotopeWalEntry do
  @moduledoc """
  Full-state WAL rows written after each tick or migration transition.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          biotope_id: Ecto.UUID.t() | nil,
          tick_count: non_neg_integer() | nil,
          transition_kind: String.t() | nil,
          state_binary: binary() | nil,
          inserted_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "biotope_wal_entries" do
    field :biotope_id, :binary_id
    field :tick_count, :integer
    field :transition_kind, :string
    field :state_binary, :binary

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:biotope_id, :tick_count, :transition_kind, :state_binary]

  @doc "Changeset for append-only WAL inserts."
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_number(:tick_count, greater_than_or_equal_to: 0)
    |> validate_length(:transition_kind, min: 1, max: 32)
  end
end
