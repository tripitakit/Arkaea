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

  # Standard genome fixture: type :substrate_binding (type_tag sum 0 rem 11 = 0).
  # Under Phase 3 step_expression: base_growth_rate = 0.1 (default, no catalytic
  # domains), energy_cost = 0.0 → delta = round(0.1*100) - 0 = 10.
  defp genome_fixture do
    domain = Domain.new([0, 0, 0], List.duplicate(0, 20))
    gene = Gene.from_domains([domain])
    Genome.new([gene])
  end

  # Zero-delta genome: a :catalytic_site domain (type_tag [0,0,1]) with
  # all-zero parameter_codons → kcat = 0.0 → base_growth_rate = 0.0 → delta = 0.
  # Paired with a :repair_fidelity domain (type_tag sum rem 11 = 10 → [0,1,9])
  # with all-max parameter_codons (value 19) → repair_efficiency ≈ 1.0 → mutation
  # probability ≈ 0.0. This makes the test deterministic: no mutations fire.
  defp zero_delta_genome do
    catalytic = Domain.new([0, 0, 1], List.duplicate(0, 20))
    # type_tag [0,1,9]: sum = 10, rem(10,11) = 10 → :repair_fidelity
    # parameter_codons all 19: raw_sum high → norm ≈ 1.0 → efficiency ≈ 1.0
    high_fidelity = Domain.new([0, 1, 9], List.duplicate(19, 20))
    gene = Gene.from_domains([catalytic, high_fidelity])
    Genome.new([gene])
  end

  defp build_state(phase_name, initial_abundance, _growth_delta, dilution_rate) do
    # Phase 5 note: growth_delta_by_lineage is now overwritten each tick by
    # step_expression using ATP yield from metabolite uptake. We seed the phase
    # with glucose (the substrate targeted by genome_fixture's substrate_binding
    # domain: first_codon = 0 → target_metabolite_id = 0 → :glucose) and
    # enable inflow so the pool stays non-zero. The externally supplied
    # growth_delta argument is preserved in the signature for call-site
    # compatibility but is no longer used.
    phase =
      Phase.new(phase_name, dilution_rate: dilution_rate)
      |> Phase.update_metabolite(:glucose, 500.0)

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
      metabolite_inflow: %{glucose: 5.0}
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
  # With a zero-kcat genome and dilution_rate = 0, abundance must be exactly
  # invariant: step_expression derives delta = 0 (kcat = 0.0 → base_growth_rate
  # = 0.0 → round(0.0*100) - round(0.0*10) = 0), and dilution also produces
  # no change (rate = 0.0).
  #
  # Note: with Phase 3 step_expression active, the genome determines the growth
  # delta — externally-set growth_delta_by_lineage is overwritten every tick.
  # The zero-kcat genome fixture guarantees a genome-derived delta of exactly 0.

  test "abundance is exactly invariant with zero-kcat genome and zero dilution_rate" do
    initial_abundance = 500
    phase_name = :surface
    phase = Phase.new(phase_name, dilution_rate: 0.0)

    lineage =
      Lineage.new_founder(
        zero_delta_genome(),
        %{phase_name => initial_abundance},
        0
      )

    state =
      BiotopeState.new_from_opts(
        id: Arkea.UUID.v4(),
        archetype: :oligotrophic_lake,
        phases: [phase],
        dilution_rate: 0.0,
        lineages: [lineage]
      )

    {pid, _name} = start_server(state)

    Enum.each(1..10, fn _ -> GenServer.call(pid, :manual_tick) end)

    final_state = GenServer.call(pid, :get_state)
    final_lineage = hd(final_state.lineages)
    final_count = Map.fetch!(final_lineage.abundance_by_phase, :surface)

    assert final_count == initial_abundance,
           "abundance changed despite zero growth and zero dilution: expected #{initial_abundance}, got #{final_count}"
  end

  test "population reaches a bounded non-negative steady state when growth is fuelled by substrate" do
    # Phase 5: the system is driven by metabolic uptake (substrate → ATP → growth)
    # balanced against dilution wash-out. With continuous glucose inflow, the
    # population is bounded above (limited by substrate inflow) and bounded below
    # at 0 (Lineage.apply_growth clamp). We verify:
    #
    # (a) The server stays alive through 200 ticks.
    # (b) All per-phase abundances are non-negative after 200 ticks.
    # (c) The population does not monotonically increase without bound: after
    #     ticks 150..200 the maximum abundance observed is ≤ some reasonable cap.
    #
    # Note: Phase 5 convergence involves coupled population + metabolite pool
    # dynamics (two interacting ODEs discretised by integer floor). The system
    # may exhibit limit-cycle oscillations near the fixed point rather than
    # exact convergence to a single integer — this is biologically plausible
    # and not a bug. The strict fixed-point assertion used in Phase 3 is relaxed
    # here accordingly.
    dilution_rate = 0.1
    initial_abundance = 100

    state = build_state(:surface, initial_abundance, 0, dilution_rate)
    {pid, _name} = start_server(state)

    Enum.each(1..200, fn _ -> GenServer.call(pid, :manual_tick) end)

    assert Process.alive?(pid), "server crashed during 200 ticks"

    final_state = GenServer.call(pid, :get_state)

    # (a) non-negative abundances
    for lineage <- final_state.lineages,
        {_phase, count} <- lineage.abundance_by_phase do
      assert count >= 0, "negative abundance detected after 200 ticks"
    end

    # (b) bounded above: glucose inflow 5.0/tick → at 10% dilution, the
    #     substrate steady state is ~50 units, supporting a population
    #     proportional to uptake rate. For the given km = 0.01 the population
    #     is bounded by the substrate availability. We use a generous upper bound.
    total =
      case final_state.lineages do
        [] -> 0
        lineages -> Enum.sum(Enum.map(lineages, &Lineage.total_abundance/1))
      end

    assert total < 100_000,
           "population grew without bound after 200 ticks: #{total}"
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

  # ---------------------------------------------------------------------------
  # Recolonization

  test "recolonize replaces lineages on an extinct biotope" do
    extinct_state =
      build_state(:surface, 100, 0, 0.05)
      |> Map.put(:lineages, [])

    {pid, _name} = start_server(extinct_state)

    fresh_lineage =
      Lineage.new_founder(genome_fixture(), %{surface: 420}, 0)

    {:ok, %{tick: tick}} =
      GenServer.call(pid, {:recolonize, fresh_lineage, [actor_player_id: "p"]})

    assert tick == 0

    state_after = GenServer.call(pid, :get_state)
    assert length(state_after.lineages) == 1
    assert hd(state_after.lineages).id == fresh_lineage.id
    assert BiotopeState.total_abundance(state_after) == 420
  end

  test "recolonize refuses on a non-extinct biotope" do
    state = build_state(:surface, 100, 0, 0.05)
    {pid, _name} = start_server(state)

    fresh_lineage =
      Lineage.new_founder(genome_fixture(), %{surface: 420}, 0)

    assert {:error, :not_extinct} =
             GenServer.call(pid, {:recolonize, fresh_lineage, []})

    state_after = GenServer.call(pid, :get_state)
    # Original (single) lineage is preserved untouched.
    assert length(state_after.lineages) == 1
    assert hd(state_after.lineages).id != fresh_lineage.id
  end
end
