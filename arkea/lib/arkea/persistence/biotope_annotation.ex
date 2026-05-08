defmodule Arkea.Persistence.BiotopeAnnotation do
  @moduledoc """
  Ecto schema for one row of `biotope_annotations` (Phase 24 / 6.1).

  A player-authored free-form note attached to a specific tick of a
  biotope's history. The smallest scientific primitive of a lab
  notebook: "tick N: I observed X, here's my hypothesis about Y".

  Author and biotope are referenced by their UUIDs without
  declarative `references`-level FK constraints — keeps the writer
  cheap (no extra round-trip) and matches the pattern used by
  `Arkea.Persistence.AuditLog` and `TimeSeriesSample`. Authorisation
  (only the author can delete their own note) is enforced at the
  context layer (`Arkea.Notebook`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          biotope_id: Ecto.UUID.t() | nil,
          player_id: Ecto.UUID.t() | nil,
          tick: non_neg_integer() | nil,
          body: String.t() | nil,
          bookmark: boolean() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "biotope_annotations" do
    field :biotope_id, :binary_id
    field :player_id, :binary_id
    field :tick, :integer
    field :body, :string
    # Phase 24 / 6.3 — when true, the annotation also surfaces on
    # the Trends time-series as a vertical marker (tooltip = body).
    field :bookmark, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  # Soft cap matching the changeset validation; the column is `:text`
  # so the DB does not enforce it.
  @body_min_length 1
  @body_max_length 2000

  @doc "Maximum allowed body length (also exposed for UI hints)."
  def body_max_length, do: @body_max_length

  @required [:biotope_id, :player_id, :tick, :body]
  @optional [:bookmark]

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(annotation, attrs) do
    annotation
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_number(:tick, greater_than_or_equal_to: 0)
    |> update_change(:body, &normalise_body/1)
    |> validate_length(:body, min: @body_min_length, max: @body_max_length)
    |> check_constraint(:tick, name: :tick_non_negative)
  end

  # Strip trailing whitespace and collapse interior runs of \r\n to \n
  # so paste-from-Windows-notepad doesn't break the rendering layer.
  defp normalise_body(nil), do: nil

  defp normalise_body(body) when is_binary(body) do
    body
    |> String.replace("\r\n", "\n")
    |> String.trim_trailing()
  end
end
