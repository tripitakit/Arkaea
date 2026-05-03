defmodule Arkea.Sim.HGT.PhageTest do
  @moduledoc """
  Property and unit tests for the closed phage cycle (Phase 12 — DESIGN.md
  Block 8). Covers `lytic_burst/5`, `infection_step/4`, and `decay_step/1`.
  """
  use ExUnit.Case, async: true

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Sim.HGT.Phage
  alias Arkea.Sim.HGT.Virion
  alias Arkea.Sim.Mutator

  # ---------------------------------------------------------------------------
  # Helpers

  @param_codons List.duplicate(10, 20)

  defp catalytic_domain, do: Domain.new([0, 0, 1], @param_codons)
  defp structural_domain, do: Domain.new([0, 0, 8], @param_codons)
  defp surface_domain, do: Domain.new([0, 0, 9], @param_codons)
  defp dna_binding_domain, do: Domain.new([0, 0, 5], @param_codons)
  defp transmembrane_domain, do: Domain.new([0, 0, 2], @param_codons)

  defp chromosome_gene, do: Gene.from_domains([catalytic_domain()])

  defp prophage_cassette do
    [
      Gene.from_domains([structural_domain(), surface_domain()])
    ]
  end

  defp seed_genome do
    Genome.new([chromosome_gene()], prophages: [prophage_cassette()])
  end

  defp surface_phase(opts \\ []) do
    Phase.new(:surface,
      temperature: 25.0,
      ph: 7.0,
      osmolarity: 300.0,
      dilution_rate: Keyword.get(opts, :dilution, 0.0)
    )
  end

  defp founder(genome, abundance) do
    Lineage.new_founder(genome, %{surface: abundance}, 0)
  end

  # ---------------------------------------------------------------------------
  # lytic_burst/5

  describe "lytic_burst/5" do
    test "produces virions in the phase pool and shrinks the host" do
      lineage = founder(seed_genome(), 200)
      phase = surface_phase()
      rng = Mutator.init_seed("phage-burst-test")

      {l_out, p_out, virion, _rng_out} = Phage.lytic_burst(lineage, phase, 0, 1, rng)

      assert virion != nil
      assert Virion.valid?(virion)
      assert virion.abundance >= Phage.min_burst_size()
      assert virion.abundance <= Phage.max_burst_size()
      # Host abundance dropped by the lysis fraction (~50%).
      assert Lineage.abundance_in(l_out, :surface) < 200
      # Phase pool carries at least the main phage virion (Phase 16:
      # may also carry a generalised-transducing virion produced
      # alongside the burst with a small per-burst probability).
      assert map_size(p_out.phage_pool) in 1..2
      assert Map.has_key?(p_out.phage_pool, virion.id)
      assert virion.payload_kind == :phage
      # DNA fragment deposited in dna_pool — keyed by fragment UUID,
      # carrying the donor's chromosome and audit-traceable to the lysed
      # lineage.
      assert map_size(p_out.dna_pool) == 1
      [fragment] = Map.values(p_out.dna_pool)
      assert fragment.origin_lineage_id == lineage.id
      assert fragment.abundance > 0
      assert fragment.genes == lineage.genome.chromosome
      # Cassette dropped from the host genome.
      assert l_out.genome.prophages == []
    end

    test "no-op when the cassette index is out of range" do
      lineage = founder(seed_genome(), 200)
      phase = surface_phase()
      rng = Mutator.init_seed("phage-burst-no-cassette")

      {l_out, p_out, virion, _rng_out} = Phage.lytic_burst(lineage, phase, 99, 1, rng)

      assert virion == nil
      assert l_out == lineage
      assert p_out == phase
    end

    test "no-op when the host abundance in the phase is zero" do
      genome = seed_genome()
      lineage = Lineage.new_founder(genome, %{water_column: 100}, 0)
      phase = surface_phase()
      rng = Mutator.init_seed("phage-burst-no-host")

      {l_out, p_out, virion, _rng_out} = Phage.lytic_burst(lineage, phase, 0, 1, rng)

      assert virion == nil
      assert l_out == lineage
      assert p_out == phase
    end
  end

  # ---------------------------------------------------------------------------
  # decay_step/1

  describe "decay_step/1" do
    test "shrinks virion abundance and ages the particle" do
      lineage = founder(seed_genome(), 200)
      phase = surface_phase()
      rng = Mutator.init_seed("phage-decay-test")
      {_l, phase_after_burst, virion, _rng} = Phage.lytic_burst(lineage, phase, 0, 1, rng)

      starting_abundance = virion.abundance

      decayed_phase = Phage.decay_step(phase_after_burst)
      [decayed_virion] = Map.values(decayed_phase.phage_pool)

      assert decayed_virion.abundance < starting_abundance
      assert decayed_virion.decay_age == virion.decay_age + 1
    end

    test "drops virions that decayed to zero abundance" do
      tiny_virion =
        Virion.new(
          id: "tiny",
          genes: [
            Gene.from_domains([
              dna_binding_domain(),
              transmembrane_domain()
            ])
          ],
          abundance: 1,
          surface_signature: nil,
          methylation_profile: [],
          origin_lineage_id: nil,
          created_at_tick: 0
        )

      phase = surface_phase() |> Phase.add_virion(tiny_virion)
      decayed_phase = Phage.decay_step(phase)

      # The virion either decays out of the pool or persists with reduced
      # abundance; either way the pool entry must satisfy the invariant
      # that abundance > 0 (zero entries are pruned).
      Enum.each(decayed_phase.phage_pool, fn {_id, %Virion{abundance: a}} ->
        assert a > 0
      end)
    end

    test "no-op when the phage_pool is empty" do
      phase = surface_phase()
      assert Phage.decay_step(phase) == phase
    end
  end

  # ---------------------------------------------------------------------------
  # infection_step/4

  describe "infection_step/4" do
    test "no-op when the phage_pool is empty" do
      lineage = founder(seed_genome(), 200)
      phase = surface_phase()
      rng = Mutator.init_seed("phage-infection-empty")

      {ls, p, children, _rng_out} = Phage.infection_step([lineage], phase, 1, rng)

      assert ls == [lineage]
      assert p == phase
      assert children == []
    end

    test "generalised transduction virions trigger allelic replacement" do
      # Build a transducing virion directly (skipping the lytic burst RNG)
      # carrying a distinguishable donor gene (structural_fold). Recipient
      # has a 1-gene chromosome with a different domain (catalytic_site).
      donor_gene = Gene.from_domains([structural_domain(), surface_domain()])
      recipient = founder(Genome.new([chromosome_gene()]), 200)

      transducing_virion =
        Virion.new(
          id: Arkea.UUID.v4(),
          genes: [donor_gene],
          abundance: 200,
          surface_signature: nil,
          methylation_profile: [],
          origin_lineage_id: "donor",
          created_at_tick: 0,
          payload_kind: :generalized_transduction
        )

      phase = surface_phase() |> Phase.add_virion(transducing_virion)
      rng = Mutator.init_seed("phage-transduction-allelic")

      {_lineages, _phase, children, _rng} =
        Enum.reduce(1..20, {[recipient], phase, [], rng}, fn _i,
                                                             {ls, ph, acc_children, acc_rng} ->
          {ls_out, ph_out, new_children, rng_out} =
            Phage.infection_step(ls, ph, 1, acc_rng)

          {ls_out, ph_out, acc_children ++ new_children, rng_out}
        end)

      # With high virion abundance, R-M trivial (no enzymes), competence
      # not required for transduction → expect at least one transformant
      # carrying the donor gene at the chromosome position.
      assert length(children) > 0

      child = hd(children)

      assert Enum.any?(child.genome.chromosome, fn g ->
               g.id == donor_gene.id or g == donor_gene
             end)
    end

    test "high-abundance virions produce at least one infection event over many ticks" do
      lineage_donor = founder(seed_genome(), 200)
      lineage_recipient = founder(Genome.new([chromosome_gene()]), 200)
      rng = Mutator.init_seed("phage-infection-many")
      phase = surface_phase()

      {_l, phase_with_phage, _virion, rng1} =
        Phage.lytic_burst(lineage_donor, phase, 0, 1, rng)

      # Pump the virion abundance up to ensure non-trivial infection rate.
      pumped_phase =
        Map.update!(phase_with_phage, :phage_pool, fn pool ->
          Map.new(pool, fn {id, v} -> {id, %{v | abundance: 200}} end)
        end)

      {_lineages_out, _phase_out, children, _rng_out} =
        Enum.reduce(1..50, {[lineage_recipient], pumped_phase, [], rng1}, fn _i,
                                                                             {ls, ph, acc_children,
                                                                              acc_rng} ->
          {ls_out, ph_out, new_children, rng_out} =
            Phage.infection_step(ls, ph, 1, acc_rng)

          {ls_out, ph_out, acc_children ++ new_children, rng_out}
        end)

      # Over 50 ticks with a stable virion population we expect at least
      # one successful infection event (lytic or lysogenic). The variance
      # is high but P(zero events in 50 ticks) << 1% with these parameters.
      assert length(children) > 0 or
               Enum.any?([lineage_recipient], fn _ -> false end),
             "Expected at least one infection product after 50 ticks"
    end
  end
end
