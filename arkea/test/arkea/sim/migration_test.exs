defmodule Arkea.Sim.MigrationTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Migration

  @moduletag :sim

  property "total lineage abundance is conserved across a reciprocal migration plan" do
    check all(
            source_abundance <- StreamData.integer(0..2_000),
            destination_abundance <- StreamData.integer(0..2_000)
          ) do
      source =
        build_state(
          id: Arkea.UUID.v4(),
          x: 0.0,
          y: 0.0,
          neighbor_ids: [],
          lineages: [build_lineage(%{surface: source_abundance})]
        )

      destination =
        build_state(
          id: Arkea.UUID.v4(),
          x: 0.0,
          y: 0.0,
          neighbor_ids: [source.id],
          lineages: [build_lineage(%{surface: destination_abundance})]
        )

      source = %{source | neighbor_ids: [destination.id]}
      plan = Migration.plan([source, destination], base_flow: 0.5)

      before_total =
        BiotopeState.total_abundance(source) + BiotopeState.total_abundance(destination)

      after_total =
        [source, destination]
        |> Enum.map(fn state ->
          Migration.apply_transfer(state, Map.get(plan, state.id, Migration.empty_transfer()))
        end)
        |> Enum.sum_by(&BiotopeState.total_abundance/1)

      assert after_total == before_total
    end
  end

  test "migration prefers environmentally matching destination phases" do
    source =
      build_state(
        id: Arkea.UUID.v4(),
        x: 0.0,
        y: 0.0,
        phases: [
          Phase.new(:surface, temperature: 18.0, ph: 7.1, osmolarity: 60.0, dilution_rate: 0.0),
          Phase.new(:sediment, temperature: 8.0, ph: 6.0, osmolarity: 140.0, dilution_rate: 0.0)
        ],
        neighbor_ids: [],
        lineages: [build_lineage(%{surface: 200})]
      )

    destination =
      build_state(
        id: Arkea.UUID.v4(),
        x: 0.0,
        y: 0.0,
        phases: [
          Phase.new(:surface, temperature: 18.5, ph: 7.0, osmolarity: 65.0, dilution_rate: 0.0),
          Phase.new(:sediment, temperature: 2.0, ph: 4.2, osmolarity: 900.0, dilution_rate: 0.0)
        ],
        neighbor_ids: [],
        lineages: []
      )

    source = %{source | neighbor_ids: [destination.id]}
    plan = Migration.plan([source, destination], base_flow: 0.5)

    updated_destination =
      Migration.apply_transfer(
        destination,
        Map.get(plan, destination.id, Migration.empty_transfer())
      )

    migrated = hd(updated_destination.lineages)

    assert Lineage.abundance_in(migrated, :surface) > Lineage.abundance_in(migrated, :sediment)
  end

  test "metabolites, signals and phages follow the same edge graph" do
    cassette_gene = Gene.from_domains([Domain.new([0, 0, 9], List.duplicate(8, 20))])

    virion =
      Arkea.Sim.HGT.Virion.new(
        id: "phage-a",
        genes: [cassette_gene],
        abundance: 40,
        created_at_tick: 0
      )

    source_phase =
      Phase.new(:surface, dilution_rate: 0.0)
      |> Phase.update_metabolite(:glucose, 100.0)
      |> Phase.update_signal("sig-a", 50.0)
      |> Phase.add_virion(virion)

    source =
      build_state(
        id: Arkea.UUID.v4(),
        x: 0.0,
        y: 0.0,
        phases: [source_phase],
        neighbor_ids: [],
        lineages: []
      )

    destination =
      build_state(
        id: Arkea.UUID.v4(),
        x: 0.0,
        y: 0.0,
        phases: [Phase.new(:surface, dilution_rate: 0.0)],
        neighbor_ids: [],
        lineages: []
      )

    source = %{source | neighbor_ids: [destination.id]}

    plan =
      Migration.plan(
        [source, destination],
        base_flow: 1.0,
        metabolite_flow_scale: 1.0,
        signal_flow_scale: 1.0,
        phage_flow_scale: 1.0
      )

    updated_source =
      Migration.apply_transfer(source, Map.get(plan, source.id, Migration.empty_transfer()))

    updated_destination =
      Migration.apply_transfer(
        destination,
        Map.get(plan, destination.id, Migration.empty_transfer())
      )

    src_phase = hd(updated_source.phases)
    dst_phase = hd(updated_destination.phases)

    assert src_phase.metabolite_pool == %{}
    assert src_phase.signal_pool == %{}
    assert src_phase.phage_pool == %{}

    assert dst_phase.metabolite_pool == %{glucose: 100.0}
    assert dst_phase.signal_pool == %{"sig-a" => 50.0}

    assert match?(
             %{"phage-a" => %Arkea.Sim.HGT.Virion{abundance: 40}},
             dst_phase.phage_pool
           )
  end

  defp build_state(opts) do
    BiotopeState.new_from_opts(
      id: Keyword.fetch!(opts, :id),
      archetype: :eutrophic_pond,
      x: Keyword.get(opts, :x, 0.0),
      y: Keyword.get(opts, :y, 0.0),
      zone: :test_zone,
      phases: Keyword.get(opts, :phases, [Phase.new(:surface, dilution_rate: 0.0)]),
      dilution_rate: 0.0,
      neighbor_ids: Keyword.get(opts, :neighbor_ids, []),
      lineages: Keyword.get(opts, :lineages, [])
    )
  end

  defp build_lineage(abundances) do
    Lineage.new_founder(simple_genome(), abundances, 0)
  end

  defp simple_genome do
    domain = Domain.new([0, 0, 0], List.duplicate(0, 20))
    gene = Gene.from_domains([domain])
    Genome.new([gene])
  end
end
