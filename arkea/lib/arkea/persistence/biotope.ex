defmodule Arkea.Persistence.Biotope do
  @moduledoc """
  Ecto schema per i nodi del world graph (DESIGN.md Blocco 10).

  **Non va confuso con `Arkea.Ecology.Biotope`** che è la struct in-memory
  usata durante la simulazione. Questo modulo riguarda solo la persistenza.

  ## Archetipi supportati

  Gli 8 archetipi sono validati via changeset e vincolati da un CHECK
  constraint Postgres nella migration. La lista è @archetypes canonici
  di `Arkea.Ecology.Biotope`, ma questo schema non importa quel modulo
  per evitare accoppiamento dominio ↔ persistenza.

  ## Foreign keys

  - `owner_player_id`: nullable, `on_delete: :nilify_all` — il biotopo
    sopravvive come "wild" (owner NULL) se il player viene rimosso.
  """

  use Ecto.Schema

  import Ecto.Changeset

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

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          archetype: String.t() | nil,
          zone: String.t() | nil,
          x: float() | nil,
          y: float() | nil,
          owner_player_id: Ecto.UUID.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "biotopes" do
    field :archetype, :string
    field :zone, :string
    field :x, :float
    field :y, :float

    belongs_to :owner_player, Arkea.Persistence.Player,
      foreign_key: :owner_player_id,
      type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:archetype, :zone, :x, :y]
  @optional_fields [:owner_player_id]

  @doc """
  Changeset base. Valida archetype contro la lista canonica degli 8 valori.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(biotope, attrs) do
    biotope
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:archetype, @archetypes,
      message: "must be one of: #{Enum.join(@archetypes, ", ")}"
    )
    |> validate_length(:archetype, max: 40)
    |> validate_length(:zone, min: 1, max: 40)
    |> foreign_key_constraint(:owner_player_id)
  end

  @doc "Lista degli 8 archetipi supportati."
  @spec archetypes() :: [String.t()]
  def archetypes, do: @archetypes
end
