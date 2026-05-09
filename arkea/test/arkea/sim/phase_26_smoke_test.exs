defmodule Arkea.Sim.Phase26SmokeTest do
  @moduledoc """
  End-to-end smoke test for Phase 26 (Codon-level visibility +
  ancestral / gene-tree analysis tools).

  Same scenario as the Phase 21 / 22 / 24 / 25 smokes — a donor
  + recipient seeded into one biotope, 30 ticks driven through
  the real `BiotopeServer` pipeline with persistence enabled —
  asserts that every Phase-26 deliverable produces its
  observable artefact.

    * **1.13 / 1.14 audit events** — `:domain_flip` and
      `:gene_chimera_birth` are emitted into the audit log
      whenever the corresponding mutation classes fire, and
      consumed by the hotspot view (no assertion of a *specific*
      count — the seeded RNG may or may not roll either event;
      the assertion is only that the audit pipe doesn't crash
      and the consumer view tolerates an empty audit too).
    * **2.6 CodonViewer** — `Arkea.Views.CodonViewer.build/1`
      annotates every codon with its role (type_tag /
      parameter_codon / promoter / regulatory).
    * **2.7 MutationHotspot** — `Arkea.Views.MutationHotspot.
      build/2` produces a per-codon count map.
    * **2.9 DomainLandscape** — `Arkea.Views.DomainLandscape.
      build/2` surfaces every catalytic-site domain across the
      population with `kcat × Km`-ready params.
    * **2.3b GeneDiff** — `Arkea.Views.GeneDiff.build/2`
      compares two gene variants codon-by-codon.
    * **3.6 / 3.7 AncestralReconstruction** —
      `Arkea.Views.AncestralReconstruction.genome_trace/2` and
      `gene_trace/3` walk the lineage chain.
    * **3.8 GeneTree** — `Arkea.Views.GeneTree.build/2`
      clusters lineages by gene similarity and flags
      species/gene-tree topology.
    * **8.9 + 8.10 GenomeCanvas** — `from_preview/1` carries
      prophages with a `replicon_kind: :prophage` tag and
      `rich_domain_tooltip/2` produces chemically-meaningful
      tooltip strings for the seeded catalytic site.

  Reproducible: `Mutator.init_seed("phase-26-smoke")`.
  """

  use Arkea.DataCase, async: false
  use Oban.Testing, repo: Arkea.Repo

  import Ecto.Query

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Persistence.AuditLog
  alias Arkea.Sim.Biotope.Server, as: BiotopeServer
  alias Arkea.Sim.Biotope.Supervisor, as: BiotopeSupervisor
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Mutator
  alias Arkea.Views.AncestralReconstruction
  alias Arkea.Views.CodonViewer
  alias Arkea.Views.DomainLandscape
  alias Arkea.Views.GeneDiff
  alias Arkea.Views.GeneTree
  alias Arkea.Views.GenomeCanvas
  alias Arkea.Views.MutationHotspot

  @param_codons List.duplicate(10, 20)

  defp catalytic_domain, do: Domain.new([0, 0, 1], @param_codons)
  defp transmembrane_domain, do: Domain.new([0, 0, 2], @param_codons)
  defp dna_binding_domain, do: Domain.new([0, 0, 5], @param_codons)

  defp founder_genome do
    chromosome = [
      Gene.from_domains([catalytic_domain(), dna_binding_domain()]),
      Gene.from_domains([transmembrane_domain()])
    ]

    plasmid = [Gene.from_domains([transmembrane_domain()])]

    prophage_genes = [Gene.from_domains([catalytic_domain()])]

    prophage = %{
      genes: prophage_genes,
      state: :lysogenic,
      repressor_strength: 0.7
    }

    Genome.new(chromosome, plasmids: [plasmid], prophages: [prophage])
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
      zone: :phase_26_smoke,
      phases: [surface_phase()],
      dilution_rate: 0.0,
      lineages: [donor, recipient],
      rng_seed: Mutator.init_seed("phase-26-smoke")
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

  test "Phase 26 smoke: codon viewer + hotspot + landscape + diff + ancestral + gene tree + canvas" do
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
    [target_gene | _] = genome.chromosome

    audit_rows =
      Repo.all(
        from a in AuditLog,
          where: a.target_biotope_id == ^state.id,
          order_by: [asc: a.occurred_at_tick]
      )

    # ---------------------------------------------------------------
    # 2.6 CodonViewer — every codon annotated with its role.

    codon_view = CodonViewer.build(target_gene)
    assert codon_view.codon_count == length(target_gene.codons)
    assert codon_view.domain_count == length(target_gene.domains)
    assert Enum.any?(codon_view.codons, &(&1.role == :type_tag))
    assert Enum.any?(codon_view.codons, &(&1.role == :parameter_codon))

    # ---------------------------------------------------------------
    # 2.7 MutationHotspot — bins length matches codon_count; the
    # view tolerates an empty / non-empty audit.

    hotspot = MutationHotspot.build(target_gene, audit_rows)
    assert hotspot.codon_count == length(target_gene.codons)
    assert hotspot.total_events >= 0
    assert length(hotspot.bins) == hotspot.codon_count

    # ---------------------------------------------------------------
    # 2.9 DomainLandscape — at least one catalytic site emitted by
    # the seeded chromosome + prophage.

    landscape = DomainLandscape.build(persisted.lineages, :catalytic_site)
    assert landscape.domain_type == :catalytic_site
    assert landscape.point_count >= 2
    assert Enum.all?(landscape.points, &Map.has_key?(&1.params, :kcat))
    replicons = landscape.points |> Enum.map(& &1.replicon) |> Enum.uniq()
    assert :chromosome in replicons
    assert :prophage in replicons

    # ---------------------------------------------------------------
    # 2.3b GeneDiff — diffing the seed gene against itself yields a
    # zero-substitution result (regression: the view doesn't
    # spuriously flag identity).

    diff = GeneDiff.build(target_gene, target_gene)
    assert diff.substitutions == 0
    assert diff.codon_count_a == diff.codon_count_b
    assert Enum.all?(diff.positions, &(&1.change == :match))

    # ---------------------------------------------------------------
    # 3.6 / 3.7 AncestralReconstruction — the genome_trace and
    # gene_trace walk the donor's chain back to itself (founder).

    genome_trace = AncestralReconstruction.genome_trace(persisted.lineages, donor.id)
    assert genome_trace.depth >= 1
    assert hd(genome_trace.ancestors).lineage_id == donor.id

    gene_trace = AncestralReconstruction.gene_trace(persisted.lineages, donor.id, 0)
    assert gene_trace.depth >= 1
    assert Enum.any?(gene_trace.trace, &(&1.status == :present))

    # ---------------------------------------------------------------
    # 3.8 GeneTree — clustering lineages by their first chromosome
    # gene yields at least one cluster covering the donor.

    tree =
      GeneTree.build(persisted.lineages,
        gene_extractor: fn
          %Lineage{genome: nil} -> nil
          %Lineage{genome: g} -> hd(g.chromosome)
        end
      )

    assert tree.cluster_count >= 1

    assert Enum.any?(tree.clusters, fn c ->
             Enum.any?(c.members, &(&1.lineage_id == donor.id))
           end)

    # ---------------------------------------------------------------
    # 8.9 + 8.10 GenomeCanvas — `from_preview/1` extracts prophages
    # and `rich_domain_tooltip/2` produces a chemical / functional
    # tooltip for the seeded catalytic site.

    preview = %{genome: genome, custom_gene_count: 0}
    canvas_data = GenomeCanvas.from_preview(preview)
    assert length(canvas_data.prophages) == 1
    [prophage] = canvas_data.prophages
    assert prophage.state == :lysogenic
    assert length(prophage.genes) == 1

    layout = GenomeCanvas.build(canvas_data)
    assert layout.chromosome.replicon_kind == :chromosome
    assert Enum.all?(layout.plasmids, &(&1.replicon_kind == :plasmid))
    assert Enum.all?(layout.prophages, &(&1.replicon_kind == :prophage))

    # Every chromosome domain in the canvas data carries a tooltip
    # string that is at least as informative as the type name.
    [first_gene | _] = canvas_data.chromosome
    assert Enum.all?(first_gene.domains, &is_binary(&1.tooltip))
    cat_dom = Enum.find(first_gene.domains, &(&1.type == :catalytic_site))
    assert cat_dom != nil
    assert cat_dom.tooltip =~ "catalytic_site"
    assert cat_dom.tooltip =~ "kcat"
  end
end
