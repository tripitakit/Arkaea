defmodule Arkea.Persistence.ArkeonBlueprint do
  @moduledoc """
  Persisted seed blueprint built in the prototype seed lab.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Arkea.Genome

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          player_id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          starter_archetype: String.t() | nil,
          phenotype_spec: map() | nil,
          genome_binary: binary() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "arkeon_blueprints" do
    field :name, :string
    field :starter_archetype, :string
    field :phenotype_spec, :map
    field :genome_binary, :binary

    belongs_to :player, Arkea.Persistence.Player

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:player_id, :name, :starter_archetype, :phenotype_spec, :genome_binary]

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(blueprint, attrs) do
    blueprint
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 80)
    |> validate_length(:starter_archetype, min: 1, max: 40)
    |> validate_change(:phenotype_spec, fn :phenotype_spec, value ->
      if is_map(value), do: [], else: [phenotype_spec: "must be a map"]
    end)
    |> validate_change(:genome_binary, fn :genome_binary, value ->
      if is_binary(value) and byte_size(value) > 0 do
        []
      else
        [genome_binary: "must be a non-empty binary"]
      end
    end)
    |> foreign_key_constraint(:player_id)
  end

  @spec dump_genome!(Genome.t()) :: binary()
  def dump_genome!(%Genome{} = genome) do
    :erlang.term_to_binary(genome, [:compressed])
  end

  @spec load_genome(binary()) :: {:ok, Genome.t()} | {:error, atom() | tuple()}
  def load_genome(binary) when is_binary(binary) do
    case :erlang.binary_to_term(binary, [:safe]) do
      %Genome{} = genome -> {:ok, genome}
      other -> {:error, {:unexpected_term, other}}
    end
  rescue
    ArgumentError -> {:error, :invalid_binary}
  end
end
