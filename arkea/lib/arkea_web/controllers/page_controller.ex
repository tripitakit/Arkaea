defmodule ArkeaWeb.PageController do
  use ArkeaWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
