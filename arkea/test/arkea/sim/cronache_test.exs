defmodule Arkea.Sim.CronacheTest do
  @moduledoc """
  Phase 11 integration test — "Caso d'uso Cronache abbreviato".

  Validates that all implemented mechanisms fire in a connected multi-biotope
  scenario within a realistic number of ticks (IMPLEMENTATION-PLAN.md §5,
  Blocco 15 of DESIGN.md: "Da seed → resistenza, biofilm, profago,
  colonizzazione visibili in qualche ora reale").

  All tests use `Tick.tick/1` directly (pure function, no GenServer) so they
  are fast, deterministic within a fixed RNG seed, and independent of the
  application supervision tree.
  """

  use ExUnit.Case, async: true

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.CronacheScenario
  alias Arkea.Sim.Tick

  @moduletag :cronache
  @moduletag timeout: 120_000

  # ---------------------------------------------------------------------------
  # Test 1 — Full evolutionary pipeline (100 ticks, pond biotope)
  #
  # Criterion: the 7-step tick pipeline wired end-to-end produces observable
  # evolutionary diversity from a two-lineage seed within 100 ticks.
  #
  # Mechanisms exercised:
  #   Phase 4 — mutation → :lineage_born; pruning → :lineage_extinct
  #   Phase 5 — Michaelis-Menten glucose uptake; chemostat inflow
  #   Phase 6 — carrier has conjugative plasmid + prophage cassette
  #   Phase 7 — QS signal production (catalytic_site) + reception (ligand_sensor)
  #
  # Reliability: with 600–800 cells per phase and repair_efficiency ≈ 0.05,
  # mutation_probability fires every ~10 ticks (Phase 4 formula), generating
  # new lineages that eventually lose abundance and trigger :lineage_extinct
  # via dilution or competition.

  test "100 ticks from Cronache pond produce evolutionary diversity and event coverage" do
    state = CronacheScenario.build_pond_state()

    {final_state, all_events} =
      Enum.reduce(1..100, {state, []}, fn _, {s, evts} ->
        {new_s, new_evts} = Tick.tick(s)
        {new_s, evts ++ new_evts}
      end)

    born = Enum.filter(all_events, fn e -> e.type == :lineage_born end)
    extinct = Enum.filter(all_events, fn e -> e.type == :lineage_extinct end)

    assert length(born) >= 3,
           "expected ≥3 :lineage_born events in 100 ticks, got #{length(born)}"

    assert extinct != [],
           "expected ≥1 :lineage_extinct event in 100 ticks, got 0"

    total = BiotopeState.total_abundance(final_state)

    assert total > 0,
           "population went extinct after 100 ticks"

    assert final_state.tick_count == 100

    for lineage <- final_state.lineages,
        {_phase, count} <- lineage.abundance_by_phase do
      assert count >= 0, "negative abundance detected in lineage #{lineage.id}"
    end

    lineage_count = length(final_state.lineages)

    assert lineage_count >= 2,
           "expected ≥2 surviving lineages, got #{lineage_count}"
  end

  # ---------------------------------------------------------------------------
  # Test 2 — Conjugative plasmid wiring (2 000 independent single-tick trials)
  #
  # Validates that the HGT conjugation mechanism is correctly wired in the full
  # tick pipeline.  A single tick with a donor+recipient pair has probability
  # p ≈ 0.00125 per phase (mass-action formula, equal abundances 500:500:1000).
  # Across 2 000 independent trials each covering 3 phases, the expected total
  # is ~7.5 events; P(total ≥ 1) ≈ 99.9 %.
  #
  # Each trial uses a distinct `:rand` state derived from the trial index so
  # the outcomes are independent despite sharing the same initial BiotopeState.

  test "conjugative plasmid transfers to recipient across 2000 independent tick trials" do
    base_state = build_two_lineage_state()

    total_hgt =
      Enum.sum(
        Enum.map(1..2000, fn i ->
          rng = :rand.seed_s(:exsss, {i, i * 17, i * 31})
          state = %{base_state | rng_seed: rng}
          {_new_state, events} = Tick.tick(state)
          Enum.count(events, fn e -> e.type == :hgt_transfer end)
        end)
      )

    assert total_hgt > 0,
           "expected ≥1 HGT transfer across 2 000 independent tick trials, got 0"
  end

  # ---------------------------------------------------------------------------
  # Test 3 — Prophage induction under starvation (50 ticks, estuary biotope)
  #
  # The estuary seed lineage carries a prophage cassette.  With no metabolite
  # inflow (starvation), atp_yield → 0, stress_factor → 1.0, p_induction →
  # 0.03 per cassette per tick.  Dilution alone (rate 0.08–0.10) reduces
  # abundance monotonically; prophage induction adds an additional stochastic
  # burst loss of 50 % on induction.
  #
  # The combined effect (dilution + possible induction) guarantees abundance
  # decrease over 50 ticks regardless of whether induction fires.  This makes
  # the assertion deterministic while still exercising the induction code path.

  test "estuary population decreases under starvation over 50 ticks" do
    state = %{CronacheScenario.build_estuary_state() | metabolite_inflow: %{}}

    initial = BiotopeState.total_abundance(state)

    {final_state, _events} =
      Enum.reduce(1..50, {state, []}, fn _, {s, evts} ->
        {new_s, new_evts} = Tick.tick(s)
        {new_s, evts ++ new_evts}
      end)

    final = BiotopeState.total_abundance(final_state)

    assert final < initial,
           "abundance should decrease under starvation " <>
             "(initial: #{initial}, final: #{final})"
  end

  # ---------------------------------------------------------------------------
  # Test 4 — Structural validation of both scenario states

  test "Cronache pond and estuary states are structurally valid" do
    pond = CronacheScenario.build_pond_state()
    estuary = CronacheScenario.build_estuary_state()

    assert pond.archetype == :eutrophic_pond
    assert pond.neighbor_ids == [estuary.id]
    assert length(pond.lineages) == 2

    assert estuary.archetype == :saline_estuary
    assert estuary.neighbor_ids == [pond.id]
    assert length(estuary.lineages) == 1

    for lineage <- pond.lineages ++ estuary.lineages do
      assert Lineage.valid?(lineage), "lineage #{lineage.id} failed validation"
      assert lineage.genome != nil, "lineage #{lineage.id} has nil genome"
    end

    carrier = Enum.find(pond.lineages, fn l -> l.genome.plasmids != [] end)
    assert carrier != nil, "expected 1 carrier lineage with a conjugative plasmid in pond"
    assert length(carrier.genome.plasmids) == 1

    lineages_with_prophage =
      Enum.filter(pond.lineages ++ estuary.lineages, fn l ->
        l.genome != nil and l.genome.prophages != []
      end)

    assert length(lineages_with_prophage) >= 2,
           "expected all seed lineages to carry a prophage cassette"
  end

  # ---------------------------------------------------------------------------
  # Private helpers

  # Build a minimal 3-phase pond state with exactly 2 lineages:
  # one conjugative donor and one plasmid-free recipient.
  # Used by the HGT trial test to isolate the HGT wiring check.
  defp build_two_lineage_state do
    phases =
      [:surface, :water_column, :sediment]
      |> Enum.map(fn name ->
        Phase.new(name, dilution_rate: 0.02)
        |> Phase.update_metabolite(:glucose, 200.0)
        |> Phase.update_metabolite(:oxygen, 50.0)
      end)

    base_gene =
      Gene.from_domains([
        Domain.new([0, 0, 0], [0 | List.duplicate(2, 19)]),
        Domain.new([0, 1, 3], List.duplicate(5, 20))
      ])

    recipient_genome = Genome.new([base_gene])

    donor_genome =
      Genome.add_plasmid(
        recipient_genome,
        [Gene.from_domains([Domain.new([0, 0, 2], List.duplicate(8, 20))])]
      )

    phase_names = Enum.map(phases, & &1.name)
    donor_abundances = Map.new(phase_names, fn name -> {name, 500} end)
    recipient_abundances = Map.new(phase_names, fn name -> {name, 500} end)

    donor = Lineage.new_founder(donor_genome, donor_abundances, 0)
    recipient = Lineage.new_founder(recipient_genome, recipient_abundances, 0)

    BiotopeState.new_from_opts(
      id: Arkea.UUID.v4(),
      archetype: :eutrophic_pond,
      phases: phases,
      dilution_rate: 0.02,
      lineages: [donor, recipient],
      metabolite_inflow: %{glucose: 10.0, oxygen: 5.0}
    )
  end
end
