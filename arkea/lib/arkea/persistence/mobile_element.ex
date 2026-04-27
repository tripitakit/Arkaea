defmodule Arkea.Persistence.MobileElement do
  @moduledoc """
  Ecto schema per il registro degli elementi mobili (DESIGN.md Blocco 13).

  Traccia plasmidi, profagi e fagi liberi con il loro lineage/biotopo di
  origine per il sistema di origin tracking anti-griefing.

  ## kind

  Tre valori ammessi: `plasmid`, `prophage`, `free_phage`. Validato sia
  dal changeset che da un CHECK constraint Postgres nella migration.

  ## genes

  Campo `:binary` (bytea). Serializzato con
  `:erlang.term_to_binary(term, [:compressed])`. In Phase 1 può essere
  NULL se il gene payload non è ancora definito (raro; il campo esiste
  per Phase 6 quando gli elementi mobili diventano attivi).

  ## origine

  `origin_lineage_id` e `origin_biotope_id` sono senza FK referenziale:
  il lineage/biotopo di origine può essere estinto o rimosso; i valori
  vengono conservati come tombstone IDs per il tracciamento storico.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @kinds ~w(plasmid prophage free_phage)

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          kind: String.t() | nil,
          genes: binary() | nil,
          origin_lineage_id: Ecto.UUID.t() | nil,
          origin_biotope_id: Ecto.UUID.t() | nil,
          created_at_tick: non_neg_integer() | nil,
          inserted_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "mobile_elements" do
    field :kind, :string
    field :genes, :binary
    field :origin_lineage_id, :binary_id
    field :origin_biotope_id, :binary_id
    field :created_at_tick, :integer

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:kind, :created_at_tick]
  @optional_fields [:genes, :origin_lineage_id, :origin_biotope_id]

  @doc """
  Changeset base. Valida `kind` contro i 3 valori ammessi.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(element, attrs) do
    element
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:kind, @kinds, message: "must be one of: #{Enum.join(@kinds, ", ")}")
    |> validate_number(:created_at_tick, greater_than_or_equal_to: 0)
  end

  @doc "Lista dei kind di elementi mobili supportati."
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds
end
