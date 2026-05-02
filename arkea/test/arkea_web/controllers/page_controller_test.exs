defmodule ArkeaWeb.PageControllerTest do
  use ArkeaWeb.ConnCase

  alias Arkea.Accounts

  test "GET / renders player access page", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "Create player"
    assert html =~ "Resume player"
    assert html =~ "Create a player, design a seed, colonize a controlled biotope."
  end

  test "GET / redirects authenticated players to /world", %{conn: conn} do
    conn = conn |> log_in_prototype_player() |> get(~p"/")
    assert redirected_to(conn) == "/world"
  end

  test "POST /players/register creates a player, starts a session, and enters the world", %{
    conn: conn
  } do
    conn =
      post(conn, ~p"/players/register", %{
        "player" => %{"display_name" => "Ada", "email" => "Ada@Example.com"}
      })

    assert redirected_to(conn) == "/world"

    player_id = get_session(conn, :player_id)
    assert %{display_name: "Ada", email: "ada@example.com"} = Accounts.get_player(player_id)
  end

  test "POST /players/log-in resumes an existing player by email", %{conn: conn} do
    {:ok, player} =
      Accounts.register_player(%{"display_name" => "Lina", "email" => "lina@example.com"})

    conn =
      post(conn, ~p"/players/log-in", %{
        "session" => %{"email" => "LINA@example.com"}
      })

    assert redirected_to(conn) == "/world"
    assert get_session(conn, :player_id) == player.id
  end

  test "POST /players/log-in rejects unknown email", %{conn: conn} do
    conn =
      post(conn, ~p"/players/log-in", %{
        "session" => %{"email" => "unknown@example.com"}
      })

    assert html_response(conn, 422) =~ "No player exists for that email yet."
  end

  test "GET /world redirects anonymous players back to /", %{conn: conn} do
    conn = get(conn, ~p"/world")
    assert redirected_to(conn) == "/"
  end

  test "GET /players/log-out clears the player session", %{conn: conn} do
    conn = conn |> log_in_prototype_player() |> get(~p"/players/log-out")
    assert redirected_to(conn) == "/"
    assert conn.private[:plug_session_info] == :drop
  end
end
