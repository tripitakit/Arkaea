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

  describe "mutagen_pulse (Phase 27 / 27.2)" do
    test "adds dna_damage to every lineage resident in the targeted phase" do
      state = build_state(plasmids?: false)

      cmd =
        command(:mutagen_pulse, :surface)
        |> Map.put(:dose, 0.10)
        |> Map.put(:source, :uv)

      assert {:ok, new_state, events, payload} = Intervention.apply(state, cmd)

      [hit] = new_state.lineages
      # 0.10 × Lineage.dna_damage_max() (5.0) = 0.5 absolute increment.
      assert_in_delta hit.dna_damage, 0.5, 1.0e-9

      # Per-lineage audit alongside the umbrella :intervention.
      damage_events = Enum.filter(events, &(&1.type == :dna_damage_pulse))
      assert length(damage_events) == 1
      assert payload.affected_lineage_count == 1
    end

    test "lineages NOT resident in the targeted phase are unaffected" do
      state = build_state(plasmids?: false, phase: :sediment)
      cmd = command(:mutagen_pulse, :surface) |> Map.put(:dose, 0.10)

      assert {:ok, new_state, _events, payload} = Intervention.apply(state, cmd)

      assert payload.affected_lineage_count == 0
      [unchanged] = new_state.lineages
      assert unchanged.dna_damage == 0.0
    end

    test "damage is clamped at Lineage.dna_damage_max/0" do
      state = build_state(plasmids?: false)
      [base_lineage] = state.lineages
      pre_damaged = %{base_lineage | dna_damage: 4.8}
      state = %{state | lineages: [pre_damaged]}

      cmd = command(:mutagen_pulse, :surface) |> Map.put(:dose, 0.50)
      assert {:ok, new_state, _events, _} = Intervention.apply(state, cmd)

      [hit] = new_state.lineages
      assert hit.dna_damage == Lineage.dna_damage_max()
    end

    test "rejects an unknown phase" do
      state = build_state(plasmids?: false)
      cmd = command(:mutagen_pulse, :nonexistent)
      assert {:error, :invalid_phase} = Intervention.apply(state, cmd)
    end
  end

  describe "environmental_shift (Phase 27 / 27.3)" do
    test "applies the supplied {temperature, ph, osmolarity} delta to the phase" do
      state = build_state(plasmids?: false)

      cmd =
        command(:environmental_shift, :surface)
        |> Map.put(:shifts, %{temperature: 35.0, ph: 6.5})

      assert {:ok, new_state, _events, payload} = Intervention.apply(state, cmd)

      surface = Enum.find(new_state.phases, &(&1.name == :surface))
      assert surface.temperature == 35.0
      assert surface.ph == 6.5
      # Untouched keys preserve their original value.
      original_surface = Enum.find(state.phases, &(&1.name == :surface))
      assert surface.osmolarity == original_surface.osmolarity

      assert payload.applied == %{"temperature" => 35.0, "ph" => 6.5}
    end

    test "rejects shifts that drive the phase out of validation range" do
      state = build_state(plasmids?: false)

      cmd =
        command(:environmental_shift, :surface)
        |> Map.put(:shifts, %{temperature: 999.0})

      assert {:error, :temperature_out_of_range} = Intervention.apply(state, cmd)
    end

    test "rejects empty / no-op shifts" do
      state = build_state(plasmids?: false)
      cmd = command(:environmental_shift, :surface) |> Map.put(:shifts, %{})
      assert {:error, :no_environmental_change} = Intervention.apply(state, cmd)
    end
  end

  describe "gene_knockout (Phase 27 / 27.4)" do
    test "zeros every codon of the named chromosome gene" do
      state = build_state(plasmids?: false)
      [lineage] = state.lineages
      [gene] = lineage.genome.chromosome

      cmd =
        command(:gene_knockout, :surface)
        |> Map.put(:lineage_id, lineage.id)
        |> Map.put(:gene_id, gene.id)

      assert {:ok, new_state, events, payload} = Intervention.apply(state, cmd)

      knocked = Enum.find(new_state.lineages, &(&1.id == lineage.id))
      [knocked_gene] = knocked.genome.chromosome
      assert Enum.all?(knocked_gene.codons, &(&1 == 0))
      # Codon count is preserved (grammar invariant: multiples of 23).
      assert length(knocked_gene.codons) == length(gene.codons)
      # The knockout invalidates the phenotype cache.
      assert knocked.fitness_cache == nil

      assert payload.gene_id == gene.id
      assert Enum.any?(events, &(&1.type == :gene_knockout))
    end

    test "rejects an unknown gene id" do
      state = build_state(plasmids?: false)
      [lineage] = state.lineages

      cmd =
        command(:gene_knockout, :surface)
        |> Map.put(:lineage_id, lineage.id)
        |> Map.put(:gene_id, "no-such-gene")

      assert {:error, :unknown_gene} = Intervention.apply(state, cmd)
    end

    test "rejects an unknown lineage id" do
      state = build_state(plasmids?: false)

      cmd =
        command(:gene_knockout, :surface)
        |> Map.put(:lineage_id, "no-such-lineage")
        |> Map.put(:gene_id, "irrelevant")

      assert {:error, :unknown_lineage} = Intervention.apply(state, cmd)
    end
  end

  describe "lineage_inoculation (Phase 27 / 27.5)" do
    test "adds the supplied genome as a new founder at the current tick" do
      state = build_state(plasmids?: false)
      original_count = length(state.lineages)

      new_genome =
        Genome.new([Gene.from_domains([Domain.new([0, 0, 1], List.duplicate(15, 20))])])

      cmd =
        command(:lineage_inoculation, :surface)
        |> Map.put(:genome, new_genome)
        |> Map.put(:abundance, 50)
        |> Map.put(:original_seed_id, "test-seed-42")

      assert {:ok, new_state, events, payload} = Intervention.apply(state, cmd)

      assert length(new_state.lineages) == original_count + 1
      [founder | _rest] = new_state.lineages
      # Lineage was inoculated AT the current tick (not 0).
      assert founder.created_at_tick == state.tick_count
      assert founder.original_seed_id == "test-seed-42"
      assert Lineage.abundance_in(founder, :surface) == 50

      assert payload.lineage_id == founder.id
      assert Enum.any?(events, &(&1.type == :lineage_inoculated))
    end

    test "rejects a non-positive abundance" do
      state = build_state(plasmids?: false)

      new_genome =
        Genome.new([Gene.from_domains([Domain.new([0, 0, 1], List.duplicate(10, 20))])])

      cmd =
        command(:lineage_inoculation, :surface)
        |> Map.put(:genome, new_genome)
        |> Map.put(:abundance, 0)

      assert {:error, :invalid_abundance} = Intervention.apply(state, cmd)
    end

    test "rejects a non-Genome payload" do
      state = build_state(plasmids?: false)

      cmd =
        command(:lineage_inoculation, :surface)
        |> Map.put(:genome, %{not: :a_genome})
        |> Map.put(:abundance, 10)

      assert {:error, :invalid_genome} = Intervention.apply(state, cmd)
    end
  end

  describe "xenobiotic_pulse with Phase-27 expanded catalog" do
    test "aminoglycoside (ribosome target) accepted by xenobiotic_pulse" do
      state = build_state(plasmids?: false)

      cmd =
        command(:xenobiotic_pulse, :surface)
        |> Map.put(:xenobiotic_id, :aminoglycoside)
        |> Map.put(:dose, 25.0)

      assert {:ok, new_state, _events, payload} = Intervention.apply(state, cmd)
      assert payload.xenobiotic_id == "aminoglycoside"

      surface = Enum.find(new_state.phases, &(&1.name == :surface))
      assert Map.fetch!(surface.xenobiotic_pool, :aminoglycoside) == 25.0
    end

    test "fluoroquinolone (mutagen mode, dna_polymerase target) accepted" do
      state = build_state(plasmids?: false)

      cmd =
        command(:xenobiotic_pulse, :surface)
        |> Map.put(:xenobiotic_id, :fluoroquinolone)

      assert {:ok, _new_state, _events, payload} = Intervention.apply(state, cmd)
      assert payload.xenobiotic_id == "fluoroquinolone"
    end

    test "polymyxin (membrane target) accepted" do
      state = build_state(plasmids?: false)

      cmd =
        command(:xenobiotic_pulse, :surface)
        |> Map.put(:xenobiotic_id, :polymyxin)

      assert {:ok, _new_state, _events, payload} = Intervention.apply(state, cmd)
      assert payload.xenobiotic_id == "polymyxin"
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
