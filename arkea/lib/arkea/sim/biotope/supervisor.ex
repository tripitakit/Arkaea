defmodule Arkea.Sim.Biotope.Supervisor do
  @moduledoc """
  `DynamicSupervisor` that owns all `Arkea.Sim.Biotope.Server` processes
  (IMPLEMENTATION-PLAN.md §4 process tree).

  Biotope server processes are started dynamically at runtime (not declared
  statically in the child spec list) because the set of active biotopes is
  determined by game state, not by application config.

  ## Supervision strategy

  `:one_for_one` — the default for DynamicSupervisor. Crashing a single
  `Biotope.Server` does not affect sibling biotopes; the supervisor restarts
  the crashed server independently. This matches the Active Record pattern:
  each biotope's in-memory state is self-contained.

  ## Starting biotope servers

  Call `start_biotope/1` with a `BiotopeState.t()`. The server registers
  itself in `Arkea.Sim.Registry` under `{:biotope, id}`, so callers can
  address it via `Biotope.Server.get_state/1` or `Biotope.Server.current_tick/1`
  without keeping a PID reference.

  ## Phase 8 note

  Migration.Coordinator (Phase 8) will call this supervisor to start biotope
  servers as the world graph is populated. In Phase 2 the caller is responsible
  for starting the servers it needs (e.g. in test setup or application init).
  """

  use DynamicSupervisor

  alias Arkea.Sim.Biotope.Server
  alias Arkea.Sim.BiotopeState

  @doc "Start the DynamicSupervisor."
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl DynamicSupervisor
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a `Biotope.Server` for the given `BiotopeState`.

  Returns `{:ok, pid}` on success, `{:error, reason}` otherwise.
  If a server for `state.id` is already running, returns
  `{:error, {:already_started, pid}}`.
  """
  @spec start_biotope(BiotopeState.t()) :: DynamicSupervisor.on_start_child()
  def start_biotope(%BiotopeState{} = state) do
    DynamicSupervisor.start_child(__MODULE__, {Server, state})
  end
end
