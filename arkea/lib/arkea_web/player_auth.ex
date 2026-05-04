defmodule ArkeaWeb.PlayerAuth do
  @moduledoc """
  Session helpers for the prototype player-auth flow.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Arkea.Accounts

  @player_session_key :player_id

  @spec fetch_current_player(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def fetch_current_player(conn, _opts) do
    player =
      conn
      |> get_session(@player_session_key)
      |> case do
        id when is_binary(id) -> Accounts.get_player(id)
        _ -> nil
      end

    assign(conn, :current_player, player)
  end

  @spec redirect_if_authenticated_player(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def redirect_if_authenticated_player(
        %Plug.Conn{assigns: %{current_player: %{id: _id}}} = conn,
        _opts
      ) do
    conn
    |> redirect(to: "/dashboard")
    |> halt()
  end

  def redirect_if_authenticated_player(conn, _opts), do: conn

  @spec require_authenticated_player(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def require_authenticated_player(
        %Plug.Conn{assigns: %{current_player: %{id: _id}}} = conn,
        _opts
      ),
      do: conn

  def require_authenticated_player(conn, _opts) do
    conn
    |> put_flash(:error, "Create or resume a player before entering the world.")
    |> redirect(to: "/")
    |> halt()
  end

  @spec log_in_player(Plug.Conn.t(), %{id: binary()}) :: Plug.Conn.t()
  def log_in_player(conn, %{id: id}) when is_binary(id) do
    conn
    |> configure_session(renew: true)
    |> put_session(@player_session_key, id)
    |> assign(:current_player, Accounts.get_player(id) || %{id: id})
  end

  @spec log_out_player(Plug.Conn.t()) :: Plug.Conn.t()
  def log_out_player(conn) do
    conn
    |> configure_session(drop: true)
    |> assign(:current_player, nil)
  end

  @spec on_mount(:ensure_authenticated, map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:ensure_authenticated, _params, session, socket) do
    case current_player_from_session(session) do
      nil ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(
           :error,
           "Create or resume a player before entering the world."
         )
         |> Phoenix.LiveView.redirect(to: "/")}

      player ->
        {:cont, Phoenix.Component.assign(socket, :current_player, player)}
    end
  end

  defp current_player_from_session(%{"player_id" => id}) when is_binary(id),
    do: Accounts.get_player(id)

  defp current_player_from_session(%{player_id: id}) when is_binary(id),
    do: Accounts.get_player(id)

  defp current_player_from_session(_session), do: nil
end
