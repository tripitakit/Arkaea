defmodule Arkea.Persistence.Lineage do
  @moduledoc """
  Ecto schema per i lignaggi attivi (DESIGN.md Blocco 4).

  Riflesso DB della foresta in-memory di lignaggi. Non va confuso con
  `Arkea.Ecology.Lineage` (struct di dominio usata durante la simulazione).

  ## Serializzazione genome / delta_genome

  Entrambi i campi sono `:binary` (bytea Postgres). La serializzazione
  è `:erlang.term_to_binary(term, [:compressed])`. La deserializzazione
  è `:erlang.binary_to_term/1` con opzione `[:safe]` obbligatoria in
  Phase 10 quando si implementa il layer di recovery.

  In Phase 1 `genome` è sempre popolato; `delta_genome` può essere NULL.
  In Phase 4 (delta-encoding), `genome` può essere NULL per i discendenti
  non-founder e `delta_genome` è la lista di mutation events serializzata.

  ## abundance_by_phase

  Serializzato come `jsonb` (tipo `:map` in Ecto) con chiavi stringa
  (gli atom Elixir vengono convertiti a string da Jason durante l'encode).
  La conversione inversa stringa → atom è responsabilità del chiamante
  (Phase 10 recovery layer); in Phase 1 il campo è write-only dal punto di
  vista degli schema tests.

  ## Foreign keys

  - `biotope_id`: `on_delete: :delete_all`
  - `parent_id`: `on_delete: :nilify_all` — il parent estinto non rimuove
    i discendenti; il campo diventa NULL.
  - `clade_ref_id`: semplice indice, non FK — può puntare a un lineage
    già estinto (il genome di riferimento del clade).
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          biotope_id: Ecto.UUID.t() | nil,
          parent_id: Ecto.UUID.t() | nil,
          clade_ref_id: Ecto.UUID.t() | nil,
          genome: binary() | nil,
          delta_genome: binary() | nil,
          abundance_by_phase: map() | nil,
          fitness_cache: float() | nil,
          created_at_tick: non_neg_integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "lineages" do
    field :clade_ref_id, :binary_id
    field :genome, :binary
    field :delta_genome, :binary
    field :abundance_by_phase, :map
    field :fitness_cache, :float
    field :created_at_tick, :integer

    belongs_to :biotope, Arkea.Persistence.Biotope, type: :binary_id

    belongs_to :parent, Arkea.Persistence.Lineage,
      foreign_key: :parent_id,
      references: :id,
      type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:biotope_id, :clade_ref_id, :abundance_by_phase, :created_at_tick]
  @optional_fields [:parent_id, :genome, :delta_genome, :fitness_cache]

  @doc """
  Changeset base.

  Valida che `created_at_tick` sia non-negativo e che `fitness_cache`,
  se presente, sia >= 0.0. Non valida la struttura del genome binario
  (quello spetta al layer applicativo che deserializza con :erlang.binary_to_term/1).
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(lineage, attrs) do
    lineage
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:created_at_tick, greater_than_or_equal_to: 0)
    |> validate_number(:fitness_cache, greater_than_or_equal_to: 0.0)
    |> validate_abundance_by_phase()
    |> foreign_key_constraint(:biotope_id)
    |> foreign_key_constraint(:parent_id)
  end

  # Verifica che abundance_by_phase sia una mappa con valori interi non-negativi.
  # Le chiavi arrivano come stringhe (Jason decode) o come atom (cast interno).
  defp validate_abundance_by_phase(changeset) do
    case get_change(changeset, :abundance_by_phase) do
      nil ->
        changeset

      abundances when is_map(abundances) ->
        valid? =
          Enum.all?(abundances, fn {_k, v} ->
            is_integer(v) and v >= 0
          end)

        if valid? do
          changeset
        else
          add_error(
            changeset,
            :abundance_by_phase,
            "values must be non-negative integers"
          )
        end

      _ ->
        add_error(changeset, :abundance_by_phase, "must be a map")
    end
  end
end
