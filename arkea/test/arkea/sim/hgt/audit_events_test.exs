defmodule Arkea.Sim.HGT.AuditEventsTest do
  @moduledoc """
  Audit-event emission across HGT channels (Sub-task 1.2 — remediation P0).

  Each successful HGT uptake/integration must emit a typed event into
  the `BiotopeState.pending_events` buffer so downstream consumers
  (audit log, world view, phylogeny) can observe inheritance flows.

  Sub-task 1.2 covers natural transformation only. Conjugation, phage
  infection and bacteriocin events follow in later sub-tasks.

  This test asserts on the events RETURNED FROM the channel function
  directly (not on `Tick.tick/1`'s output) — wiring into
  `BiotopeState.pending_events` is exercised in the simpler
  pending_events foundation tests; the *step → state.pending_events*
  bridge is verified by the broader sim suite passing after the
  refactor.
  """

  use ExUnit.Case, async: true

  alias Arkea.Ecology.Lineage
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Sim.HGT.Channel.Transformation
  alias Arkea.Sim.HGT.DnaFragment
  alias Arkea.Sim.Mutator

  # ---------------------------------------------------------------------------
  # Helpers (adapted from arkea/test/arkea/sim/hgt/transformation_test.exs;
  # inlined here to avoid introducing a Factories module).

  @param_codons List.duplicate(10, 20)

  defp catalytic_domain, do: Domain.new([0, 0, 1], @param_codons)
  defp transmembrane_domain, do: Domain.new([0, 0, 2], @param_codons)
  defp channel_domain, do: Domain.new([0, 0, 3], @param_codons)
  defp ligand_sensor_domain, do: Domain.new([0, 0, 7], @param_codons)

  defp competent_genome do
    Genome.new([
      Gene.from_domains([catalytic_domain()]),
      Gene.from_domains([channel_domain()]),
      Gene.from_domains([transmembrane_domain()]),
      Gene.from_domains([ligand_sensor_domain()])
    ])
  end

  defp donor_chromosome do
    [
      Gene.from_domains([catalytic_domain()]),
      Gene.from_domains([channel_domain()]),
      Gene.from_domains([transmembrane_domain()]),
      Gene.from_domains([ligand_sensor_domain()])
    ]
  end

  defp founder(genome, abundance) do
    Lineage.new_founder(genome, %{surface: abundance}, 0)
  end

  defp surface_phase do
    Arkea.Ecology.Phase.new(:surface,
      temperature: 25.0,
      ph: 7.0,
      osmolarity: 300.0,
      dilution_rate: 0.0
    )
  end

  defp dna_fragment(donor_genes, opts) do
    DnaFragment.new(
      id: Keyword.get(opts, :id, Arkea.UUID.v4()),
      genes: donor_genes,
      abundance: Keyword.get(opts, :abundance, 5_000),
      methylation_profile: Keyword.get(opts, :methylation_profile, []),
      origin_lineage_id: Keyword.get(opts, :origin_lineage_id, "donor-lineage"),
      created_at_tick: 0
    )
  end

  describe "transformation_event emission" do
    test "successful uptake produces a :transformation_event with origin/recipient/tick" do
      # Build a competent recipient and a saturating donor fragment so
      # uptake fires within a handful of rolls under any RNG seed.
      recipient = founder(competent_genome(), 200)

      fragment =
        dna_fragment(donor_chromosome(),
          abundance: 5_000,
          origin_lineage_id: "donor-lineage-xyz"
        )

      phase = Arkea.Ecology.Phase.add_dna_fragment(surface_phase(), fragment)
      rng = Mutator.init_seed("transformation-event-emission")
      tick = 42

      # Iterate until at least one transformation fires (matches the
      # pattern used by the existing transformation_test for high-uptake
      # scenarios). Each call returns a 5-tuple with events in slot 4.
      {_ls, _ph, children, events, _rng_out} =
        Enum.reduce(1..20, {[recipient], phase, [], [], rng}, fn _i,
                                                                 {ls, ph, ch_acc, ev_acc, acc_rng} ->
          {ls_out, ph_out, new_children, new_events, rng_out} =
            Transformation.step(ls, ph, tick, acc_rng)

          {ls_out, ph_out, ch_acc ++ new_children, ev_acc ++ new_events, rng_out}
        end)

      # Sanity: at least one transformant child fired (otherwise the
      # event assertion would pass vacuously for the wrong reason).
      assert length(children) > 0

      # Every successful uptake must have produced exactly one event.
      assert length(events) == length(children)

      assert Enum.all?(events, fn e ->
               e.type == :transformation_event and
                 e.tick == tick and
                 is_binary(e.recipient_lineage_id) and
                 e.origin_lineage_id == "donor-lineage-xyz" and
                 is_integer(e.gene_index) and e.gene_index >= 0
             end)
    end
  end
end
