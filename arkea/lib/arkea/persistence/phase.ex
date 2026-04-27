defmodule Arkea.Persistence.Phase do
  @moduledoc """
  Ecto schema per i sotto-ambienti di un biotopo (DESIGN.md Blocco 12).

  **Non va confuso con `Arkea.Ecology.Phase`** (struct in-memory).

  Un record Phase memorizza i parametri fisico-chimici stabili di una fase
  (temperature, pH, osmolarity, dilution_rate). I pool dinamici
  (metabolite_pool, signal_pool, phage_pool) sono in-memory durante il tick
  e vengono serializzati solo nel full-state snapshot (Phase 10).

  ## Vincoli

  - `(biotope_id, name)` UNIQUE: un biotopo non può avere due fasi con lo
    stesso nome. Il vincolo è imposto sia via DB (unique_index nella migration)
    sia via `unique_constraint/2` nel changeset.
  - FK `biotope_id` con `on_delete: :delete_all`: le fasi non hanno
    significato senza il biotopo padre.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          biotope_id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          temperature: float() | nil,
          ph: float() | nil,
          osmolarity: float() | nil,
          dilution_rate: float() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "phases" do
    field :name, :string
    field :temperature, :float
    field :ph, :float
    field :osmolarity, :float
    field :dilution_rate, :float

    belongs_to :biotope, Arkea.Persistence.Biotope, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:biotope_id, :name, :temperature, :ph, :osmolarity, :dilution_rate]

  @doc """
  Changeset base. Valida range fisici coerenti con i valori in-domain
  (`Arkea.Ecology.Phase`): temperature [-50, 150], pH [0, 14],
  osmolarity [0, 5000], dilution_rate [0, 1].
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(phase, attrs) do
    phase
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 40)
    |> validate_number(:temperature,
      greater_than_or_equal_to: -50.0,
      less_than_or_equal_to: 150.0
    )
    |> validate_number(:ph, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 14.0)
    |> validate_number(:osmolarity,
      greater_than_or_equal_to: 0.0,
      less_than_or_equal_to: 5000.0
    )
    |> validate_number(:dilution_rate,
      greater_than_or_equal_to: 0.0,
      less_than_or_equal_to: 1.0
    )
    |> foreign_key_constraint(:biotope_id)
    |> unique_constraint([:biotope_id, :name],
      name: :phases_biotope_id_name_index,
      message: "a phase with this name already exists in the biotope"
    )
  end
end
