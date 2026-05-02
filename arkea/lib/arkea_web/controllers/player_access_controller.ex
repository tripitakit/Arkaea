defmodule ArkeaWeb.PlayerAccessController do
  use ArkeaWeb, :controller

  alias Arkea.Accounts
  alias ArkeaWeb.PlayerAuth

  def new(conn, _params) do
    render_new(conn, Accounts.change_player_registration(), %{"email" => ""})
  end

  def create(conn, %{"player" => params}) do
    case Accounts.register_player(params) do
      {:ok, player} ->
        conn
        |> put_flash(
          :info,
          "Player created. Design the seed and choose the first biotope to colonize."
        )
        |> PlayerAuth.log_in_player(player)
        |> redirect(to: ~p"/seed-lab")

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render_new(changeset, %{"email" => Map.get(params, "email", "")})
    end
  end

  def log_in(conn, %{"session" => %{"email" => email}}) do
    case Accounts.get_player_by_email(email) do
      nil ->
        conn
        |> put_flash(:error, "No player exists for that email yet.")
        |> put_status(:unprocessable_entity)
        |> render_new(Accounts.change_player_registration(), %{"email" => email})

      player ->
        conn
        |> put_flash(:info, "Welcome back, #{player.display_name}.")
        |> PlayerAuth.log_in_player(player)
        |> redirect(to: ~p"/world")
    end
  end

  def delete(conn, _params) do
    conn
    |> PlayerAuth.log_out_player()
    |> put_flash(:info, "Session closed.")
    |> redirect(to: ~p"/")
  end

  defp render_new(conn, %Ecto.Changeset{} = register_changeset, login_attrs) do
    render(conn, :new,
      register_form: Phoenix.Component.to_form(register_changeset, as: :player),
      login_form: Phoenix.Component.to_form(login_attrs, as: :session)
    )
  end
end
