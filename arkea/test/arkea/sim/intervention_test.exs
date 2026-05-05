defmodule Arkea.Sim.InterventionTest do
  use ExUnit.Case, async: true

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Intervention

  describe "plasmid_inoculation" do
    test "succeeds when the focused phase has a lineage with a genome (no plasmids yet)" do
      state = build_state(plasmids?: false)

      assert {:ok, new_state, _events, payload} =
               Intervention.apply(state, command(:plasmid_inoculation, :surface))

      assert payload.host_lineage_id != nil
      # New child appended to the lineages list.
      assert length(new_state.lineages) == length(state.lineages) + 1
    end

    test "succeeds even when every resident lineage already carries a plasmid (pile-up allowed)" do
      state = build_state(plasmids?: true)

      assert {:ok, _new_state, _events, payload} =
               Intervention.apply(state, command(:plasmid_inoculation, :surface))

      assert payload.host_lineage_id != nil
    end

    test "returns :no_lineage_host when the focused phase has zero abundance" do
      # Lineage exists but has no cells in :surface — only in :sediment.
      state = build_state(plasmids?: false, phase: :sediment)

      assert {:error, :no_lineage_host} =
               Intervention.apply(state, command(:plasmid_inoculation, :surface))
    end
  end

  defp command(kind, phase_name) do
    %{
      kind: kind,
      phase_name: phase_name,
      actor_player_id: "11111111-1111-1111-1111-111111111111",
      actor_name: "test"
    }
  end

  defp build_state(opts) do
    plasmids? = Keyword.get(opts, :plasmids?, false)
    phase = Keyword.get(opts, :phase, :surface)

    base_genome =
      Genome.new([Gene.from_domains([Domain.new([0, 0, 0], List.duplicate(5, 20))])])

    genome =
      if plasmids? do
        plasmid_gene = Gene.from_domains([Domain.new([0, 0, 2], List.duplicate(7, 20))])
        Genome.add_plasmid(base_genome, [plasmid_gene])
      else
        base_genome
      end

    lineage = %Lineage{
      id: Arkea.UUID.v4(),
      parent_id: nil,
      original_seed_id: nil,
      clade_ref_id: nil,
      created_at_tick: 0,
      abundance_by_phase: %{phase => 200},
      genome: genome,
      delta: [],
      biomass: %{wall: 1.0, membrane: 1.0, dna: 1.0},
      dna_damage: 0.0
    }

    BiotopeState.new_from_opts(
      id: Arkea.UUID.v4(),
      archetype: :eutrophic_pond,
      x: 0.0,
      y: 0.0,
      phases: [Phase.new(:surface), Phase.new(:sediment)],
      dilution_rate: 0.05,
      lineages: [lineage]
    )
  end
end
