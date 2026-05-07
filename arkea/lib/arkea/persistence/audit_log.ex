defmodule Arkea.Persistence.AuditLog do
  @moduledoc """
  Ecto schema per il log di eventi tipizzati (01-DESIGN.md Blocco 13).

  Tabella append-only: nessun UPDATE né DELETE nel flusso normale.
  Usata per anti-griefing, origin tracking degli elementi mobili e
  qualsiasi evento significativo (HGT, mass lysis, interventi player).

  ## Design delle FK

  `actor_player_id`, `target_biotope_id`, `target_lineage_id` sono
  campi `:binary_id` senza foreign key referenziale — il log di audit
  deve sopravvivere alla rimozione dei referenti. I valori vengono
  conservati come "tombstone IDs" per il tracciamento storico.

  ## event_type previsti (Phase 1+)

  Lifecycle / diff-derived:
  - `lineage_born` — nuova lineage comparsa nel tick
  - `lineage_extinct` — lineage scomparsa nel tick
  - `mutation_notable` — mutazione con effetto fenotipico rilevante
  - `mass_lysis` — evento di lisi massiva
  - `colonization` — colonizzazione di un biotopo wild
  - `phage_burst` — burst lisogenico/litico massivo

  HGT / mobile elements (channel-direct, post-remediation 1.4–1.6):
  - `hgt_transfer` — coniugazione plasmidica
  - `transformation_event` — uptake di DNA libero
  - `transduction_event` — trasferimento mediato da fago
  - `phage_infection` — infezione fagica con esito di lisi/lisogenia
  - `rm_digestion` — restrizione/modificazione neutralizza l'episome
  - `plasmid_displaced` — conflitto di gruppo Inc tra plasmidi
  - `mobile_element_release` — rilascio di plasmide/profago nel sistema

  Stress / death:
  - `bacteriocin_kill` — lisi indotta da bacteriocina di un produttore vicino
  - `error_catastrophe_death` — offspring non vitale per soglia μ × genome_size

  Player / governance:
  - `intervention` — azione player (Phase 9)
  - `community_provisioned` — biotopo community-mode inoculato

  Nota storica: prima della remediation P0 (Sub-task 1.4) gli eventi HGT
  erano persistiti come `hgt_event` (handler diff-derived). Il tipo è
  stato sostituito dalla famiglia channel-direct sopra; non viene più
  emesso in nuovi inserimenti ma può essere presente in righe storiche.

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
