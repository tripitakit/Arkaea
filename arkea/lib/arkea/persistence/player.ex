defmodule Arkea.Persistence.Player do
  @moduledoc """
  Ecto schema per l'account giocatore (DESIGN.md Blocco 11).

  Questo modulo rappresenta la persistenza. Non va confuso con eventuali
  struct di dominio lato giocatore che arriveranno in fasi successive.

  Phase 1 minimale: email (normalizzata lowercase), display_name, cooldown
  di colonizzazione. Auth completa (password, sessioni, token) è Phase 9+.

  ## Decisioni di schema

  - `email` viene lowercased nel changeset: l'unicità è case-insensitive
    di fatto senza richiedere l'estensione citext (rinviata a Phase 9).
  - `colonization_cooldown_until` è nullable — NULL significa nessun cooldown
    attivo (il giocatore può colonizzare liberamente).
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          email: String.t() | nil,
          display_name: String.t() | nil,
          colonization_cooldown_until: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "players" do
    field :email, :string
    field :display_name, :string
    field :colonization_cooldown_until, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:email, :display_name]
  @optional_fields [:colonization_cooldown_until]

  @doc """
  Changeset base per inserimento e aggiornamento.

  Normalizza l'email a lowercase prima della validazione.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(player, attrs) do
    player
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> update_change(:email, &String.downcase/1)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/,
      message: "must be a valid email address"
    )
    |> validate_length(:email, max: 320)
    |> validate_length(:display_name, min: 1, max: 80)
    |> unique_constraint(:email)
  end
end
