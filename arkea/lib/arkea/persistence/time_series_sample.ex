defmodule Arkea.Persistence.TimeSeriesSample do
  @moduledoc """
  Ecto schema for one row of `time_series_samples` (UI Phase B).

  Append-only: rows are never updated. The aggregate cap is enforced by
  pruning oldest rows for a given biotope when the row count exceeds
  `Arkea.Persistence.TimeSeries.cap/0`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type kind :: :abundance | :metabolite_pool | :signal_pool | :biomass | :dna_damage

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          biotope_id: Ecto.UUID.t() | nil,
          tick: non_neg_integer() | nil,
          kind: String.t() | nil,
          scope_id: String.t() | nil,
          payload: map() | nil,
          inserted_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "time_series_samples" do
    field :biotope_id, :binary_id
    field :tick, :integer
    field :kind, :string
    field :scope_id, :string
    field :payload, :map
    field :inserted_at, :utc_datetime_usec
  end

  @required [:biotope_id, :tick, :kind, :inserted_at]
  @optional [:scope_id, :payload]

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(sample, attrs) do
    sample
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_number(:tick, greater_than_or_equal_to: 0)
    |> validate_length(:kind, min: 1, max: 40)
    |> put_default_payload()
  end

  defp put_default_payload(changeset) do
    case get_field(changeset, :payload) do
      nil -> put_change(changeset, :payload, %{})
      _ -> changeset
    end
  end
end
