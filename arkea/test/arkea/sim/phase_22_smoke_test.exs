defmodule Arkea.Sim.Phase22SmokeTest do
  @moduledoc """
  End-to-end smoke test for Phase 22 (Analisi base + polish).

  Reuses the same 2-lineage scenario as the Phase 21 smoke
  (donor with conjugative plasmid + regulator + plain recipient),
  drives 30 ticks through the real `BiotopeServer` pipeline with
  persistence enabled, and asserts that each of the four
  Phase-22 deliverables produces its observable artefact:

    * **2.8 PhenotypeDistribution** — `build/3` over the
      persisted `phenotype_trait` samples + the live
      abundance map produces one point per genome-bearing
      lineage with a sensible weighted-mean within the
      trait's observed value domain.

    * **2.4 MetabolicMap** — `build/1` on the post-tick state
      returns the canonical 13 rows × N phases shape with
      per-row normalised intensities, and the row's `max`
      tracks the live `metabolite_pool`.

    * **2.3a GenomeDiff** — `build/2` on the donor vs the
      recipient returns `identical?: false` with the donor's
      regulator gene and conjugative plasmid surfaced under
      `chromosome.a_only` / `plasmids.a_only`. Donor compared
      to itself returns `identical?: true`.

    * **8.2 Biotope stress chip** —
      `ArkeaWeb.SimLive.biotope_stress_level/1` returns
      `tier: :low` on a stable post-30-tick biotope (no SOS
      induction in this benign scenario).

  Reproducible: `Mutator.init_seed("phase-22-smoke")`. Fail = a
  Phase-22 artefact regressed.
  """

  use Arkea.DataCase, async: false
  use Oban.Testing, repo: Arkea.Repo

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Persistence.TimeSeries
  alias Arkea.Sim.Biotope.Server, as: BiotopeServer
  alias Arkea.Sim.Biotope.Supervisor, as: BiotopeSupervisor
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Mutator
  alias Arkea.Views.GenomeDiff
  alias Arkea.Views.MetabolicMap
  alias Arkea.Views.PhenotypeDistribution

  @param_codons List.duplicate(10, 20)

  defp catalytic_domain, do: Domain.new([0, 0, 1], @param_codons)
  defp transmembrane_domain, do: Domain.new([0, 0, 2], @param_codons)
  defp dna_binding_domain, do: Domain.new([0, 0, 5], @param_codons)
  # type_tag sum 6 → :regulator_output, even first param codon → :activator.
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

    # Pre-seed a tiny inflow of the canary nutrients so the
    # MetabolicMap row-max assertion can fire on a deterministic
    # value rather than relying on archetype-driven inflow logic
    # (which `BiotopeState.new_from_opts/1` does not run).
    %{base | metabolite_pool: %{glucose: 200.0, nh3: 40.0, po4: 10.0}}
  end

  defp build_state do
    donor = Lineage.new_founder(founder_genome(), %{surface: 200}, 0)
    recipient = Lineage.new_founder(recipient_genome(), %{surface: 200}, 0)

    BiotopeState.new_from_opts(
      id: Arkea.UUID.v4(),
      archetype: :eutrophic_pond,
      zone: :phase_22_smoke,
      phases: [surface_phase()],
      dilution_rate: 0.0,
      lineages: [donor, recipient],
      rng_seed: Mutator.init_seed("phase-22-smoke")
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

  test "Phase 22 smoke: 30 ticks of a regulator + conjugative seed exercises every Phase-22 artefact" do
    state = build_state()
    [donor, recipient] = state.lineages

    start_biotope(state)

    # Drive the simulation: 30 ticks → 3 cellular sampling boundaries
    # for `phenotype_trait` samples (10, 20, 30).
    for _i <- 1..30 do
      assert :ok = BiotopeServer.manual_tick(state.id)
    end

    persisted = BiotopeServer.get_state(state.id)
    assert persisted.tick_count == 30

    abundances =
      Map.new(persisted.lineages, fn l -> {l.id, Lineage.total_abundance(l)} end)

    # ---------------------------------------------------------------
    # 2.8 PhenotypeDistribution — strip plot of `repair_efficiency`
    # at the latest tick.

    trait_samples = TimeSeries.list(state.id, kind: "phenotype_trait", repo: Repo)
    assert trait_samples != [], "expected phenotype_trait samples after 30 ticks"

    distribution = PhenotypeDistribution.build(trait_samples, "repair_efficiency", abundances)

    assert distribution.trait == "repair_efficiency"
    assert distribution.tick == 30
    # Each genome-bearing lineage that survived contributes one point.
    assert distribution.points != []
    # Weighted mean lies inside the observed x-domain.
    {min_x, max_x} = distribution.x_domain
    assert distribution.weighted_mean >= min_x
    assert distribution.weighted_mean <= max_x
    # Total abundance equals the sum of plotted points.
    plotted_total = distribution.points |> Enum.map(& &1.y) |> Enum.sum()
    assert distribution.total_abundance == plotted_total

    # ---------------------------------------------------------------
    # 2.4 MetabolicMap — 13 rows × 1 phase (only :surface) for this
    # biotope; per-row intensity in [0.0, 1.0].

    metabolic_map = MetabolicMap.build(persisted)
    assert length(metabolic_map.rows) == 13
    assert metabolic_map.phases == [:surface]
    assert metabolic_map.metabolites == MetabolicMap.metabolite_order()

    for row <- metabolic_map.rows do
      [cell] = row.cells
      assert cell.intensity >= 0.0 and cell.intensity <= 1.0
      # Sanity: the cell value tracks the live metabolite_pool entry.
      [%Phase{metabolite_pool: pool}] = persisted.phases
      assert cell.value == Map.get(pool, row.metabolite, 0.0) * 1.0
    end

    # Sanity: at least one row has non-zero intensity (eutrophic_pond
    # archetype seeds glucose / nh3 / po4 in the inflow).
    assert Enum.any?(metabolic_map.rows, fn row -> row.max > 0.0 end)

    # ---------------------------------------------------------------
    # 2.3a GenomeDiff — donor vs recipient must differ on the
    # regulator gene + conjugative plasmid; donor vs itself is
    # identical.

    persisted_donor = Enum.find(persisted.lineages, &(&1.id == donor.id))
    persisted_recipient = Enum.find(persisted.lineages, &(&1.id == recipient.id))

    self_diff = GenomeDiff.build(persisted_donor.genome, persisted_donor.genome)
    assert self_diff.identical?

    cross_diff = GenomeDiff.build(persisted_donor.genome, persisted_recipient.genome)
    refute cross_diff.identical?
    # Donor carries the regulator gene + conjugative plasmid that
    # the recipient lacks.
    assert cross_diff.chromosome.a_only != []
    assert match?([_one], cross_diff.plasmids.a_only)

    # The regulator gene's signature must show a `:regulator_output`
    # in its domain types.
    regulator_summary =
      Enum.find(cross_diff.chromosome.a_only, fn s ->
        :regulator_output in s.domain_types
      end)

    assert regulator_summary, "donor's regulator gene should appear in chromosome.a_only"

    # ---------------------------------------------------------------
    # 8.2 Biotope stress chip — a stable benign scenario should sit
    # in the green band well below the SOS threshold.

    stress = ArkeaWeb.SimLive.biotope_stress_level(persisted)

    assert stress.tier == :low,
           "expected :low stress tier on a benign 30-tick eutrophic_pond run; " <>
             "got #{inspect(stress)}"

    # Empty-state contract: no lineages → still :low (chip never blank).
    empty_stress = ArkeaWeb.SimLive.biotope_stress_level(%{lineages: []})
    assert empty_stress.tier == :low
    assert empty_stress.label == "0.000"
  end
end
