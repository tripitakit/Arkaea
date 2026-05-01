defmodule Arkea.Persistence.BiotopeSnapshot do
  @moduledoc """
  Periodic full-state snapshot copied from a previously persisted WAL row.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          biotope_id: Ecto.UUID.t() | nil,
          tick_count: non_neg_integer() | nil,
          source_wal_entry_id: Ecto.UUID.t() | nil,
          state_binary: binary() | nil,
          inserted_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "biotope_snapshots" do
    field :biotope_id, :binary_id
    field :tick_count, :integer
    field :source_wal_entry_id, :binary_id
    field :state_binary, :binary

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:biotope_id, :tick_count, :source_wal_entry_id, :state_binary]

  @doc "Changeset for snapshot inserts or upserts."
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_number(:tick_count, greater_than_or_equal_to: 0)
    |> unique_constraint([:biotope_id, :tick_count])
  end
end
