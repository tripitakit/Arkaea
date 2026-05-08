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
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.HGT
  alias Arkea.Sim.HGT.Channel.Transformation
  alias Arkea.Sim.HGT.DnaFragment
  alias Arkea.Sim.HGT.Phage
  alias Arkea.Sim.HGT.Virion
  alias Arkea.Sim.Mutator
  alias Arkea.Sim.Tick

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
                                                                 {ls, ph, ch_acc, ev_acc, acc_rng} ->
          {ls_out, ph_out, new_children, new_events, rng_out} =
            Phage.step(ls, ph, tick, acc_rng)

          {ls_out, ph_out, ch_acc ++ new_children, ev_acc ++ new_events, rng_out}
        end)

      infections = Enum.filter(events, &(&1.type == :phage_infection))

      # Sanity: at least one infection occurred (children list reflects
      # lysogenic integrations; lytic infections do not produce children
      # but DO emit events).
      assert not Enum.empty?(infections),
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
                                                                 {ls, ph, ch_acc, ev_acc, acc_rng} ->
          {ls_out, ph_out, new_children, new_events, rng_out} =
            Phage.step(ls, ph, tick, acc_rng)

          {ls_out, ph_out, ch_acc ++ new_children, ev_acc ++ new_events, rng_out}
        end)

      digestions = Enum.filter(events, &(&1.type == :rm_digestion))

      assert not Enum.empty?(digestions),
             "Expected at least one :rm_digestion event over 50 ticks; got #{inspect(events)}"

      assert Enum.all?(digestions, fn e ->
               is_binary(e.recipient_lineage_id) and
                 e.recipient_lineage_id == recipient.id and
                 e.tick == tick and
                 (Map.has_key?(e, :virion_id) or Map.has_key?(e, :origin_lineage_id))
             end)
    end
  end

  # ---------------------------------------------------------------------------
  # Sub-task 1.4 — HGT.step (conjugation) channel-aware events.

  defp tm_domain, do: Domain.new([0, 0, 2], @param_codons)

  defp conjugative_plasmid_genes do
    # 3 transmembrane_anchor domains → conjugation_strength = 3
    [Gene.from_domains([tm_domain(), tm_domain(), tm_domain()])]
  end

  defp donor_with_conjugative do
    plasmid = conjugative_plasmid_genes()
    genome = Genome.new([Gene.from_domains([catalytic_domain()])], plasmids: [plasmid])
    Lineage.new_founder(genome, %{surface: 200}, 0)
  end

  defp plain_recipient do
    Lineage.new_founder(
      Genome.new([Gene.from_domains([catalytic_domain()])]),
      %{surface: 200},
      0
    )
  end

  describe "hgt_transfer event from conjugation" do
    test "successful conjugation emits :hgt_transfer with channel: :conjugation" do
      donor = donor_with_conjugative()
      recipient = plain_recipient()
      lineages = [donor, recipient]
      phase = surface_phase()

      rng = Mutator.init_seed("hgt-conjugation-event-emission")

      # Run HGT.step many times to overcome the low per-call probability
      # (~0.00375). Lineages are NOT mutated between calls so populations
      # stay stable; we only need at least one event to fire.
      {events, _rng_out} =
        Enum.reduce(1..2_000, {[], rng}, fn tick, {acc_events, acc_rng} ->
          {_lineages_out, _phase_out, _children, events, rng_out} =
            HGT.step(lineages, phase, tick, acc_rng)

          {acc_events ++ events, rng_out}
        end)

      transfers = Enum.filter(events, &(&1.type == :hgt_transfer))

      assert not Enum.empty?(transfers),
             "Expected at least one :hgt_transfer event over 2000 HGT.step calls"

      assert Enum.all?(transfers, fn e ->
               e.channel == :conjugation and
                 is_binary(e.donor_lineage_id) and
                 is_binary(e.recipient_lineage_id) and
                 is_integer(e.plasmid_inc_group) and
                 is_integer(e.tick) and e.tick >= 1
             end)

      # The donor in this scenario is the conjugative-plasmid carrier.
      assert Enum.all?(transfers, &(&1.donor_lineage_id == donor.id))
      assert Enum.all?(transfers, &(&1.recipient_lineage_id == recipient.id))
    end
  end

  describe "plasmid_displaced event from inc-group conflict" do
    test "incompatible inc_group plasmid arrival emits :plasmid_displaced" do
      # Build a recipient that already carries a plasmid with the SAME
      # inc_group as the donor's. The current biology suppresses the
      # transfer (recipient_has_plasmid?/2 short-circuit), but Sub-task 1.4
      # surfaces the inc-group conflict as a :plasmid_displaced audit event
      # so downstream consumers see the displacement attempt.
      plasmid_genes = conjugative_plasmid_genes()
      plasmid = Genome.normalize_plasmid(plasmid_genes)

      donor_genome = Genome.new([Gene.from_domains([catalytic_domain()])], plasmids: [plasmid])
      donor = Lineage.new_founder(donor_genome, %{surface: 200}, 0)

      # Recipient has a plasmid with the SAME inc_group (we reuse the same
      # genes so normalize_plasmid yields the same hash).
      recipient_genome =
        Genome.new([Gene.from_domains([catalytic_domain()])], plasmids: [plasmid])

      recipient = Lineage.new_founder(recipient_genome, %{surface: 200}, 0)

      lineages = [donor, recipient]
      phase = surface_phase()
      rng = Mutator.init_seed("hgt-inc-group-conflict")

      {events, _rng_out} =
        Enum.reduce(1..2_000, {[], rng}, fn tick, {acc_events, acc_rng} ->
          {_lineages_out, _phase_out, _children, events, rng_out} =
            HGT.step(lineages, phase, tick, acc_rng)

          {acc_events ++ events, rng_out}
        end)

      displacements = Enum.filter(events, &(&1.type == :plasmid_displaced))

      assert not Enum.empty?(displacements),
             "Expected at least one :plasmid_displaced event over 2000 HGT.step calls"

      assert Enum.all?(displacements, fn e ->
               is_binary(e.recipient_lineage_id) and
                 is_binary(e.new_donor_lineage_id) and
                 is_integer(e.displaced_inc_group) and
                 is_integer(e.tick)
             end)
    end
  end

  describe "transduction_event from transducing virion integration" do
    test "successful transducing virion integration emits :transduction_event" do
      # Build a transducing virion directly and feed it to Phage.step/4.
      # The recipient has a 1-gene chromosome and a :phage_receptor surface
      # tag (surface_domain/0) so receptor matching passes; no restriction
      # enzymes so R-M passes; high virion abundance to make the infection
      # roll fire within a few iterations.
      donor_gene = Gene.from_domains([structural_domain(), surface_domain()])

      recipient =
        founder(
          Genome.new([
            Gene.from_domains([catalytic_domain()]),
            Gene.from_domains([surface_domain()])
          ]),
          200
        )

      transducing_virion =
        Virion.new(
          id: Arkea.UUID.v4(),
          genes: [donor_gene],
          abundance: 5_000,
          surface_signature: nil,
          methylation_profile: [],
          origin_lineage_id: "transduction-donor-xyz",
          created_at_tick: 0,
          payload_kind: :generalized_transduction
        )

      phase = Phase.add_virion(surface_phase(), transducing_virion)
      rng = Mutator.init_seed("phage-transduction-event-emission")
      tick = 500

      {_ls, _ph, _children, events, _rng_out} =
        Enum.reduce(1..30, {[recipient], phase, [], [], rng}, fn _i,
                                                                 {ls, ph, ch_acc, ev_acc, acc_rng} ->
          {ls_out, ph_out, new_children, new_events, rng_out} =
            Phage.step(ls, ph, tick, acc_rng)

          {ls_out, ph_out, ch_acc ++ new_children, ev_acc ++ new_events, rng_out}
        end)

      transductions = Enum.filter(events, &(&1.type == :transduction_event))

      assert not Enum.empty?(transductions),
             "Expected at least one :transduction_event over 30 Phage.step calls"

      assert Enum.all?(transductions, fn e ->
               e.payload_kind in [:generalized, :specialized] and
                 is_binary(e.recipient_lineage_id) and
                 e.recipient_lineage_id == recipient.id and
                 e.donor_lineage_id == "transduction-donor-xyz" and
                 e.tick == tick
             end)
    end
  end

  describe "Tick.tick/1 exposes pending_events in outward result" do
    defp tick_state_with_active_hgt do
      donor = donor_with_conjugative()
      recipient = plain_recipient()

      BiotopeState.new_from_opts(
        id: "audit-events-tick-test",
        archetype: :hot_spring,
        phases: [surface_phase()],
        dilution_rate: 0.0,
        lineages: [donor, recipient],
        rng_seed: Mutator.init_seed("audit-events-tick-test")
      )
    end

    test "events accumulated by step_hgt and step_phage_infection appear in tick output" do
      # Drive multiple ticks until at least one channel-emitted event surfaces
      # in the tick's outward events list. Per-tick conjugation probability is
      # ~0.00375, so we run a few hundred ticks.
      state = tick_state_with_active_hgt()

      {_final_state, all_events} =
        Enum.reduce(1..500, {state, []}, fn _i, {acc_state, acc_events} ->
          {new_state, events} = Tick.tick(acc_state)
          {new_state, acc_events ++ events}
        end)

      channel_events =
        Enum.filter(all_events, fn e ->
          e.type in [:hgt_transfer, :transformation_event, :phage_infection, :rm_digestion]
        end)

      assert not Enum.empty?(channel_events),
             "Expected at least one channel-emitted event in tick output over 500 ticks"
    end

    test "new_state.pending_events is cleared after tick" do
      state = tick_state_with_active_hgt()
      {new_state, _events} = Tick.tick(state)
      assert new_state.pending_events == []
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
      assert not Enum.empty?(children)

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

  # ---------------------------------------------------------------------------
  # Sub-task 1.5 — cause-tagged death audit events.

  # Bacteriocin helpers (adapted from arkea/test/arkea/sim/bacteriocin_test.exs).
  # `[0, 0, 0]` first 3 codons → `rem(sum, 6) == 0` → `reaction_class: :hydrolysis`.
  defp catalytic_hydrolysis_domain,
    do: Domain.new([0, 0, 1], [0, 0, 0 | List.duplicate(10, 17)])

  defp substrate_binding_domain, do: Domain.new([0, 0, 0], @param_codons)

  defp toxin_gene do
    Gene.from_domains([
      substrate_binding_domain(),
      transmembrane_domain(),
      catalytic_hydrolysis_domain()
    ])
  end

  # Producer carries the bacteriocin gene + a `:phage_receptor` (kin tag from
  # `surface_domain/0`, first_codon=10, rem(10,3)=1) which doubles as
  # the producer's self-immunity marker.
  defp bacteriocin_producer_genome do
    Genome.new([toxin_gene(), Gene.from_domains([surface_domain()])])
  end

  # Victim carries no surface_tag — fully susceptible to the producer's toxin.
  defp bacteriocin_victim_genome do
    Genome.new([Gene.from_domains([catalytic_domain()])])
  end

  describe "bacteriocin_kill emission" do
    test "lethal bacteriocin damage emits :bacteriocin_kill event" do
      # Producer + non-immune victim in the same phase. We pre-damage the
      # victim's wall just *above* the lysis threshold (0.40) so a single
      # tick of bacteriocin damage drops it past the threshold, qualifying
      # as a "lethal" event for emission.
      producer =
        Lineage.new_founder(bacteriocin_producer_genome(), %{surface: 50_000}, 0)

      victim_base = Lineage.new_founder(bacteriocin_victim_genome(), %{surface: 5_000}, 0)
      victim = %{victim_base | biomass: %{victim_base.biomass | wall: 0.405}}

      state =
        BiotopeState.new_from_opts(
          id: "bacteriocin-kill-event-emission",
          archetype: :hot_spring,
          phases: [surface_phase()],
          dilution_rate: 0.0,
          lineages: [producer, victim],
          rng_seed: Mutator.init_seed("bacteriocin-kill-event-emission")
        )

      # Drive ticks until at least one :bacteriocin_kill event surfaces.
      # The pre-damaged victim should cross the threshold within a handful
      # of ticks at 50_000 producer abundance (toxin pool ≈ 5.0/tick).
      {_final_state, all_events} =
        Enum.reduce(1..50, {state, []}, fn _i, {acc_state, acc_events} ->
          {next_state, events} = Tick.tick(acc_state)
          {next_state, acc_events ++ events}
        end)

      kills = Enum.filter(all_events, &(&1.type == :bacteriocin_kill))

      assert not Enum.empty?(kills),
             "Expected at least one :bacteriocin_kill event over 50 ticks; got #{inspect(Enum.map(all_events, & &1.type))}"

      assert Enum.all?(kills, fn e ->
               is_binary(e.victim_lineage_id) and
                 is_list(e.producer_lineage_ids) and
                 e.producer_lineage_ids != [] and
                 Enum.all?(e.producer_lineage_ids, &is_binary/1) and
                 is_binary(e.surface_tag_target) and
                 is_integer(e.tick)
             end)

      # The first emitted kill should target our seeded victim and credit
      # the seeded producer.
      first_kill = hd(kills)
      assert first_kill.victim_lineage_id == victim.id
      assert producer.id in first_kill.producer_lineage_ids
    end
  end

  describe "error_catastrophe_death emission" do
    # Post-Review-2 calibration (Task 5): `Mutator.error_catastrophe_lethality`
    # now follows the Eigen quasispecies criterion strictly — fidelity
    # `(1 − µ/L)^L` versus `1/σ`. With the σ = 2 default the per-cell
    # critical µ is ≈ ln(2) ≈ 0.69, far above any rate Arkea's mutation
    # pipeline can produce (max `mu_per_cell ≈ 0.04` under SOS×4 with
    # repair = 0). This is biologically faithful: bacteria operate orders
    # of magnitude below the Eigen threshold. The legacy "natural
    # emission" test driven through `Tick.tick/1` therefore can no longer
    # trigger; the audit-event contract for `:error_catastrophe_death`
    # remains covered by `audit_writer_test.exs:221` (synthetic event
    # persistence) and `mutator_test.exs` (formula behaviour above the
    # Eigen threshold).
    @tag :skip
    test "lineage with mu * L >> 1 emits :error_catastrophe_death on division" do
      assert false, "deferred: Eigen-aderent threshold is unreachable in stock simulation"
    end
  end
end
