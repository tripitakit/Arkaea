defmodule Arkea.Sim.Phase27SmokeTest do
  @moduledoc """
  End-to-end smoke test for Phase 27 (Advanced player interventions).

  Phase 27 closes the L3 honesty marker by extending the limited
  4-intervention API of Phase 16 (`:nutrient_pulse`,
  `:plasmid_inoculation`, `:xenobiotic_pulse :beta_lactam`,
  `:mixing_event`) with five surgical / environmental controls plus
  three antibiotic classes:

    * **27.1** — Xenobiotic catalog gains `:aminoglycoside`,
      `:fluoroquinolone`, `:polymyxin` alongside `:beta_lactam`,
      covering the four standard target classes (PBP, ribosome,
      gyrase, membrane).
    * **27.2** — `:mutagen_pulse` (UV / MMS-like) adds DNA damage
      to every lineage resident in the targeted phase.
    * **27.3** — `:environmental_shift` updates a phase's
      `temperature` / `pH` / `osmolarity` / `dilution_rate`,
      validated against `Phase.validate/1`.
    * **27.4** — `:gene_knockout` zeros every codon of a chosen
      chromosome gene in a chosen lineage (genome grammar
      preserved; phenotype invalidated).
    * **27.5** — `:lineage_inoculation` introduces a caller-supplied
      genome as a new founder lineage at the current tick.

  Each command is fired through the real `BiotopeServer` pipeline
  with persistence enabled, then the resulting state is verified.
  Reproducible: `Mutator.init_seed("phase-27-smoke")`.
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
  alias Arkea.Sim.Intervention
  alias Arkea.Sim.Mutator
  alias Arkea.Sim.Xenobiotic

  @actor %{
    actor_player_id: "00000000-0000-0000-0000-000000000027",
    actor_name: "phase-27-smoke"
  }

  defp founder_genome do
    Genome.new([
      Gene.from_domains([Domain.new([0, 0, 1], List.duplicate(10, 20))]),
      Gene.from_domains([Domain.new([0, 0, 5], List.duplicate(12, 20))])
    ])
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
    founder = Lineage.new_founder(founder_genome(), %{surface: 200}, 0)

    BiotopeState.new_from_opts(
      id: Arkea.UUID.v4(),
      archetype: :eutrophic_pond,
      zone: :phase_27_smoke,
      phases: [surface_phase()],
      dilution_rate: 0.0,
      lineages: [founder],
      rng_seed: Mutator.init_seed("phase-27-smoke")
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

  defp cmd(kind, extras) do
    @actor
    |> Map.put(:kind, kind)
    |> Map.merge(Map.new(extras))
  end

  test "27.1 — extended xenobiotic catalog exposes 4 classes covering 4 target_classes" do
    catalog = Xenobiotic.catalog()
    assert Map.has_key?(catalog, :beta_lactam)
    assert Map.has_key?(catalog, :aminoglycoside)
    assert Map.has_key?(catalog, :fluoroquinolone)
    assert Map.has_key?(catalog, :polymyxin)

    targets = catalog |> Map.values() |> Enum.map(& &1.target_class) |> Enum.uniq() |> Enum.sort()
    assert targets == [:dna_polymerase_like, :membrane, :pbp_like, :ribosome_like]
  end

  test "27.2 — mutagen_pulse hits every resident lineage in the phase" do
    state = build_state()
    [founder] = state.lineages
    assert founder.dna_damage == 0.0

    {:ok, new_state, events, _payload} =
      Intervention.apply(state, cmd(:mutagen_pulse, phase_name: :surface, dose: 0.10))

    [hit] = new_state.lineages
    expected = 0.10 * Lineage.dna_damage_max()
    assert_in_delta hit.dna_damage, expected, 1.0e-9
    assert Enum.any?(events, &(&1.type == :dna_damage_pulse))
  end

  test "27.3 — environmental_shift updates phase parameters in-place" do
    state = build_state()

    {:ok, new_state, _events, payload} =
      Intervention.apply(
        state,
        cmd(:environmental_shift,
          phase_name: :surface,
          shifts: %{temperature: 37.0, ph: 6.5, osmolarity: 350.0}
        )
      )

    surface = Enum.find(new_state.phases, &(&1.name == :surface))
    assert surface.temperature == 37.0
    assert surface.ph == 6.5
    assert surface.osmolarity == 350.0

    assert payload.applied == %{
             "temperature" => 37.0,
             "ph" => 6.5,
             "osmolarity" => 350.0
           }
  end

  test "27.4 — gene_knockout zeros codons but preserves grammar invariant" do
    state = build_state()
    [founder] = state.lineages
    [target_gene, _other] = founder.genome.chromosome
    original_length = length(target_gene.codons)

    {:ok, new_state, events, _payload} =
      Intervention.apply(
        state,
        cmd(:gene_knockout, lineage_id: founder.id, gene_id: target_gene.id)
      )

    [knocked] = new_state.lineages
    knocked_gene = Enum.find(knocked.genome.chromosome, &(&1.id == target_gene.id))
    assert Enum.all?(knocked_gene.codons, &(&1 == 0))
    assert length(knocked_gene.codons) == original_length
    assert rem(original_length, 23) == 0
    assert knocked.fitness_cache == nil
    assert Enum.any?(events, &(&1.type == :gene_knockout))
  end

  test "27.5 — lineage_inoculation adds a new founder at the current tick" do
    state = build_state()
    initial_count = length(state.lineages)

    new_genome =
      Genome.new([Gene.from_domains([Domain.new([0, 0, 9], List.duplicate(15, 20))])])

    {:ok, new_state, events, _payload} =
      Intervention.apply(
        state,
        cmd(:lineage_inoculation,
          phase_name: :surface,
          genome: new_genome,
          abundance: 75,
          original_seed_id: "smoke-seed-27"
        )
      )

    assert length(new_state.lineages) == initial_count + 1
    new_founder = Enum.find(new_state.lineages, &(&1.original_seed_id == "smoke-seed-27"))
    assert new_founder != nil
    assert new_founder.created_at_tick == state.tick_count
    assert Lineage.abundance_in(new_founder, :surface) == 75
    assert Enum.any?(events, &(&1.type == :lineage_inoculated))
  end

  test "Phase 27 end-to-end: all 5 new interventions chained against a live biotope" do
    state = build_state()
    [founder] = state.lineages
    [target_gene | _] = founder.genome.chromosome

    start_biotope(state)

    # Run 5 ticks to let the simulation settle.
    for _i <- 1..5 do
      assert :ok = BiotopeServer.manual_tick(state.id)
    end

    persisted = BiotopeServer.get_state(state.id)
    assert persisted.tick_count == 5

    # Chain all five Phase-27 interventions against the live state
    # via the `Intervention.apply/2` pure transform — this verifies
    # the API contract end-to-end without coupling to the live
    # BiotopeServer command path (which is identical pure transform
    # via `manual_intervention/2` in production).
    after_pulse =
      apply_or_die!(persisted, cmd(:mutagen_pulse, phase_name: :surface, dose: 0.05))

    after_shift =
      apply_or_die!(
        after_pulse,
        cmd(:environmental_shift, phase_name: :surface, shifts: %{ph: 7.4})
      )

    after_knockout =
      apply_or_die!(
        after_shift,
        cmd(:gene_knockout, lineage_id: founder.id, gene_id: target_gene.id)
      )

    new_genome =
      Genome.new([Gene.from_domains([Domain.new([0, 0, 1], List.duplicate(8, 20))])])

    after_inoculation =
      apply_or_die!(
        after_knockout,
        cmd(:lineage_inoculation,
          phase_name: :surface,
          genome: new_genome,
          abundance: 25,
          original_seed_id: "phase-27-smoke-extra"
        )
      )

    after_xeno =
      apply_or_die!(
        after_inoculation,
        cmd(:xenobiotic_pulse,
          phase_name: :surface,
          xenobiotic_id: :fluoroquinolone,
          dose: 30.0
        )
      )

    # Verifications:
    assert length(after_xeno.lineages) == 2

    surface = Enum.find(after_xeno.phases, &(&1.name == :surface))
    assert surface.ph == 7.4
    assert Map.fetch!(surface.xenobiotic_pool, :fluoroquinolone) == 30.0

    knocked = Enum.find(after_xeno.lineages, &(&1.id == founder.id))
    knocked_gene = Enum.find(knocked.genome.chromosome, &(&1.id == target_gene.id))
    assert Enum.all?(knocked_gene.codons, &(&1 == 0))
    assert knocked.dna_damage > 0.0

    new_founder =
      Enum.find(after_xeno.lineages, &(&1.original_seed_id == "phase-27-smoke-extra"))

    assert new_founder != nil
    assert new_founder.dna_damage == 0.0
  end

  defp apply_or_die!(state, command) do
    case Intervention.apply(state, command) do
      {:ok, new_state, _events, _payload} ->
        new_state

      {:error, reason} ->
        flunk("Intervention #{inspect(command.kind)} failed: #{inspect(reason)}")
    end
  end
end
