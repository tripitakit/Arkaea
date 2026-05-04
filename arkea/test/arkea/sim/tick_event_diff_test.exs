defmodule Arkea.Sim.TickEventDiffTest do
  @moduledoc """
  Targets the new state-diff event detectors added in UI Phase B
  (`derive_events/2` extension): `:mass_lysis`, `:colonization`,
  `:phage_burst`, `:mutation_notable`.
  """
  use ExUnit.Case, async: true

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Tick

  describe "mass_lysis detection" do
    test "emits :mass_lysis when phase population drops > 30%" do
      lineage_id = Arkea.UUID.v4()
      old = state_with_lineage(lineage_id, %{water_column: 1000})
      new = state_with_lineage(lineage_id, %{water_column: 500})

      events = Tick.derive_events(old, new)
      lysis = Enum.filter(events, &(&1.type == :mass_lysis))

      assert length(lysis) == 1
      payload = hd(lysis).payload
      assert payload.phase == "water_column"
      assert payload.population_before == 1000
      assert payload.population_after == 500
      assert payload.fraction_lost >= 0.3
    end

    test "no :mass_lysis for small populations or moderate drops" do
      lineage_id = Arkea.UUID.v4()
      old = state_with_lineage(lineage_id, %{water_column: 100})
      new = state_with_lineage(lineage_id, %{water_column: 30})

      events = Tick.derive_events(old, new)
      assert Enum.filter(events, &(&1.type == :mass_lysis)) == []
    end

    test "no :mass_lysis when the population grows or stays flat" do
      lineage_id = Arkea.UUID.v4()
      old = state_with_lineage(lineage_id, %{water_column: 1000})
      new = state_with_lineage(lineage_id, %{water_column: 1500})

      events = Tick.derive_events(old, new)
      assert Enum.filter(events, &(&1.type == :mass_lysis)) == []
    end
  end

  describe "colonization detection" do
    test "emits :colonization when an existing lineage crosses the threshold from 0" do
      lineage_id = Arkea.UUID.v4()
      old = state_with_lineage(lineage_id, %{water_column: 200, sediment: 0})
      new = state_with_lineage(lineage_id, %{water_column: 200, sediment: 80})

      events = Tick.derive_events(old, new)
      colonisation = Enum.filter(events, &(&1.type == :colonization))

      assert length(colonisation) == 1
      payload = hd(colonisation).payload
      assert payload.lineage_id == lineage_id
      assert payload.phase == "sediment"
      assert payload.abundance == 80
    end

    test "no :colonization for newly-born lineages (those carry :lineage_born instead)" do
      old_id = Arkea.UUID.v4()
      new_id = Arkea.UUID.v4()

      old = state_with_lineage(old_id, %{water_column: 200})
      new = put_lineage(old, lineage(new_id, %{water_column: 100}))

      events = Tick.derive_events(old, new)
      assert Enum.filter(events, &(&1.type == :colonization)) == []
      assert Enum.any?(events, &(&1.type == :lineage_born))
    end
  end

  describe "phage_burst detection" do
    test "emits :phage_burst when a phase's phage_pool grows beyond the threshold" do
      lineage_id = Arkea.UUID.v4()
      old = state_with_phase_phage_pool(lineage_id, %{water_column: %{}})

      new =
        state_with_phase_phage_pool(lineage_id, %{
          water_column: %{"phage_a" => %{abundance: 200, decay_age: 0}}
        })

      events = Tick.derive_events(old, new)
      burst = Enum.filter(events, &(&1.type == :phage_burst))

      assert length(burst) == 1
      payload = hd(burst).payload
      assert payload.phase == "water_column"
      assert payload.virions_after == 200
      assert payload.virions_gained == 200
    end

    test "no :phage_burst when virion gain stays below the threshold" do
      lineage_id = Arkea.UUID.v4()
      old = state_with_phase_phage_pool(lineage_id, %{water_column: %{}})

      new =
        state_with_phase_phage_pool(lineage_id, %{
          water_column: %{"phage_a" => 5}
        })

      events = Tick.derive_events(old, new)
      assert Enum.filter(events, &(&1.type == :phage_burst)) == []
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers

  defp lineage(id, abundance_by_phase) do
    %Lineage{
      id: id,
      parent_id: nil,
      original_seed_id: nil,
      clade_ref_id: nil,
      created_at_tick: 0,
      abundance_by_phase: abundance_by_phase,
      genome: nil,
      delta: [],
      biomass: %{wall: 1.0, membrane: 1.0, dna: 1.0},
      dna_damage: 0.0
    }
  end

  defp state_with_lineage(lineage_id, abundance_by_phase) do
    phases = Enum.map(Map.keys(abundance_by_phase), &Phase.new/1)

    BiotopeState.new_from_opts(
      id: Arkea.UUID.v4(),
      archetype: :eutrophic_pond,
      x: 0.0,
      y: 0.0,
      phases: phases,
      dilution_rate: 0.05,
      tick_count: 0,
      lineages: [lineage(lineage_id, abundance_by_phase)]
    )
  end

  defp state_with_phase_phage_pool(lineage_id, phase_pools) do
    phases =
      Enum.map(phase_pools, fn {name, pool} ->
        %Phase{Phase.new(name) | phage_pool: pool}
      end)

    BiotopeState.new_from_opts(
      id: Arkea.UUID.v4(),
      archetype: :eutrophic_pond,
      x: 0.0,
      y: 0.0,
      phases: phases,
      dilution_rate: 0.05,
      tick_count: 0,
      lineages: [
        lineage(lineage_id, Map.new(phase_pools, fn {name, _} -> {name, 100} end))
      ]
    )
  end

  defp put_lineage(state, lineage), do: %{state | lineages: state.lineages ++ [lineage]}
end
