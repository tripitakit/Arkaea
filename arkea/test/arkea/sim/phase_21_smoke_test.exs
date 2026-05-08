defmodule Arkea.Sim.Phase21SmokeTest do
  @moduledoc """
  End-to-end smoke test for Phase 21.

  Builds a realistic two-lineage scenario (a founder carrying a
  conjugative plasmid + a regulator gene, and a plain recipient),
  runs ~30 ticks through the real `BiotopeServer → Tick → Store →
  AuditWriter + TimeSeries` pipeline with persistence enabled, and
  asserts that each of the five Phase-21 commits has produced its
  observable artefact in the database / view layer:

    * **Top 5 #2** — `Arkea.Views.HGTLedger.build/2` produces an entry
      whose `kind == "conjugation"` when the audit log carries an
      `hgt_transfer` with `payload["channel"] == "conjugation"`.

    * **Top 5 #3** — the new typed events (`:sos_active`,
      `:mutator_emergence`, `:biofilm_formation` /
      `:biofilm_dispersal`, `:migration_pulse`) flow through the
      `AuditWriter` typed branch without crashing. We synthesise an
      `:sos_active` event directly to confirm round-trip persistence,
      since the natural occurrence is opportunistic and may or may
      not happen within 30 ticks under stable conditions.

    * **Top 5 #4** — `TimeSeries.list(id, kind: "phenotype_trait")`
      returns one row per genome-bearing lineage at every cellular
      sampling boundary, with the canonical scalar / boolean payload
      shape.

    * **Top 5 #5** — `Phenotype.regulatory_outputs` is non-empty for
      the regulator-carrying founder, the entry shape is correct, and
      `sigma_factor_components/1` produces the summary tuple. The
      same fields appear in the `SnapshotExport` JSON.

  Reproducible: every roll uses `Mutator.init_seed/1` derived from a
  fixed string. Fail = real regression.
  """

  use Arkea.DataCase, async: false
  use Oban.Testing, repo: Arkea.Repo

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Persistence.AuditLog
  alias Arkea.Persistence.AuditWriter
  alias Arkea.Persistence.TimeSeries
  alias Arkea.Sim.Biotope.Server, as: BiotopeServer
  alias Arkea.Sim.Biotope.Supervisor, as: BiotopeSupervisor
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Mutator
  alias Arkea.Sim.Phenotype
  alias Arkea.Views.HGTLedger
  alias Arkea.Views.SnapshotExport

  @param_codons List.duplicate(10, 20)
  # Domain type tags — sum of the 3 type_tag codons % 11 selects the
  # type from `Arkea.Genome.Domain.Type.@types`.
  defp catalytic_domain, do: Domain.new([0, 0, 1], @param_codons)
  defp transmembrane_domain, do: Domain.new([0, 0, 2], @param_codons)
  defp dna_binding_domain, do: Domain.new([0, 0, 5], @param_codons)
  # type_tag sum 6 → :regulator_output. First parameter codon even →
  # :activator (ensures regulatory_outputs[0].mode == :activator).
  defp activator_regulator_domain do
    Domain.new([0, 0, 6], [0 | List.duplicate(10, 19)])
  end

  defp founder_genome do
    # Chromosome: catalytic + dna_binding + regulator_output → enough
    # composition to derive a phenotype with non-zero
    # `regulatory_outputs` (Top 5 #5). The dna_binding contributes
    # `binding_affinity > 0` to the regulator's enriched entry.
    chromosome = [
      Gene.from_domains([catalytic_domain()]),
      Gene.from_domains([dna_binding_domain(), activator_regulator_domain()])
    ]

    # Plasmid: 3 transmembrane_anchor domains → conjugation_strength = 3,
    # so the donor will eventually conjugate the plasmid into the
    # recipient (Top 5 #2 — produces `hgt_transfer` with
    # `payload.channel = "conjugation"`).
    plasmid = [Gene.from_domains([transmembrane_domain(), transmembrane_domain()])]

    Genome.new(chromosome, plasmids: [plasmid])
  end

  defp recipient_genome do
    # Plain catalytic-only chromosome. Recipient lacks the conjugative
    # plasmid so the donor → recipient transfer is a real event.
    Genome.new([Gene.from_domains([catalytic_domain()])])
  end

  defp surface_phase do
    Phase.new(:surface,
      temperature: 25.0,
      ph: 7.0,
      osmolarity: 300.0,
      dilution_rate: 0.0
    )
  end

  defp build_state do
    donor = Lineage.new_founder(founder_genome(), %{surface: 200}, 0)
    recipient = Lineage.new_founder(recipient_genome(), %{surface: 200}, 0)

    BiotopeState.new_from_opts(
      id: Arkea.UUID.v4(),
      archetype: :eutrophic_pond,
      zone: :phase_21_smoke,
      phases: [surface_phase()],
      dilution_rate: 0.0,
      lineages: [donor, recipient],
      rng_seed: Mutator.init_seed("phase-21-smoke")
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

  test "Phase 21 smoke: 30 ticks of a regulator + conjugative seed exercises every Top-5 artefact" do
    state = build_state()
    [donor, recipient] = state.lineages

    start_biotope(state)

    # ----- Top 5 #5 (a) — structural regulatory aggregation on the
    # founder phenotype, before any tick. Asserts the static surface
    # added to `Phenotype.from_genome/1` is wired.
    founder_phenotype = Phenotype.from_genome(donor.genome)
    assert [%{mode: :activator} = entry | _] = founder_phenotype.regulatory_outputs

    assert entry.binding_affinity > 0.0,
           "regulator co-located with :dna_binding should inherit non-zero binding_affinity"

    sigma = Phenotype.sigma_factor_components(founder_phenotype)
    assert sigma.n_activators >= 1
    assert sigma.net_activation > 0.0

    # ----- Drive the simulation: 30 ticks crosses 3 cellular boundaries
    # (10, 20, 30) → at least 3 phenotype_trait sample windows.
    for _i <- 1..30 do
      assert :ok = BiotopeServer.manual_tick(state.id)
    end

    persisted = BiotopeServer.get_state(state.id)
    assert persisted.tick_count == 30

    # ----- Top 5 #4 — phenotype_trait time-series samples persisted.
    trait_rows = TimeSeries.list(state.id, kind: "phenotype_trait", repo: Repo)
    assert trait_rows != [], "expected at least one phenotype_trait sample after 30 ticks"

    # Cellular sampling cadence is 10 ticks → samples at 10, 20, 30.
    sampled_ticks = trait_rows |> Enum.map(& &1.tick) |> Enum.uniq() |> Enum.sort()
    assert 10 in sampled_ticks and 20 in sampled_ticks and 30 in sampled_ticks

    sample = hd(trait_rows)
    payload = sample.payload

    # All 11 traits exposed by `TimeSeries.trait_payload/1` must be present.
    expected_keys = ~w(base_growth_rate repair_efficiency energy_cost
                       dna_binding_affinity competence_score hydrolase_capacity
                       efflux_capacity structural_stability n_transmembrane
                       biofilm_capable regulatory_net_activation)

    for key <- expected_keys do
      assert Map.has_key?(payload, key),
             "phenotype_trait payload missing key: #{key} (got: #{inspect(Map.keys(payload))})"
    end

    # The donor (regulator-carrier) sample must show a positive
    # `regulatory_net_activation` derived from `sigma_factor_components`.
    donor_sample = Enum.find(trait_rows, &(&1.scope_id == donor.id))
    assert donor_sample, "donor lineage should appear in phenotype_trait samples"
    assert donor_sample.payload["regulatory_net_activation"] > 0.0

    # ----- Top 5 #2 — synthesise an `hgt_transfer` audit event with
    # `channel: conjugation` (real conjugation under stable abundance
    # is rare per-tick, so a deterministic synthetic insert keeps the
    # test stable; the *real* per-tick emission path is exercised by
    # `audit_events_test.exs::hgt_transfer event from conjugation`).
    {:ok, _} =
      AuditWriter.insert_events(
        Repo,
        state.id,
        25,
        [
          %{
            type: :hgt_transfer,
            channel: :conjugation,
            donor_lineage_id: donor.id,
            recipient_lineage_id: recipient.id,
            plasmid_inc_group: 1,
            tick: 25
          }
        ],
        DateTime.utc_now() |> DateTime.truncate(:microsecond)
      )

    audit_rows = recent_audit(state.id)
    ledger = HGTLedger.build(audit_rows)
    conjugation_kinds = Map.get(ledger.kind_counts, "conjugation", 0)

    assert conjugation_kinds >= 1,
           "Top 5 #2: HGTLedger.build/2 should promote hgt_transfer + channel=conjugation " <>
             "to kind 'conjugation'; got kinds: #{inspect(Map.keys(ledger.kind_counts))}"

    # Filtering by `kind: "conjugation"` must narrow the entries.
    filtered = HGTLedger.build(audit_rows, kind: "conjugation")
    assert filtered.total >= 1
    assert Enum.all?(filtered.entries, &(&1.kind == "conjugation"))

    # ----- Top 5 #3 — typed-event branch coverage for `:sos_active`.
    # Synthesise the event and assert the row reads back with the
    # documented payload shape.
    {:ok, _} =
      AuditWriter.insert_events(
        Repo,
        state.id,
        28,
        [
          %{
            type: :sos_active,
            tick: 28,
            lineage_id: donor.id,
            dna_damage: 0.234,
            trigger_source: :replication_load
          }
        ],
        DateTime.utc_now() |> DateTime.truncate(:microsecond)
      )

    sos_rows =
      Repo.all(
        from a in AuditLog,
          where: a.target_biotope_id == ^state.id and a.event_type == "sos_active"
      )

    assert [sos_row] = sos_rows
    assert sos_row.target_lineage_id == donor.id
    assert sos_row.payload["trigger_source"] == "replication_load"
    assert sos_row.payload["dna_damage"] == 0.234

    # ----- Top 5 #5 (b) — snapshot export carries the structural
    # `regulatory_outputs` + `sigma_factor_components` for every
    # genome-bearing lineage.
    snapshot = SnapshotExport.build(persisted, audit_rows, [])
    donor_lineage_export = Enum.find(snapshot.lineages, &(&1.id == donor.id))
    assert donor_lineage_export, "donor lineage missing from snapshot export"

    pheno_export = donor_lineage_export.phenotype
    assert is_list(pheno_export.regulatory_outputs)
    assert pheno_export.regulatory_outputs != []
    [first_export | _] = pheno_export.regulatory_outputs
    assert first_export.mode in ["activator", "repressor"]
    assert first_export.binding_affinity >= 0.0 and first_export.binding_affinity <= 1.0

    sigma_export = pheno_export.sigma_factor_components
    assert is_map(sigma_export)
    assert Map.has_key?(sigma_export, :net_activation)
    assert Map.has_key?(sigma_export, :n_activators)
  end

  defp recent_audit(biotope_id) do
    import Ecto.Query

    Repo.all(
      from a in AuditLog,
        where: a.target_biotope_id == ^biotope_id,
        order_by: [asc: a.occurred_at_tick]
    )
  end
end
