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
  alias Arkea.Sim.HGT.Phage
  alias Arkea.Sim.HGT.Virion
  alias Arkea.Sim.Mutator

  # ---------------------------------------------------------------------------
  # Helpers (adapted from arkea/test/arkea/sim/hgt/transformation_test.exs;
  # inlined here to avoid introducing a Factories module).

  @param_codons List.duplicate(10, 20)

  defp catalytic_domain, do: Domain.new([0, 0, 1], @param_codons)
  defp transmembrane_domain, do: Domain.new([0, 0, 2], @param_codons)
  defp channel_domain, do: Domain.new([0, 0, 3], @param_codons)
  defp ligand_sensor_domain, do: Domain.new([0, 0, 7], @param_codons)
  defp dna_binding_domain, do: Domain.new([0, 0, 5], @param_codons)
  defp structural_domain, do: Domain.new([0, 0, 8], @param_codons)
  # Phase 20: surface_tag(first_codon=10, rem(10,3)=1) → :phage_receptor.
  defp surface_domain, do: Domain.new([0, 0, 9], @param_codons)

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

  # ---------------------------------------------------------------------------
  # Phage helpers (Sub-task 1.3).

  defp prophage_cassette do
    # A cassette with a structural_fold (capsid) + surface_tag (signature
    # source). The cassette also encodes the prophage's repressor strength
    # via dna_binding affinity.
    [Gene.from_domains([structural_domain(), surface_domain()])]
  end

  # Recipient with a `:phage_receptor` surface_tag, no restriction enzymes.
  # `surface_domain/0` has `tag_class: :phage_receptor`. Without a co-located
  # `:dna_binding` partner the catalytic_site is not interpreted as a
  # restriction enzyme, so `restriction_profile` is empty → R-M trivially
  # passes.
  defp receptor_only_genome do
    Genome.new([
      Gene.from_domains([catalytic_domain()]),
      Gene.from_domains([surface_domain()])
    ])
  end

  # Recipient with the same `:phage_receptor` AND a real restriction enzyme:
  # a gene carrying co-located `:dna_binding` + `:catalytic_site(:hydrolysis)`
  # domains. The catalytic_site `signal_key` ("10,10,10,10" with the default
  # parameter codons) becomes a vulnerable restriction site whenever the
  # virion's methylation_profile does NOT cover it.
  defp restriction_enzyme_genome do
    Genome.new([
      Gene.from_domains([dna_binding_domain(), catalytic_domain()]),
      Gene.from_domains([surface_domain()])
    ])
  end

  defp phage_virion(opts) do
    Virion.new(
      id: Keyword.get(opts, :id, Arkea.UUID.v4()),
      genes: Keyword.get(opts, :genes, hd(prophage_cassette()) |> List.wrap()),
      abundance: Keyword.get(opts, :abundance, 5_000),
      surface_signature: Keyword.get(opts, :surface_signature, "10,10,10,10"),
      methylation_profile: Keyword.get(opts, :methylation_profile, []),
      origin_lineage_id: Keyword.get(opts, :origin_lineage_id, "donor-lineage"),
      created_at_tick: 0,
      payload_kind: :phage
    )
  end

  describe "phage_infection emission" do
    test "successful infection emits :phage_infection event with mode" do
      recipient = founder(receptor_only_genome(), 200)

      virion =
        phage_virion(
          abundance: 5_000,
          methylation_profile: [],
          origin_lineage_id: "phage-donor-abc"
        )

      phase = Arkea.Ecology.Phase.add_virion(surface_phase(), virion)
      rng = Mutator.init_seed("phage-infection-event-emission")
      tick = 100

      # Iterate until at least one infection fires. Phage.step/4 must
      # return a 5-tuple with events in slot 4 (Sub-task 1.3).
      {_ls, _ph, children, events, _rng_out} =
        Enum.reduce(1..50, {[recipient], phase, [], [], rng}, fn _i,
                                                                  {ls, ph, ch_acc, ev_acc,
                                                                   acc_rng} ->
          {ls_out, ph_out, new_children, new_events, rng_out} =
            Phage.step(ls, ph, tick, acc_rng)

          {ls_out, ph_out, ch_acc ++ new_children, ev_acc ++ new_events, rng_out}
        end)

      infections = Enum.filter(events, &(&1.type == :phage_infection))

      # Sanity: at least one infection occurred (children list reflects
      # lysogenic integrations; lytic infections do not produce children
      # but DO emit events).
      assert length(infections) >= 1,
             "Expected at least one :phage_infection event over 50 ticks; got #{inspect(events)}"

      assert Enum.all?(infections, fn e ->
               e.mode in [:lytic, :lysogenic] and
                 is_binary(e.recipient_lineage_id) and
                 e.recipient_lineage_id == recipient.id and
                 e.tick == tick and
                 (Map.has_key?(e, :virion_id) or Map.has_key?(e, :origin_lineage_id))
             end)

      # Successful lysogenic integrations should match by count: every
      # lysogenic event corresponds to exactly one new child lineage.
      lysogenic_events = Enum.filter(infections, &(&1.mode == :lysogenic))
      assert length(lysogenic_events) == length(children)
    end
  end

  describe "rm_digestion emission" do
    test "incompatible methylation triggers :rm_digestion event" do
      recipient = founder(restriction_enzyme_genome(), 200)

      # Virion with a methylation profile that does NOT cover the
      # recipient's restriction site ("10,10,10,10"). R-M will roll
      # digestion with @cleave_p = 0.95.
      virion =
        phage_virion(
          abundance: 5_000,
          methylation_profile: [],
          origin_lineage_id: "phage-donor-rm"
        )

      phase = Arkea.Ecology.Phase.add_virion(surface_phase(), virion)
      rng = Mutator.init_seed("phage-rm-digestion-event")
      tick = 200

      {_ls, _ph, _children, events, _rng_out} =
        Enum.reduce(1..50, {[recipient], phase, [], [], rng}, fn _i,
                                                                  {ls, ph, ch_acc, ev_acc,
                                                                   acc_rng} ->
          {ls_out, ph_out, new_children, new_events, rng_out} =
            Phage.step(ls, ph, tick, acc_rng)

          {ls_out, ph_out, ch_acc ++ new_children, ev_acc ++ new_events, rng_out}
        end)

      digestions = Enum.filter(events, &(&1.type == :rm_digestion))

      assert length(digestions) >= 1,
             "Expected at least one :rm_digestion event over 50 ticks; got #{inspect(events)}"

      assert Enum.all?(digestions, fn e ->
               is_binary(e.recipient_lineage_id) and
                 e.recipient_lineage_id == recipient.id and
                 e.tick == tick and
                 (Map.has_key?(e, :virion_id) or Map.has_key?(e, :origin_lineage_id))
             end)
    end
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
