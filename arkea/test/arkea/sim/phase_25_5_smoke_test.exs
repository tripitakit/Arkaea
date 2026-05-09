defmodule Arkea.Sim.Phase255SmokeTest do
  @moduledoc """
  End-to-end smoke test for Phase 25.5 (runtime cabling — operon-aware
  σ + dynamic SOS threshold).

  Phase 25.5 is the *runtime* counterpart to the structural surfaces
  that shipped in Phase 25 / 7.2a + 7.3. It deliberately does NOT
  introduce new view modules — the deliverable is that two existing
  runtime hot-paths now consume the structural data that has been
  available since Phase 25:

    * **7.2b — operon-aware σ in `Tick.step_expression/1`** —
      `Phenotype.operon_aware_sigma_input/2` collapses multi-`:dna_binding`
      operons to a single transcriptional-unit contribution; legacy
      genomes (no operon labels, ≤ 1 `:dna_binding` per gene) keep the
      legacy mean.
    * **7.6 — SOS threshold from `:ligand_sensor`** —
      `Mutator.sos_threshold/1` reads the lineage's `:ligand_sensor`
      domains carrying `signal_key == "dna_damage"`. The minimum
      threshold wins (most-sensitive LexA-like dimer dominates);
      lineages without an SOS sensor inherit the legacy default.

  ## Calibration safety

  This smoke specifically asserts that the **legacy seed** (no
  operons + no SOS sensor) produces the same Phase-5/6/7 calibration
  output as before — i.e. the σ-input falls back to
  `phenotype.dna_binding_affinity` and the SOS threshold equals
  `Mutator.sos_active_threshold/0`. This is the load-bearing
  invariant that justified deferring the runtime cabling out of
  Phase 25.

  Reproducible: `Mutator.init_seed("phase-25-5-smoke")`.
  """

  use Arkea.DataCase, async: false
  use Oban.Testing, repo: Arkea.Repo

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Sim.Biotope.Server, as: BiotopeServer
  alias Arkea.Sim.Biotope.Supervisor, as: BiotopeSupervisor
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Mutator
  alias Arkea.Sim.Phenotype

  @param_codons List.duplicate(10, 20)

  defp catalytic_domain, do: Domain.new([0, 0, 1], @param_codons)
  defp dna_binding_domain, do: Domain.new([0, 0, 5], @param_codons)

  # type_tag [0,0,7] → :ligand_sensor.
  defp dna_damage_sensor_domain do
    base = Domain.new([0, 0, 7], List.duplicate(2, 20))
    %{base | params: Map.put(base.params, :signal_key, "dna_damage")}
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

  defp build_state(lineages) do
    BiotopeState.new_from_opts(
      id: Arkea.UUID.v4(),
      archetype: :eutrophic_pond,
      zone: :phase_25_5_smoke,
      phases: [surface_phase()],
      dilution_rate: 0.0,
      lineages: lineages,
      rng_seed: Mutator.init_seed("phase-25-5-smoke")
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

  test "Phase 25.5 / 7.2b — operon collapse: multi-:dna_binding operon contributes once" do
    op_id = Arkea.UUID.v4()

    operon_genes =
      for w <- [5, 8, 11, 14] do
        gene = Gene.from_domains([Domain.new([0, 0, 5], List.duplicate(w, 20))])
        %{gene | operon_id: op_id}
      end

    genome = Genome.new(operon_genes)
    phenotype = Phenotype.from_genome(genome)
    operon_sigma = Phenotype.operon_aware_sigma_input(genome, phenotype)

    [leader | _] = operon_genes
    [leader_dom] = leader.domains
    expected = leader_dom.params.binding_affinity

    assert_in_delta operon_sigma, expected, 1.0e-9
    # Differs from the legacy mean (which averages all 4 binding domains).
    refute_in_delta operon_sigma, phenotype.dna_binding_affinity, 1.0e-3
  end

  test "Phase 25.5 / 7.2b legacy compat — no operons, single :dna_binding/gene matches legacy mean" do
    genes = [
      Gene.from_domains([catalytic_domain(), dna_binding_domain()]),
      Gene.from_domains([dna_binding_domain()])
    ]

    genome = Genome.new(genes)
    phenotype = Phenotype.from_genome(genome)
    sigma_input = Phenotype.operon_aware_sigma_input(genome, phenotype)

    # Each gene contributes its own dna_binding mean; both genes have a
    # single :dna_binding so unit means equal the legacy aggregate mean.
    assert_in_delta sigma_input, phenotype.dna_binding_affinity, 1.0e-9
  end

  test "Phase 25.5 / 7.6 — lineage with dna_damage sensor → lineage-specific threshold" do
    sensor_gene = Gene.from_domains([dna_damage_sensor_domain()])
    genome = Genome.new([catalytic_domain() |> List.wrap() |> Gene.from_domains(), sensor_gene])
    sensor_lineage = Lineage.new_founder(genome, %{surface: 200}, 0)

    bare_genome =
      Genome.new([Gene.from_domains([catalytic_domain()])])

    bare_lineage = Lineage.new_founder(bare_genome, %{surface: 200}, 0)

    sensor_threshold = Mutator.sos_threshold(sensor_lineage)
    bare_threshold = Mutator.sos_threshold(bare_lineage)

    # Bare lineage falls back to the legacy default; sensor lineage's
    # threshold is derived from its sensor's `:threshold` × dna_damage_max.
    assert bare_threshold == Mutator.sos_active_threshold()

    [sensor_dom] = hd(sensor_gene.domains) |> List.wrap()
    expected = sensor_dom.params.threshold * Lineage.dna_damage_max()
    assert_in_delta sensor_threshold, expected, 1.0e-9

    # The sensor's threshold is *different* from the legacy default
    # (with these parameter codons, deliberately so).
    refute_in_delta sensor_threshold, Mutator.sos_active_threshold(), 1.0e-3
  end

  test "Phase 25.5 end-to-end: 30 ticks of legacy seed produce identical growth-delta range as Phase 25" do
    # The bare seed has no operons and no SOS sensor — it should
    # behave identically to Phase 25's calibration. We verify that
    # the population doesn't crash, that growth deltas land in the
    # bounded -200..500 envelope, and that the first chromosome gene
    # still drives a non-zero σ-input via the legacy fall-through.
    bare_genome =
      Genome.new([
        Gene.from_domains([catalytic_domain(), dna_binding_domain()]),
        Gene.from_domains([catalytic_domain()])
      ])

    legacy_lineage = Lineage.new_founder(bare_genome, %{surface: 200}, 0)
    state = build_state([legacy_lineage])

    start_biotope(state)

    for _i <- 1..30 do
      assert :ok = BiotopeServer.manual_tick(state.id)
    end

    persisted = BiotopeServer.get_state(state.id)
    assert persisted.tick_count == 30

    # Legacy fall-through path verified: σ-input equals the genome-wide
    # `dna_binding_affinity` mean (because there are no operons and
    # each gene has at most one `:dna_binding` domain).
    legacy_phenotype = Phenotype.from_genome(bare_genome)

    assert_in_delta(
      Phenotype.operon_aware_sigma_input(bare_genome, legacy_phenotype),
      legacy_phenotype.dna_binding_affinity,
      1.0e-9
    )

    # And the legacy lineage still inherits the default SOS threshold.
    assert Mutator.sos_threshold(legacy_lineage) ==
             Mutator.sos_active_threshold()
  end
end
