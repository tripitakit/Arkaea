defmodule Arkea.Persistence.AuditLog do
  @moduledoc """
  Ecto schema per il log di eventi tipizzati (DESIGN.md Blocco 13).

  Tabella append-only: nessun UPDATE né DELETE nel flusso normale.
  Usata per anti-griefing, origin tracking degli elementi mobili e
  qualsiasi evento significativo (HGT, mass lysis, interventi player).

  ## Design delle FK

  `actor_player_id`, `target_biotope_id`, `target_lineage_id` sono
  campi `:binary_id` senza foreign key referenziale — il log di audit
  deve sopravvivere alla rimozione dei referenti. I valori vengono
  conservati come "tombstone IDs" per il tracciamento storico.

  ## event_type previsti (Phase 1+)

  - `mutation_notable` — mutazione con effetto fenotipico rilevante
  - `hgt_event` — trasferimento genico orizzontale (Phase 6)
  - `mass_lysis` — evento di lisi massiva
  - `intervention` — azione player (Phase 9)
  - `colonization` — colonizzazione di un biotopo wild
  - `mobile_element_release` — rilascio di plasmide/profago nel sistema

  La lista è estensibile: il changeset non limita i valori di `event_type`
  con un'inclusione rigida per consentire l'aggiunta di nuovi tipi senza
  migration. Il controllo semantico è responsabilità del chiamante.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          event_type: String.t() | nil,
          actor_player_id: Ecto.UUID.t() | nil,
          target_biotope_id: Ecto.UUID.t() | nil,
          target_lineage_id: Ecto.UUID.t() | nil,
          payload: map() | nil,
          occurred_at_tick: non_neg_integer() | nil,
          occurred_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "audit_log" do
    field :event_type, :string
    field :actor_player_id, :binary_id
    field :target_biotope_id, :binary_id
    field :target_lineage_id, :binary_id
    field :payload, :map
    field :occurred_at_tick, :integer
    field :occurred_at, :utc_datetime_usec
  end

  @required_fields [:event_type, :occurred_at_tick, :occurred_at]
  @optional_fields [:actor_player_id, :target_biotope_id, :target_lineage_id, :payload]

  @doc """
  Changeset per inserimento (unica operazione supportata).

  `payload` defaulta a `%{}` se omesso.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:event_type, min: 1, max: 60)
    |> validate_number(:occurred_at_tick, greater_than_or_equal_to: 0)
    |> put_default_payload()
  end

  defp put_default_payload(changeset) do
    case get_field(changeset, :payload) do
      nil -> put_change(changeset, :payload, %{})
      _ -> changeset
    end
  end
end
