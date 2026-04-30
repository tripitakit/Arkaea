defmodule Arkea.Sim.WorldClock do
  @moduledoc """
  GenServer that drives the global simulation clock (DESIGN.md Block 11,
  IMPLEMENTATION-PLAN.md §4).

  Behaviour:
  - Beats a `:tick` every `@tick_interval_ms` milliseconds of wall-clock time.
  - Broadcasts `{:tick, tick_number}` on the PubSub topic `"world:tick"`.
  - `Biotope.Server` processes subscribe to `"world:tick"` and execute their
    pure tick function upon receiving the broadcast.

  ## Configuration

  The interval is configurable for test environments so that tests do not
  need to wait 5 minutes per tick:

      config :arkea, :tick_interval_ms, 300_000   # production default: 5 min

      config :arkea, :tick_interval_ms, 0          # test: tick immediately

  The default when no config entry is present is 300_000 (5 real minutes per
  tick as per DESIGN.md Block 11).

  ## State

  `%{tick_count: non_neg_integer()}` — the number of ticks emitted since the
  process started. Published in the broadcast message so subscribers can
  correlate their internal `BiotopeState.tick_count` with the global clock.

  ## Fault tolerance

  `restart: :permanent` — the WorldClock is a load-bearing process: losing it
  silently stops all biotope evolution. The supervisor will restart it on crash.
  On restart it resets `tick_count` to 0 (wall-clock sync is a Phase 10 concern).

  ## No DB writes

  WorldClock does not access the DB. Persistence is the responsibility of
  `Persistence.Snapshot` (Phase 10).
  """

  use GenServer

  require Logger

  @default_tick_interval_ms 300_000

  # ---------------------------------------------------------------------------
  # Public API

  @doc "Start the WorldClock under a supervisor."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Return the current tick count."
  @spec current_tick() :: non_neg_integer()
  def current_tick do
    GenServer.call(__MODULE__, :current_tick)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks

  @impl GenServer
  def init(_opts) do
    interval = tick_interval_ms()
    Process.send_after(self(), :tick, interval)
    Logger.info("WorldClock started, tick interval: #{interval}ms")
    {:ok, %{tick_count: 0}}
  end

  @impl GenServer
  def handle_call(:current_tick, _from, state) do
    {:reply, state.tick_count, state}
  end

  @impl GenServer
  def handle_info(:tick, %{tick_count: n} = state) do
    new_tick = n + 1
    Phoenix.PubSub.broadcast(Arkea.PubSub, "world:tick", {:tick, new_tick})
    Process.send_after(self(), :tick, tick_interval_ms())
    {:noreply, %{state | tick_count: new_tick}}
  end

  # ---------------------------------------------------------------------------
  # Private helpers

  defp tick_interval_ms do
    Application.get_env(:arkea, :tick_interval_ms, @default_tick_interval_ms)
  end
end
