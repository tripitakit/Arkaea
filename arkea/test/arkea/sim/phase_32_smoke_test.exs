defmodule Arkea.Sim.Phase32SmokeTest do
  @moduledoc """
  End-to-end smoke test for Phase 32 — L1.7 refinements
  (codon-complement palindromes + kcat-modulated methylation)
  and orchestration (`:scheduled_dosing` intervention).

  ## L1.7 refinements (32a)

  Phase 31 detected only *exact* palindromes (sequence equals its
  plain reversal) and methylase sites defaulted to *full*
  per-position coverage regardless of the methylase's catalytic
  quality. Phase 32 closes both gaps:

    * **Codon-complement involution** — `c → 19 - c` plays the
      role of the canonical Watson-Crick base-pair complement.
      `RecognitionSite.palindrome_kind/1` now returns
      `:exact | :complement | :none`; `classify_type/2` tags
      complement palindromes as Type II (textbook EcoRI shape).
    * **kcat-modulated partial methylation** —
      `RecognitionSite.scale_methylation_to_kcat/2` shrinks
      `methylated_positions` proportionally to the methylase's
      `:catalytic_site.kcat` (range `0..10`). Low-kcat methylase
      → only the leading 5'-end positions methylated → restriction
      enzymes can still cleave at the trailing positions.
    * `Phenotype.rm_profiles_detailed/1` automatically applies the
      kcat scaling when constructing methylase sites.

  ## Orchestration (32b)

  The Phase-27 `Intervention.apply/2` API runs commands
  immediately. Phase 32 adds a scheduling layer:

    * `Arkea.Sim.Intervention.Scheduler.schedule/1` enqueues an
      Oban job in the `:scheduled_dosing` queue.
    * `Arkea.Sim.Intervention.ScheduledDosingWorker.perform/1`
      polls the target biotope's tick and fires the
      intervention via `BiotopeServer.apply_intervention/2` once
      the due-tick is reached.

  Reproducible: pure functional helpers + Oban manual mode.
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
  alias Arkea.Sim.HGT.RecognitionSite
  alias Arkea.Sim.Intervention.ScheduledDosingWorker
  alias Arkea.Sim.Intervention.Scheduler
  alias Arkea.Sim.Mutator
  alias Arkea.Sim.Phenotype

  describe "32a — L1.7 refinements" do
    test "complement palindrome (c → 19 - c) classifies as Type II" do
      # Reverse-complement palindrome: pattern equals its reverse-c-complement.
      pattern = [3, 17, 9, 10, 2, 16]
      assert RecognitionSite.palindrome_kind(pattern) == :complement

      site = RecognitionSite.new("3,17,9,10", pattern, :restriction)
      assert site.type == :type_ii
    end

    test "kcat-modulated methylation: high-kcat methylase covers more positions than low-kcat" do
      pattern = List.duplicate(10, 20)
      base = RecognitionSite.new("10,10,10,10", pattern, :methylation)

      high = RecognitionSite.scale_methylation_to_kcat(base, 9.0)
      low = RecognitionSite.scale_methylation_to_kcat(base, 2.0)

      high_count = MapSet.size(high.methylated_positions)
      low_count = MapSet.size(low.methylated_positions)

      assert high_count >= 18
      assert low_count == 4
      assert high_count > low_count
    end

    test "Phenotype.rm_profiles_detailed/1 applies kcat scaling automatically" do
      # Two methylase genes with the same recognition pattern but
      # different kcat-driving param codons → different
      # `methylated_positions` coverage.
      methylase_high =
        Gene.from_domains([
          Domain.new([0, 0, 5], List.duplicate(10, 20)),
          Domain.new([0, 0, 1], [3, 0, 0] ++ List.duplicate(19, 17))
        ])

      methylase_low =
        Gene.from_domains([
          Domain.new([0, 0, 5], List.duplicate(10, 20)),
          Domain.new([0, 0, 1], [3, 0, 0] ++ List.duplicate(2, 17))
        ])

      %{methylation_sites: [m_high | _]} =
        Phenotype.rm_profiles_detailed(Genome.new([methylase_high]))

      %{methylation_sites: [m_low | _]} =
        Phenotype.rm_profiles_detailed(Genome.new([methylase_low]))

      assert MapSet.size(m_high.methylated_positions) >
               MapSet.size(m_low.methylated_positions)
    end
  end

  describe "32b — orchestration: scheduled dosing" do
    setup do
      # Oban testing in :manual mode means jobs aren't auto-executed;
      # the test calls `perform_job/2` explicitly.
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

    defp simple_genome do
      Genome.new([Gene.from_domains([Domain.new([0, 0, 1], List.duplicate(10, 20))])])
    end

    defp surface_phase do
      Phase.new(:surface,
        temperature: 25.0,
        ph: 7.0,
        osmolarity: 300.0,
        dilution_rate: 0.0
      )
      |> Phase.update_metabolite(:glucose, 200.0)
    end

    defp build_state do
      founder = Lineage.new_founder(simple_genome(), %{surface: 100}, 0)

      BiotopeState.new_from_opts(
        id: Arkea.UUID.v4(),
        archetype: :eutrophic_pond,
        zone: :phase_32_smoke,
        phases: [surface_phase()],
        dilution_rate: 0.0,
        lineages: [founder],
        rng_seed: Mutator.init_seed("phase-32-smoke")
      )
    end

    defp start_biotope(state) do
      {:ok, pid} = BiotopeSupervisor.start_biotope(state)
      on_exit(fn -> stop_biotope(state.id) end)
      pid
    end

    defp stop_biotope(id) do
      case Registry.lookup(Arkea.Sim.Registry, {:biotope, id}) do
        [{pid, _}] when is_pid(pid) ->
          if Process.alive?(pid) do
            DynamicSupervisor.terminate_child(BiotopeSupervisor, pid)
          end

        _ ->
          :ok
      end

      :ok
    end

    test "Scheduler.schedule/1 enqueues a job and rejects malformed input" do
      assert {:ok, %Oban.Job{} = job} =
               Scheduler.schedule(%{
                 biotope_id: "test-biotope-id",
                 due_tick: 5,
                 command: %{
                   kind: :nutrient_pulse,
                   actor_player_id: "00000000-0000-0000-0000-000000000032",
                   actor_name: "tester",
                   phase_name: :surface
                 }
               })

      assert job.queue == "scheduled_dosing"
      assert job.args["biotope_id"] == "test-biotope-id"
      assert job.args["due_tick"] == 5

      # Malformed input → validation error.
      assert {:error, :invalid_command_kind} =
               Scheduler.schedule(%{
                 biotope_id: "x",
                 due_tick: 0,
                 command: %{actor_player_id: "x", actor_name: "x"}
               })
    end

    test "stringify_command/1 + atomize_command/1 round-trip" do
      command = %{
        kind: :xenobiotic_pulse,
        actor_player_id: "actor-id",
        actor_name: "tester",
        phase_name: :surface,
        xenobiotic_id: :beta_lactam,
        dose: 25.0,
        scope: :phase
      }

      json_safe = Scheduler.stringify_command(command)
      restored = Scheduler.atomize_command(json_safe)

      assert restored == command
    end

    test "Worker fires the intervention once due_tick is reached" do
      state = build_state()
      start_biotope(state)

      # Drive the biotope to tick 3.
      for _ <- 1..3, do: assert(:ok = BiotopeServer.manual_tick(state.id))

      command = %{
        kind: :nutrient_pulse,
        actor_player_id: "00000000-0000-0000-0000-000000000032",
        actor_name: "tester",
        phase_name: :surface
      }

      args = %{
        "biotope_id" => state.id,
        "due_tick" => 2,
        "command" => Scheduler.stringify_command(command)
      }

      # The biotope's tick_count (3) ≥ due_tick (2) → worker fires.
      assert :ok = perform_job(ScheduledDosingWorker, args)

      # Confirm the intervention took effect: the surface phase's
      # glucose pool grew by the nutrient_pulse default amount.
      persisted = BiotopeServer.get_state(state.id)
      surface = Enum.find(persisted.phases, &(&1.name == :surface))
      assert surface.metabolite_pool[:glucose] > 200.0
    end

    test "Worker snoozes when biotope tick is still below due_tick" do
      state = build_state()
      start_biotope(state)
      # Biotope at tick 0; schedule for tick 50.

      command = %{
        kind: :nutrient_pulse,
        actor_player_id: "00000000-0000-0000-0000-000000000032",
        actor_name: "tester",
        phase_name: :surface
      }

      args = %{
        "biotope_id" => state.id,
        "due_tick" => 50,
        "command" => Scheduler.stringify_command(command)
      }

      assert {:snooze, snooze_seconds} = perform_job(ScheduledDosingWorker, args)
      assert is_integer(snooze_seconds) and snooze_seconds > 0
    end

    test "Worker cancels when target biotope is no longer running" do
      command = %{
        kind: :nutrient_pulse,
        actor_player_id: "00000000-0000-0000-0000-000000000032",
        actor_name: "tester",
        phase_name: :surface
      }

      args = %{
        "biotope_id" => "no-such-biotope-id",
        "due_tick" => 1,
        "command" => Scheduler.stringify_command(command)
      }

      assert {:cancel, :biotope_not_running} = perform_job(ScheduledDosingWorker, args)
    end
  end
end
