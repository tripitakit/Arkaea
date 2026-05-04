defmodule ArkeaWeb.Router do
  use ArkeaWeb, :router

  import ArkeaWeb.PlayerAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ArkeaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_player
  end

  pipeline :redirect_if_authenticated do
    plug :redirect_if_authenticated_player
  end

  pipeline :require_authenticated do
    plug :require_authenticated_player
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ArkeaWeb do
    pipe_through [:browser, :redirect_if_authenticated]

    get "/", PlayerAccessController, :new
    post "/players/register", PlayerAccessController, :create
    post "/players/log-in", PlayerAccessController, :log_in
  end

  scope "/", ArkeaWeb do
    pipe_through [:browser, :require_authenticated]

    get "/players/log-out", PlayerAccessController, :delete

    live_session :player_authenticated,
      on_mount: [{ArkeaWeb.PlayerAuth, :ensure_authenticated}] do
      live "/dashboard", DashboardLive
      live "/world", WorldLive
      live "/seed-lab", SeedLabLive
      live "/biotopes/:id", SimLive
      live "/audit", AuditLive
      live "/community", CommunityLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", ArkeaWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:arkea, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ArkeaWeb.Telemetry
    end
  end
end
