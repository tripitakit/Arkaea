defmodule Arkea.Sim.Phase25SmokeTest do
  @moduledoc """
  End-to-end smoke test for Phase 25 (Operons & regulation —
  *structural + view layer*).

  Same regulator + conjugative-plasmid scenario as the Phase
  21 / 22 / 24 smokes; we drive 30 ticks through the real
  `BiotopeServer` pipeline with persistence enabled and assert
  that each Phase-25 view / structural surface produces its
  observable artefact.

  Phase 25 deliberately ships only the *structural + view*
  layer of L1.1, L1.3, L4 and L5. The *runtime cabling* parts
  (operon-aware σ in `Tick.step_expression/1` ↔ 7.2b, SOS
  threshold derived from `:ligand_sensor` ↔ 7.6) are deferred
  to a follow-up phase ("25.5 — runtime cabling") so the
  Phase 5/6/7 calibration stays untouched. This smoke test
  therefore asserts on view shapes, not on simulation
  trajectories.

    * **7.2a Operon** — `Arkea.Genome.Operon.operons/1` groups
      chromosome genes by `operon_id` in chromosome order.
    * **7.3 Regulation parser** — `Arkea.Genome.Regulation.
      promoter_sites/1` and `riboswitches/1` parse the
      `promoter_block` / `regulatory_block` codons.
    * **2.5 RegulatoryNetwork** — `Arkea.Views.RegulatoryNetwork.
      build/1` produces `{nodes, edges}` consuming 7.1 + 7.2a
      + 7.3.
    * **3.X advanced phylogeny** — `Phylogeny.enrich_with_branch_
      metrics/2` adds `:phenotype_displacement` + `:hgt_received`
      per node; `colour_by_trait/2` annotates `:colour_value`.
    * **2.2 GeneExpression** — `Arkea.Views.GeneExpression.
      derive/1` returns `[%{gene_id, base_level, modulation,
      expression}]` with sign-correct activator/repressor
      modulation.

  Reproducible: `Mutator.init_seed("phase-25-smoke")`.
  """

  use Arkea.DataCase, async: false
  use Oban.Testing, repo: Arkea.Repo

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Genome.Operon
  alias Arkea.Genome.Regulation
  alias Arkea.Sim.Biotope.Server, as: BiotopeServer
  alias Arkea.Sim.Biotope.Supervisor, as: BiotopeSupervisor
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Mutator
  alias Arkea.Views.GeneExpression
  alias Arkea.Views.Phylogeny
  alias Arkea.Views.RegulatoryNetwork

  @param_codons List.duplicate(10, 20)

  defp catalytic_domain, do: Domain.new([0, 0, 1], @param_codons)
  defp transmembrane_domain, do: Domain.new([0, 0, 2], @param_codons)
  defp dna_binding_domain, do: Domain.new([0, 0, 5], @param_codons)

  defp activator_regulator_domain do
    Domain.new([0, 0, 6], [0 | List.duplicate(10, 19)])
  end

  defp founder_genome do
    op_id = Arkea.UUID.v4()

    chromosome = [
      # Two operon-co-located genes — the 7.2a structural
      # surface should group them under op_id.
      %{Gene.from_domains([catalytic_domain()]) | operon_id: op_id},
      %{
        Gene.from_domains([dna_binding_domain(), activator_regulator_domain()])
        | operon_id: op_id
      },
      # A solo gene with a 5-codon riboswitch in regulatory_block
      # so the 7.3 parser has data to chew on.
      %{
        Gene.from_domains([catalytic_domain()])
        | regulatory_block: [3, 10, 0, 0, 19],
          promoter_block: [1, 2, 3, 19]
      }
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
      zone: :phase_25_smoke,
      phases: [surface_phase()],
      dilution_rate: 0.0,
      lineages: [donor, recipient],
      rng_seed: Mutator.init_seed("phase-25-smoke")
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

  test "Phase 25 smoke: regulator + operon + riboswitch seed exercises every Phase-25 surface" do
    state = build_state()
    [donor, _recipient] = state.lineages

    start_biotope(state)

    for _i <- 1..30 do
      assert :ok = BiotopeServer.manual_tick(state.id)
    end

    persisted = BiotopeServer.get_state(state.id)
    assert persisted.tick_count == 30

    persisted_donor = Enum.find(persisted.lineages, &(&1.id == donor.id))
    genome = persisted_donor.genome

    # ---------------------------------------------------------------
    # 7.2a Operon — two operon-co-located genes group under one
    # operon entry; the third gene (no operon_id) is a solo.

    operons = Operon.operons(genome)
    assert match?([_one], operons)
    [op] = operons
    assert op.gene_count == 2
    assert length(Operon.solo_genes(genome)) == 1

    # ---------------------------------------------------------------
    # 7.3 Regulation parser — promoter_sites + riboswitches read
    # the codons we seeded into the third gene.

    [_g1, _g2, regulated_gene] = genome.chromosome

    [site] = Regulation.promoter_sites(regulated_gene)
    assert site.signature == "1,2,3"
    assert_in_delta site.strength, 1.0, 1.0e-9

    [riboswitch] = Regulation.riboswitches(regulated_gene)
    assert riboswitch.metabolite_id == 3
    assert riboswitch.mode == :activator

    # ---------------------------------------------------------------
    # 2.5 RegulatoryNetwork — graph builder consumes 7.1 + 7.2a + 7.3
    # and produces nodes / edges; counts roll up correctly.

    network = RegulatoryNetwork.build(genome)
    assert network.gene_count == 3
    assert network.operon_count == 1
    assert network.regulator_count >= 1
    assert network.riboswitch_count == 1

    # Operon-member edges have a leader flag exactly once per operon.
    member_edges = Enum.filter(network.edges, &(&1.kind == :operon_member))
    leaders = Enum.filter(member_edges, & &1.payload.leader?)
    assert length(leaders) == 1

    # ---------------------------------------------------------------
    # 3.X advanced phylogeny — branch-metric enrichment +
    # trait colouring augment the Phylogeny model in place.

    audit = []

    phylogeny =
      [persisted_donor]
      |> Phylogeny.build(audit)
      |> Phylogeny.enrich_with_branch_metrics(audit)
      |> Phylogeny.colour_by_trait(:repair_efficiency)

    donor_node = Enum.find(phylogeny.nodes, &(&1.id == donor.id))
    assert is_float(donor_node.phenotype_displacement)
    assert donor_node.phenotype_displacement >= 0.0
    assert donor_node.hgt_received >= 0
    assert donor_node.colour_value == donor_node.phenotype.repair_efficiency

    # ---------------------------------------------------------------
    # 2.2 GeneExpression — per-gene expression entries; the
    # activator-regulator operon member should show positive
    # modulation, the catalytic-only genes zero modulation.

    entries = GeneExpression.derive(genome)
    assert length(entries) == 3

    [_solo_first, regulator_entry, regulated_third] = entries
    assert regulator_entry.modulation > 0.0
    assert regulated_third.modulation == 0.0
  end
end
