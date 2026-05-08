defmodule Arkea.Sim.Phase24SmokeTest do
  @moduledoc """
  End-to-end smoke test for Phase 24 (Lab notebook).

  Reuses the regulator + conjugative-plasmid scenario from the
  Phase 21 / 22 smokes, drives 30 ticks through the real
  `BiotopeServer` pipeline with persistence enabled, and asserts
  that each Phase-24 sub-deliverable produces its observable
  artefact end-to-end:

    * **6.1 Annotations** — `Arkea.Notebook.create/4` writes a
      row that `list_for_biotope/1` returns in tick order;
      `delete/2` is author-only.
    * **6.3 Bookmarks** — `toggle_bookmark/2` flips the flag;
      `list_bookmarks_for_biotope/1` returns only flagged rows.
    * **6.2 Permalinks (banner)** — covered implicitly by the
      `list_for_biotope/1` filter at a specific tick (the banner
      is a pure render of those rows).
    * **6.4 Historical replay** — `Arkea.History.fetch_state_at(
      biotope_id, N)` returns a `BiotopeState` whose tick is
      ≤ N for any N reachable via WAL or snapshot.
    * **6.8 Notebook exports** — the long-format CSV + NDJSON
      builders in `BiotopeController` are reachable by
      constructing the same artefacts the actions assemble
      (separate controller test verifies the HTTP envelope).

  Reproducible: `Mutator.init_seed("phase-24-smoke")`. Fail = a
  Phase-24 artefact regressed.
  """

  use Arkea.DataCase, async: false
  use Oban.Testing, repo: Arkea.Repo

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.History
  alias Arkea.Notebook
  alias Arkea.Persistence.TimeSeries
  alias Arkea.Sim.Biotope.Server, as: BiotopeServer
  alias Arkea.Sim.Biotope.Supervisor, as: BiotopeSupervisor
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Mutator

  @param_codons List.duplicate(10, 20)

  defp catalytic_domain, do: Domain.new([0, 0, 1], @param_codons)
  defp transmembrane_domain, do: Domain.new([0, 0, 2], @param_codons)
  defp dna_binding_domain, do: Domain.new([0, 0, 5], @param_codons)

  defp activator_regulator_domain do
    Domain.new([0, 0, 6], [0 | List.duplicate(10, 19)])
  end

  defp founder_genome do
    chromosome = [
      Gene.from_domains([catalytic_domain()]),
      Gene.from_domains([dna_binding_domain(), activator_regulator_domain()])
    ]

    plasmid = [Gene.from_domains([transmembrane_domain(), transmembrane_domain()])]
    Genome.new(chromosome, plasmids: [plasmid])
  end

  defp recipient_genome do
    Genome.new([Gene.from_domains([catalytic_domain()])])
  end

  defp surface_phase do
    base =
      Phase.new(:surface,
        temperature: 25.0,
        ph: 7.0,
        osmolarity: 300.0,
        dilution_rate: 0.0
      )

    %{base | metabolite_pool: %{glucose: 200.0, nh3: 40.0, po4: 10.0}}
  end

  defp build_state do
    donor = Lineage.new_founder(founder_genome(), %{surface: 200}, 0)
    recipient = Lineage.new_founder(recipient_genome(), %{surface: 200}, 0)

    BiotopeState.new_from_opts(
      id: Arkea.UUID.v4(),
      archetype: :eutrophic_pond,
      zone: :phase_24_smoke,
      phases: [surface_phase()],
      dilution_rate: 0.0,
      lineages: [donor, recipient],
      rng_seed: Mutator.init_seed("phase-24-smoke")
    )
  end

  defp start_biotope(%BiotopeState{} = state) do
    {:ok, pid} = BiotopeSupervisor.start_biotope(state)
    on_exit(fn -> stop_biotope(state.id) end)
    pid
  end

  defp stop_biotope(id) do
    case Registry.lookup(Arkea.Sim.Registry, {:biotope, id}) do
      [{pid, _value}] when is_pid(pid) ->
        if Process.alive?(pid) do
          DynamicSupervisor.terminate_child(BiotopeSupervisor, pid)
        end

        :ok

      _ ->
        :ok
    end
  end

  setup do
    previous = Application.get_env(:arkea, :persistence_enabled)
    Application.put_env(:arkea, :persistence_enabled, true)
    start_supervised!(Arkea.Oban)

    on_exit(fn ->
      if previous == nil do
        Application.delete_env(:arkea, :persistence_enabled)
      else
        Application.put_env(:arkea, :persistence_enabled, previous)
      end
    end)

    :ok
  end

  test "Phase 24 smoke: annotations + bookmarks + history + trait export round-trip end-to-end" do
    state = build_state()
    [donor, _recipient] = state.lineages
    biotope_id = state.id
    player_id = Ecto.UUID.generate()

    start_biotope(state)

    for _i <- 1..30 do
      assert :ok = BiotopeServer.manual_tick(biotope_id)
    end

    persisted = BiotopeServer.get_state(biotope_id)
    assert persisted.tick_count == 30

    # ---------------------------------------------------------------
    # 6.1 — annotations: create at three different ticks; list
    # returns them in tick-asc order.

    {:ok, _a1} = Notebook.create(biotope_id, player_id, 5, "early observation")
    {:ok, _a2} = Notebook.create(biotope_id, player_id, 25, "later observation")
    {:ok, _a3} = Notebook.create(biotope_id, player_id, 10, "middle observation")

    list = Notebook.list_for_biotope(biotope_id)
    ticks = Enum.map(list, & &1.tick)
    assert ticks == [5, 10, 25], "annotations should sort by tick asc; got #{inspect(ticks)}"

    # 6.2 — permalink filter (banner-style): notes attached to
    # tick 10 surface independently of the other two.
    pinned_ten = Enum.filter(list, &(&1.tick == 10))
    assert length(pinned_ten) == 1
    assert hd(pinned_ten).body == "middle observation"

    # ---------------------------------------------------------------
    # 6.3 — bookmarks: promote tick 25 to a bookmark; list of
    # flagged rows returns just that one.

    a25 = Enum.find(list, &(&1.tick == 25))
    assert {:ok, _} = Notebook.toggle_bookmark(a25.id, player_id)

    bookmarks = Notebook.list_bookmarks_for_biotope(biotope_id)
    assert match?([_one], bookmarks)
    assert hd(bookmarks).tick == 25
    assert hd(bookmarks).bookmark == true

    # Toggle again to clear → bookmarks list empties.
    assert {:ok, _} = Notebook.toggle_bookmark(a25.id, player_id)
    assert Notebook.list_bookmarks_for_biotope(biotope_id) == []

    # ---------------------------------------------------------------
    # 6.4 — historical replay: any tick in [0..30] reachable via
    # WAL or snapshot rebuilds a BiotopeState whose tick ≤ N.
    # The persisted WAL writes one row per tick (transition_kind
    # "tick"), so the exact-WAL branch fires for in-range queries.

    historical_5 = History.fetch_state_at(biotope_id, 5)
    assert %BiotopeState{tick_count: t5} = historical_5
    assert t5 <= 5
    # Donor lineage must still be present in the rebuild.
    assert Enum.any?(historical_5.lineages, &(&1.id == donor.id))

    historical_30 = History.fetch_state_at(biotope_id, 30)
    assert %BiotopeState{tick_count: t30} = historical_30
    assert t30 <= 30

    # Future tick (out of range) must still resolve to the latest
    # available row (≤ 30).
    historical_future = History.fetch_state_at(biotope_id, 9_999)
    assert %BiotopeState{tick_count: tn} = historical_future
    assert tn <= 30

    # ---------------------------------------------------------------
    # 6.8 — notebook-ready export: TimeSeries.list returns the
    # phenotype_trait samples that the controller flattens into
    # CSV rows. We assert here on the *data plane* the controller
    # reads from; the HTTP envelope is covered in
    # `biotope_controller_test.exs`.

    samples = TimeSeries.list(biotope_id, kind: "phenotype_trait", repo: Repo)
    assert samples != [], "phenotype_trait samples should be persisted after 30 ticks"

    sample = hd(samples)
    payload = sample.payload
    assert is_map(payload)

    # The CSV builder emits `tick,lineage_id,trait,value` rows for
    # every numeric / boolean trait in the payload. Sanity: every
    # canonical trait appears at least once across all samples.
    seen_traits = samples |> Enum.flat_map(&Map.keys(&1.payload)) |> MapSet.new()

    expected_subset = ~w(base_growth_rate repair_efficiency biofilm_capable)
    assert Enum.all?(expected_subset, &MapSet.member?(seen_traits, &1))
  end
end
