defmodule Arkea.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Arkea.Persistence.Recovery
  alias Arkea.Sim.Biotope.Supervisor, as: BiotopeSupervisor
  alias Arkea.Sim.Bootstrap
  alias Arkea.Sim.Migration.Coordinator, as: MigrationCoordinator
  alias Arkea.Sim.WorldClock

  @impl true
  def start(_type, _args) do
    children =
      [
        ArkeaWeb.Telemetry,
        Arkea.Repo,
        {DNSCluster, query: Application.get_env(:arkea, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Arkea.PubSub},
        {Registry, keys: :unique, name: Arkea.Sim.Registry},
        BiotopeSupervisor
      ] ++
        persistence_children() ++
        runtime_children() ++
        bootstrap_children() ++
        [ArkeaWeb.Endpoint]

    # :one_for_one — each child is independent. A crashing Biotope.Server or
    # WorldClock does not affect sibling processes (01-DESIGN.md §14 rationale).
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

  defp persistence_children do
    if Arkea.Persistence.enabled?() do
      [
        Arkea.Oban,
        Recovery
      ]
    else
      []
    end
  end

  defp runtime_children do
    [MigrationCoordinator, WorldClock]
  end

  # Phase 33 — startup-time bootstrap of the default world (3 wild
  # biotopes + 1 community-chain biotope). Runs as a one-shot
  # `Task` *after* the persistence Recovery child has already
  # restored persisted biotopes, so it skips any biotope id that
  # was already brought back from the WAL / snapshot tables.
  # Disabled in test env via `config :arkea, :startup_bootstrap, false`.
  defp bootstrap_children do
    if Application.get_env(:arkea, :startup_bootstrap, true) do
      [
        {Task, fn -> Bootstrap.bootstrap_default_world() end}
      ]
    else
      []
    end
  end
end
