defmodule Arkea.Sim.HGTTest do
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting
  # `gen all do ... end` blocks compose by nesting; the canonical StreamData
  # pattern legitimately exceeds Credo's default depth here.

  use ExUnit.Case, async: true
  use ExUnitProperties

  @moduletag :sim
  @moduletag timeout: 30_000

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.HGT
  alias Arkea.Sim.Mutator
  alias Arkea.Sim.Phenotype
  alias Arkea.Sim.Tick

  import Arkea.Generators, only: [gene: 0]

  # ---------------------------------------------------------------------------
  # Shared fixtures

  # :transmembrane_anchor — index 2 in Domain.Type.all() → type_tag sum = 2
  @tm_type_tag [0, 0, 2]
  # :catalytic_site — index 1 → sum = 1
  @cat_type_tag [0, 0, 1]
  # :structural_fold — index 8 → sum = 8
  @structural_type_tag [0, 0, 8]

  @param_codons List.duplicate(10, 20)

  defp tm_domain, do: Domain.new(@tm_type_tag, @param_codons)
  defp cat_domain, do: Domain.new(@cat_type_tag, @param_codons)
  defp structural_domain, do: Domain.new(@structural_type_tag, @param_codons)

  defp conjugative_plasmid do
    # One gene with 3 transmembrane_anchor domains → conjugation_strength = 3
    plasmid_gene = Gene.from_domains([tm_domain(), tm_domain(), tm_domain()])
    [plasmid_gene]
  end

  defp non_conjugative_plasmid do
    # One gene with only a structural_fold domain → no transmembrane anchors
    plasmid_gene = Gene.from_domains([structural_domain()])
    [plasmid_gene]
  end

  defp chromosome_gene, do: Gene.from_domains([cat_domain()])

  defp chromosome_gene_with_transfer(module_id) do
    chromosome_gene()
    |> with_intergenic(%{transfer: [module_id]})
  end

  defp donor_genome(plasmid) do
    Genome.new([chromosome_gene()], plasmids: [plasmid])
  end

  defp recipient_genome do
    Genome.new([chromosome_gene()])
  end

  defp recipient_genome_with_hotspot do
    Genome.new([chromosome_gene_with_transfer("integration_hotspot")])
  end

  defp conjugative_plasmid_with_orit do
    plasmid_gene =
      Gene.from_domains([tm_domain(), tm_domain(), tm_domain()])
      |> with_intergenic(%{transfer: ["orit_site"]})

    [plasmid_gene]
  end

  defp surface_phase do
    Phase.new(:surface,
      dilution_rate: 0.02,
      temperature: 25.0,
      ph: 7.0,
      osmolarity: 300.0
    )
    |> Phase.update_metabolite(:glucose, 500.0)
    |> Phase.update_metabolite(:oxygen, 200.0)
  end

  defp make_founder(genome, abundance) do
    Lineage.new_founder(genome, %{surface: abundance}, 0)
  end

  defp with_intergenic(gene, overrides) do
    %{gene | intergenic_blocks: Map.merge(empty_intergenic_blocks(), overrides)}
  end

  defp empty_intergenic_blocks do
    %{expression: [], transfer: [], duplication: []}
  end

  defp count_hgt_children(lineages, ticks, seed) do
    rng = Mutator.init_seed(seed)

    Enum.reduce(1..ticks, {0, rng}, fn tick, {acc_children, acc_rng} ->
      {_updated, children, new_rng} = HGT.step(:surface, lineages, tick, acc_rng)
      {acc_children + length(children), new_rng}
    end)
    |> elem(0)
  end

  # ---------------------------------------------------------------------------
  # Test 1: conjugative plasmid spreads via HGT.step

  # The conjugation probability formula (mass-action model) is designed for
  # biological realism, not for high per-tick transfer rates. With strength=3,
  # n_donor=n_recipient=200 out of n_total=400, p_conj ≈ 0.00375 per step.
  # We test HGT.step/4 directly — not through the full pipeline — so that
  # dilution and mutation do not interfere, and the population remains stable
  # across iterations. Over 2000 independent HGT.step calls the cumulative
  # probability of at least one transfer exceeds 99.9%.
  test "conjugative plasmid spreads: HGT.step produces at least 1 transconjugant in 2000 calls" do
    plasmid = conjugative_plasmid()
    donor = make_founder(donor_genome(plasmid), 200)
    recipient = make_founder(recipient_genome(), 200)
    lineages = [donor, recipient]

    rng = Mutator.init_seed("hgt-test")

    # Accumulate total new children across 2000 HGT.step calls.
    # The lineage list is NOT updated between calls so populations remain stable
    # and the count measures raw conjugation events.
    {total_children, _rng} =
      Enum.reduce(1..2000, {0, rng}, fn tick, {acc_children, acc_rng} ->
        {_updated, children, new_rng} = HGT.step(:surface, lineages, tick, acc_rng)
        {acc_children + length(children), new_rng}
      end)

    assert total_children >= 1,
           "Expected at least 1 conjugation event in 2000 HGT.step calls, got #{total_children}"
  end

  # ---------------------------------------------------------------------------
  # Test 2: non-conjugative plasmid does not spread

  test "non-conjugative plasmid does not produce any HGT children in 2000 calls" do
    plasmid = non_conjugative_plasmid()
    donor = make_founder(donor_genome(plasmid), 200)
    recipient = make_founder(recipient_genome(), 200)
    lineages = [donor, recipient]

    rng = Mutator.init_seed("hgt-test")

    {total_children, _rng} =
      Enum.reduce(1..2000, {0, rng}, fn tick, {acc_children, acc_rng} ->
        {_updated, children, new_rng} = HGT.step(:surface, lineages, tick, acc_rng)
        {acc_children + length(children), new_rng}
      end)

    assert total_children == 0,
           "Non-conjugative plasmid should not spread; got #{total_children} HGT events"
  end

  # ---------------------------------------------------------------------------
  # Test 3: plasmid burden reduces growth delta
  #
  # A plasmid with 2 genes adds 0.6 ATP burden per tick (2 × 0.3).
  # When ATP yield = 0.0 and energy_cost = 0.0:
  #   Without plasmid: net = 0.0 → round(0.0) = 0
  #   With 2-gene plasmid: net_adjusted = 0.0 - 0.6 = -0.6 → round(-0.6) = -1
  # The 0.6 burden crosses the 0.5 rounding threshold, making the difference visible.
  test "plasmid burden reduces growth delta compared to plasmid-free lineage" do
    # Non-conjugative 2-gene plasmid: 2 × 0.3 = 0.6 ATP burden
    structural_gene = Gene.from_domains([structural_domain()])
    burden_plasmid = [structural_gene, structural_gene]

    genome_with_plasmid = Genome.new([chromosome_gene()], plasmids: [burden_plasmid])
    genome_without = Genome.new([chromosome_gene()])

    lineage_with = make_founder(genome_with_plasmid, 100)
    lineage_without = make_founder(genome_without, 100)

    rng = Mutator.init_seed("burden-test")

    state =
      BiotopeState.new_from_opts(
        id: "burden-biotope",
        archetype: :hot_spring,
        phases: [surface_phase()],
        dilution_rate: 0.02,
        lineages: [lineage_with, lineage_without],
        rng_seed: rng,
        metabolite_inflow: %{glucose: 10.0, oxygen: 5.0}
      )

    # Run metabolism first to populate atp_yield_by_lineage, then expression
    state_after_metabolism = Tick.step_metabolism(state)
    state_after_expression = Tick.step_expression(state_after_metabolism)

    delta_with =
      state_after_expression.growth_delta_by_lineage
      |> Map.get(lineage_with.id, %{})
      |> Map.get(:surface, 0)

    delta_without =
      state_after_expression.growth_delta_by_lineage
      |> Map.get(lineage_without.id, %{})
      |> Map.get(:surface, 0)

    assert delta_with < delta_without,
           "Lineage with plasmid (delta=#{delta_with}) should have lower growth delta than lineage without (delta=#{delta_without})"
  end

  # ---------------------------------------------------------------------------
  # Test 4: HGT.conjugative? is consistent with HGT.conjugation_strength > 0

  property "conjugative? iff conjugation_strength > 0" do
    check all(genes <- StreamData.list_of(gene())) do
      assert HGT.conjugative?(genes) == HGT.conjugation_strength(genes) > 0
    end
  end

  # ---------------------------------------------------------------------------
  # Test 5: prophage induction reduces abundance under stress

  # With p_induction = 0.03 per cassette and atp_yield = 0.0 (max stress),
  # E[inductions over 200 calls] = 0.03 × 200 = 6. P(zero inductions) ≈ 0.0025.
  # Each induction removes floor(abundance × 0.5) cells (lytic burst).
  test "prophage induction reduces abundance under maximum stress (atp_yield = 0.0)" do
    prophage_gene = Gene.from_domains([structural_domain()])
    prophage_cassette = [prophage_gene]

    genome_with_prophage =
      Genome.new([chromosome_gene()], prophages: [prophage_cassette])

    lineage = make_founder(genome_with_prophage, 200)
    initial_abundance = Lineage.total_abundance(lineage)

    # Maximum stress: atp_yield = 0.0
    atp_yields = %{lineage.id => 0.0}
    phenotypes = %{lineage.id => Phenotype.from_genome(lineage.genome)}

    rng = Mutator.init_seed("prophage-test")

    # Run induction 200 times; P(no induction in 200 rolls at p=0.03) ≈ 0.0025
    {lineages_after, _rng} =
      Enum.reduce(1..200, {[lineage], rng}, fn _i, {ls, acc_rng} ->
        HGT.induction_step(ls, atp_yields, phenotypes, acc_rng)
      end)

    final_abundance =
      lineages_after
      |> hd()
      |> Lineage.total_abundance()

    assert final_abundance < initial_abundance,
           "Expected prophage induction to reduce abundance below #{initial_abundance}, got #{final_abundance}"
  end

  test "oriT and integration hotspots increase transfer throughput" do
    baseline_lineages = [
      make_founder(donor_genome(conjugative_plasmid()), 200),
      make_founder(recipient_genome(), 200)
    ]

    boosted_lineages = [
      make_founder(donor_genome(conjugative_plasmid_with_orit()), 200),
      make_founder(recipient_genome_with_hotspot(), 200)
    ]

    baseline_children = count_hgt_children(baseline_lineages, 5_000, "hgt-baseline")
    boosted_children = count_hgt_children(boosted_lineages, 5_000, "hgt-boosted")

    assert boosted_children > baseline_children,
           "expected transfer-biased genomes to outproduce baseline HGT events, got #{boosted_children} <= #{baseline_children}"
  end
end
