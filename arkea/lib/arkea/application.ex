defmodule Arkea.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ArkeaWeb.Telemetry,
      Arkea.Repo,
      {DNSCluster, query: Application.get_env(:arkea, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Arkea.PubSub},
      # Sim process tree — order matters here (Registry before consumers,
      # WorldClock before Biotope.Supervisor so PubSub topic exists first).
      {Registry, keys: :unique, name: Arkea.Sim.Registry},
      Arkea.Sim.WorldClock,
      Arkea.Sim.Biotope.Supervisor,
      # Start to serve requests, typically the last entry
      ArkeaWeb.Endpoint
    ]

    # :one_for_one — each child is independent. A crashing Biotope.Server or
    # WorldClock does not affect sibling processes (DESIGN.md §14 rationale).
    opts = [strategy: :one_for_one, name: Arkea.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ArkeaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
