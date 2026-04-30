defmodule Arkea.Sim.Biotope.ServerTest do
  use ExUnit.Case, async: true

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Sim.Biotope.Server
  alias Arkea.Sim.BiotopeState

  @moduletag :sim

  # ---------------------------------------------------------------------------
  # Setup helpers

  # Start a standalone Biotope.Server with its own Registry and PubSub,
  # independent of the application-level WorldClock (so ticks are manual).
  setup do
    # Each test gets its own Registry so registrations do not leak.
    registry_name = :"test_registry_#{System.unique_integer([:positive])}"
    start_supervised!({Registry, keys: :unique, name: registry_name})

    # Patch the via-tuple builder to use the test registry — done by starting
    # the server with a patched initial state using start_link directly.
    # We bypass the application-level Biotope.Supervisor: the server is started
    # standalone (linked to the test process). If the test crashes, the server
    # crashes too (no resource leak).
    :ok
  end

  # ---------------------------------------------------------------------------
  # Helper: start a standalone server (no application supervisor)

  defp start_server(initial_state) do
    # Start the server in its own registry context. We override the name
    # to use a random registered name so tests can run concurrently without
    # conflicting with the application-level Arkea.Sim.Registry.
    server_name = :"biotope_server_#{System.unique_integer([:positive])}"

    {:ok, pid} =
      GenServer.start_link(
        Server,
        initial_state,
        name: server_name
      )

    {pid, server_name}
  end

  # ---------------------------------------------------------------------------
  # Fixtures

  defp genome_fixture do
    domain = Domain.new([0, 0, 0], List.duplicate(0, 20))
    gene = Gene.from_domains([domain])
    Genome.new([gene])
  end

  defp build_state(phase_name, initial_abundance, growth_delta, dilution_rate) do
    phase = Phase.new(phase_name, dilution_rate: dilution_rate)

    lineage =
      Lineage.new_founder(
        genome_fixture(),
        %{phase_name => initial_abundance},
        0
      )

    BiotopeState.new_from_opts(
      id: Arkea.UUID.v4(),
      archetype: :oligotrophic_lake,
      phases: [phase],
      dilution_rate: dilution_rate,
      lineages: [lineage],
      growth_delta_by_lineage: %{lineage.id => %{phase_name => growth_delta}}
    )
  end

  # ---------------------------------------------------------------------------
  # Test: get_state/1 via GenServer.call

  test "GenServer.call :get_state returns the current BiotopeState" do
    state = build_state(:surface, 100, 0, 0.05)
    {pid, _name} = start_server(state)

    returned = GenServer.call(pid, :get_state)
    assert returned.id == state.id
    assert returned.tick_count == 0
  end

  # ---------------------------------------------------------------------------
  # Test: manual_tick/1 advances state

  test "manual_tick advances tick_count by 1" do
    state = build_state(:surface, 100, 0, 0.05)
    {pid, _name} = start_server(state)

    assert GenServer.call(pid, :current_tick) == 0

    GenServer.call(pid, :manual_tick)
    assert GenServer.call(pid, :current_tick) == 1

    GenServer.call(pid, :manual_tick)
    assert GenServer.call(pid, :current_tick) == 2
  end

  # ---------------------------------------------------------------------------
  # Test: server survives many ticks without crash

  test "server survives 50 consecutive manual ticks without crash" do
    state = build_state(:surface, 1000, 5, 0.02)
    {pid, _name} = start_server(state)

    Enum.each(1..50, fn _ -> GenServer.call(pid, :manual_tick) end)

    assert Process.alive?(pid)
    final = GenServer.call(pid, :get_state)
    assert final.tick_count == 50
  end

  # ---------------------------------------------------------------------------
  # Integration: equilibrium test
  # With growth_delta = 0 and dilution_rate = 0, abundance must be exactly invariant.
  # (The continuous-model balance growth_delta/dilution_rate is a fixed point only in
  # floating-point arithmetic; integer floor makes the discrete fixed point lower.
  # The cleanest verifiable invariant for "zero net growth" in integers is d=r=0.)

  test "abundance is exactly invariant when growth_delta = 0 and dilution_rate = 0" do
    initial_abundance = 500
    state = build_state(:surface, initial_abundance, 0, 0.0)
    {pid, _name} = start_server(state)

    Enum.each(1..10, fn _ -> GenServer.call(pid, :manual_tick) end)

    final_state = GenServer.call(pid, :get_state)
    final_lineage = hd(final_state.lineages)
    final_count = Map.fetch!(final_lineage.abundance_by_phase, :surface)

    assert final_count == initial_abundance,
           "abundance changed despite zero growth and zero dilution: expected #{initial_abundance}, got #{final_count}"
  end

  test "population converges to a stable fixed point when growth balances dilution" do
    # With integer floor(), the system converges to a discrete fixed point below
    # the continuous equilibrium (growth_delta / dilution_rate).
    # We verify: after convergence, one more tick leaves the count unchanged.
    dilution_rate = 0.1
    growth_delta = 10
    initial_abundance = 100

    state = build_state(:surface, initial_abundance, growth_delta, dilution_rate)
    {pid, _name} = start_server(state)

    # Run 100 ticks to reach the fixed point
    Enum.each(1..100, fn _ -> GenServer.call(pid, :manual_tick) end)

    final_state = GenServer.call(pid, :get_state)
    final_lineage = hd(final_state.lineages)
    count_at_100 = Map.fetch!(final_lineage.abundance_by_phase, :surface)

    # One more tick
    GenServer.call(pid, :manual_tick)
    after_state = GenServer.call(pid, :get_state)
    after_lineage = hd(after_state.lineages)
    count_at_101 = Map.fetch!(after_lineage.abundance_by_phase, :surface)

    assert count_at_100 == count_at_101,
           "population has not converged at tick 100: #{count_at_100} → #{count_at_101}"
  end

  # ---------------------------------------------------------------------------
  # Integration: PubSub broadcast on tick

  test "manual_tick broadcasts {:biotope_tick, state, events} on biotope topic" do
    state = build_state(:surface, 100, 0, 0.05)
    {pid, _name} = start_server(state)

    Phoenix.PubSub.subscribe(Arkea.PubSub, "biotope:#{state.id}")

    GenServer.call(pid, :manual_tick)

    assert_receive {:biotope_tick, new_state, events}, 1000
    assert new_state.tick_count == 1
    assert is_list(events)
  end

  # ---------------------------------------------------------------------------
  # Integration: WorldClock-driven tick via PubSub

  test "server advances state when it receives a {:tick, n} PubSub message" do
    state = build_state(:surface, 100, 0, 0.05)
    {pid, _name} = start_server(state)

    # Simulate a WorldClock broadcast by sending directly to the server
    send(pid, {:tick, 1})

    # Give the server time to process the async message
    :timer.sleep(50)

    final = GenServer.call(pid, :get_state)
    assert final.tick_count == 1
  end

  # ---------------------------------------------------------------------------
  # Integration: unrecognised messages are ignored

  test "server ignores unknown messages without crashing" do
    state = build_state(:surface, 100, 0, 0.05)
    {pid, _name} = start_server(state)

    send(pid, :unknown_message)
    send(pid, {:some, :other, :tuple})

    :timer.sleep(20)
    assert Process.alive?(pid)
    assert GenServer.call(pid, :current_tick) == 0
  end
end
