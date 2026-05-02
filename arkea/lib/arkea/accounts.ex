defmodule Arkea.Accounts do
  @moduledoc """
  Minimal player-account context for the interactive game shell.

  Authentication remains prototype-level: registration persists a `Player`,
  while sign-in resumes an existing player by email and stores the player id
  in the browser session.
  """

  import Ecto.Query

  alias Arkea.Persistence.Player
  alias Arkea.Repo

  @spec change_player_registration(map()) :: Ecto.Changeset.t()
  def change_player_registration(attrs \\ %{}) when is_map(attrs) do
    Player.changeset(%Player{}, attrs)
  end

  @spec register_player(map()) :: {:ok, Player.t()} | {:error, Ecto.Changeset.t()}
  def register_player(attrs) when is_map(attrs) do
    %Player{}
    |> Player.changeset(attrs)
    |> Repo.insert()
  end

  @spec get_player(binary()) :: Player.t() | nil
  def get_player(id) when is_binary(id), do: Repo.get(Player, id)

  @spec get_player_by_email(binary()) :: Player.t() | nil
  def get_player_by_email(email) when is_binary(email) do
    normalized =
      email
      |> String.trim()
      |> String.downcase()

    Repo.one(from(player in Player, where: player.email == ^normalized))
  end
end
