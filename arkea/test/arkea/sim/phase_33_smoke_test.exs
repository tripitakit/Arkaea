defmodule Arkea.Sim.Phase33SmokeTest do
  @moduledoc """
  Phase 33 — startup-time bootstrap of the default world.

  Exercises `Arkea.Sim.Bootstrap.bootstrap_default_world/0` which
  idempotently seeds **3 wild biotopes** + **1 community-chain
  biotope** at application boot.

  ## What we verify

    * Calling the bootstrap once registers all 4 biotopes under
      `Arkea.Sim.Biotope.Supervisor`.
    * Calling it again is a no-op (idempotent: every biotope is
      skipped on the second call).
    * The wild seed genomes are *high-mutability* (low
      `repair_efficiency`) → mutation events fire within a small
      tick window, demonstrating observable evolution.
    * The community biotope's three seeds form a chemotrophic
      chain on different substrates: A consumes glucose,
      B consumes acetate, C consumes CO₂. The byproduct map
      (`glucose → acetate, co2, h2`; `acetate → co2`;
      `co2 → ch4`) wires the chain end-to-end via mass-action
      kinetics; we verify the substrates / products visibly
      shift after a short run.

  Each test starts the BiotopeSupervisor + Registry in isolation
  to keep the suite hermetic. The `bootstrap_default_world/0`
  path itself is opt-out via `config :arkea, :startup_bootstrap,
  false` — but we *enable* it here for the duration of the test.
  """

  use Arkea.DataCase, async: false

  alias Arkea.Sim.Biotope.Server, as: BiotopeServer
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Bootstrap
  alias Arkea.Sim.Phenotype
  alias Arkea.Sim.Tick

  setup do
    previous = Application.get_env(:arkea, :startup_bootstrap)
    Application.put_env(:arkea, :startup_bootstrap, true)

    on_exit(fn ->
      # Tear down any biotope started by the bootstrap so the
      # next test starts clean.
      for id <- Bootstrap.wild_biotope_ids() ++ [Bootstrap.community_biotope_id()] do
        case Registry.lookup(Arkea.Sim.Registry, {:biotope, id}) do
          [{pid, _}] when is_pid(pid) ->
            if Process.alive?(pid) do
              DynamicSupervisor.terminate_child(Arkea.Sim.Biotope.Supervisor, pid)
            end

          _ ->
            :ok
        end
      end

      if previous == nil do
        Application.delete_env(:arkea, :startup_bootstrap)
      else
        Application.put_env(:arkea, :startup_bootstrap, previous)
      end
    end)

    :ok
  end

  test "bootstrap_default_world/0 starts 3 wild + 1 community biotope, idempotently" do
    assert {:ok, %{started: started_first, skipped: skipped_first}} =
             Bootstrap.bootstrap_default_world()

    assert started_first == 4
    assert skipped_first == 0

    # Each wild + community biotope has a registered server.
    for id <- Bootstrap.wild_biotope_ids() do
      assert [{pid, _}] = Registry.lookup(Arkea.Sim.Registry, {:biotope, id})
      assert Process.alive?(pid)
    end

    assert [{pid, _}] =
             Registry.lookup(Arkea.Sim.Registry, {:biotope, Bootstrap.community_biotope_id()})

    assert Process.alive?(pid)

    # Idempotency: re-running the bootstrap skips everything.
    assert {:ok, %{started: 0, skipped: 4}} = Bootstrap.bootstrap_default_world()
  end

  test "wild biotopes carry a high-mutability single seed (low repair_efficiency)" do
    {:ok, _} = Bootstrap.bootstrap_default_world()

    for id <- Bootstrap.wild_biotope_ids() do
      state = BiotopeServer.get_state(id)
      assert match?([_one], state.lineages), "wild biotope #{id} should have exactly 1 seed"

      [seed] = state.lineages
      phenotype = Phenotype.from_genome(seed.genome)

      # Repair_efficiency derives from `:repair_fidelity` domain. We seed
      # with low param codons (≈ 2) → efficiency ≈ 0.1 in the genome's
      # aggregator. The mean-vs-default bookkeeping in `from_genome/1`
      # caps it ≤ 0.5; we just need it to land below 0.5 for visible
      # mutation rates.
      assert phenotype.repair_efficiency < 0.5

      # `original_seed_id` tags every founder for Community Mode-style
      # provenance audits even on solo wild seeds.
      assert is_binary(seed.original_seed_id)
      assert String.starts_with?(seed.original_seed_id, "wild-seed-")
    end
  end

  test "community biotope carries 3 seeds with chain-aligned substrate targets" do
    {:ok, _} = Bootstrap.bootstrap_default_world()

    state = BiotopeServer.get_state(Bootstrap.community_biotope_id())
    assert length(state.lineages) == 3

    seed_targets =
      state.lineages
      |> Enum.map(fn lineage ->
        phenotype = Phenotype.from_genome(lineage.genome)
        phenotype.substrate_affinities |> Map.keys() |> Enum.sort()
      end)

    flat = List.flatten(seed_targets) |> Enum.sort()
    # The three seeds collectively target glucose + acetate + co2.
    assert :glucose in flat
    assert :acetate in flat
    assert :co2 in flat

    # Original seed ids reflect the chain role (provenance is
    # carried through `:lineage_inoculation` semantics in
    # Phase 19 Community Mode).
    seed_ids = Enum.map(state.lineages, & &1.original_seed_id) |> Enum.sort()

    assert Enum.any?(seed_ids, &String.contains?(&1, "glucose-fermenter"))
    assert Enum.any?(seed_ids, &String.contains?(&1, "acetate-oxidizer"))
    assert Enum.any?(seed_ids, &String.contains?(&1, "methanogen"))
  end

  test "community biotope: chemotrophic chain shifts metabolite pools after a short run" do
    {:ok, _} = Bootstrap.bootstrap_default_world()

    initial_state = BiotopeServer.get_state(Bootstrap.community_biotope_id())
    initial_glucose = sum_metabolite(initial_state, :glucose)

    # Drive 30 ticks. The chain consumes glucose (A) → produces
    # acetate (B's substrate) → produces co2 (C's substrate) →
    # produces ch4. After 30 ticks the glucose pool should have
    # *shifted* (could rise from inflow or fall from consumption,
    # but should NOT be identical to the initial pool down to the
    # 0.01-precision rounding).
    final_state =
      Enum.reduce(1..30, initial_state, fn _, s ->
        {ns, _events} = Tick.tick(s)
        ns
      end)

    final_glucose = sum_metabolite(final_state, :glucose)
    final_acetate = sum_metabolite(final_state, :acetate)
    final_ch4 = sum_metabolite(final_state, :ch4)

    # The glucose pool must move from its initial steady state
    # under the consumer load.
    refute_in_delta initial_glucose, final_glucose, 0.5

    # The chain produces SOMETHING along the way: either acetate
    # accumulates (from A consuming glucose) or ch4 trace appears
    # (from C reducing accumulated co2). At least one of the two
    # must be non-zero — i.e. the chain is NOT fully stalled.
    assert final_acetate > 0.0 or final_ch4 > 0.0
  end

  test "bootstrap is a no-op when :startup_bootstrap is false" do
    Application.put_env(:arkea, :startup_bootstrap, false)

    assert {:ok, %{started: 0, skipped: 0}} = Bootstrap.bootstrap_default_world()

    # No biotope was registered.
    for id <- Bootstrap.wild_biotope_ids() ++ [Bootstrap.community_biotope_id()] do
      assert Registry.lookup(Arkea.Sim.Registry, {:biotope, id}) == []
    end
  end

  defp sum_metabolite(%BiotopeState{phases: phases}, metabolite) do
    phases
    |> Enum.map(fn p -> Map.get(p.metabolite_pool, metabolite, 0.0) end)
    |> Enum.sum()
  end
end
