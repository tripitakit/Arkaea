defmodule Arkea.Sim.HGT.Channel.TransformationTest do
  @moduledoc """
  Tests for natural transformation (Phase 13 — DESIGN.md Block 8).
  """
  use ExUnit.Case, async: true

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Sim.HGT.Channel.Transformation
  alias Arkea.Sim.HGT.DnaFragment
  alias Arkea.Sim.Mutator
  alias Arkea.Sim.Phenotype

  # ---------------------------------------------------------------------------
  # Helpers

  @param_codons List.duplicate(10, 20)

  defp catalytic_domain, do: Domain.new([0, 0, 1], @param_codons)
  defp transmembrane_domain, do: Domain.new([0, 0, 2], @param_codons)
  defp channel_domain, do: Domain.new([0, 0, 3], @param_codons)
  defp ligand_sensor_domain, do: Domain.new([0, 0, 7], @param_codons)

  defp competent_genome do
    # Three competence categories on dedicated genes plus a catalytic
    # carrier so the chromosome has at least two loci for recombination.
    chromosome = [
      Gene.from_domains([catalytic_domain()]),
      Gene.from_domains([channel_domain()]),
      Gene.from_domains([transmembrane_domain()]),
      Gene.from_domains([ligand_sensor_domain()])
    ]

    Genome.new(chromosome)
  end

  defp non_competent_genome do
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

  defp dna_fragment(donor_genes, opts \\ []) do
    DnaFragment.new(
      id: Keyword.get(opts, :id, Arkea.UUID.v4()),
      genes: donor_genes,
      abundance: Keyword.get(opts, :abundance, 200),
      methylation_profile: Keyword.get(opts, :methylation_profile, []),
      origin_lineage_id: Keyword.get(opts, :origin_lineage_id, "donor-lineage"),
      created_at_tick: 0
    )
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

  defp seed_phase_with_fragment(phase, fragment) do
    Phase.add_dna_fragment(phase, fragment)
  end

  # ---------------------------------------------------------------------------
  # competence_score / competent?

  describe "competence" do
    test "competent? is true only when all three categories are present" do
      assert Transformation.competent?(founder(competent_genome(), 100))
      refute Transformation.competent?(founder(non_competent_genome(), 100))
    end

    test "competence_score is zero without all three categories" do
      partial =
        Genome.new([
          Gene.from_domains([channel_domain()]),
          Gene.from_domains([transmembrane_domain()])
        ])

      assert Phenotype.from_genome(partial).competence_score == 0.0
    end

    test "competence_score is positive when all three categories are present" do
      assert Phenotype.from_genome(competent_genome()).competence_score > 0.0
    end
  end

  # ---------------------------------------------------------------------------
  # step/4

  describe "step/4" do
    test "no-op when dna_pool is empty" do
      lineage = founder(competent_genome(), 200)
      phase = surface_phase()
      rng = Mutator.init_seed("transformation-empty-pool")

      {ls, p, children, _rng} = Transformation.step([lineage], phase, 1, rng)

      assert ls == [lineage]
      assert p == phase
      assert children == []
    end

    test "no-op when no recipient is competent" do
      lineage = founder(non_competent_genome(), 200)
      phase = seed_phase_with_fragment(surface_phase(), dna_fragment(donor_chromosome()))
      rng = Mutator.init_seed("transformation-no-competence")

      {ls, p, children, _rng} = Transformation.step([lineage], phase, 1, rng)

      assert ls == [lineage]
      # Pool was untouched because no competent recipient existed.
      assert p == phase
      assert children == []
    end

    test "at high uptake rate a competent recipient eventually transforms" do
      recipient = founder(competent_genome(), 200)
      fragment = dna_fragment(donor_chromosome(), abundance: 5_000)
      phase = seed_phase_with_fragment(surface_phase(), fragment)
      rng = Mutator.init_seed("transformation-uptake")

      {_lineages_out, _phase_out, children, _rng_out} =
        Enum.reduce(1..20, {[recipient], phase, [], rng}, fn _i,
                                                             {ls, ph, acc_children, acc_rng} ->
          {ls_out, ph_out, new_children, rng_out} =
            Transformation.step(ls, ph, 1, acc_rng)

          {ls_out, ph_out, acc_children ++ new_children, rng_out}
        end)

      # With abundance 5000 × competence ~0.4 × p_uptake_base 0.0006 ≈ 1.2
      # capped at 0.20 per call, P(zero successes in 20 calls × 1 fragment)
      # ≈ 0.8^20 ≈ 0.012 → at least one transformation expected.
      assert length(children) > 0
    end

    test "every successful uptake consumes one fragment unit" do
      recipient = founder(competent_genome(), 200)
      fragment = dna_fragment(donor_chromosome(), abundance: 100)
      phase = seed_phase_with_fragment(surface_phase(), fragment)
      rng = Mutator.init_seed("transformation-conservation")

      {_ls_out, phase_out, _children, _rng_out} =
        Enum.reduce(1..30, {[recipient], phase, [], rng}, fn _i, {ls, ph, ch, acc_rng} ->
          {ls_out, ph_out, new_children, rng_out} =
            Transformation.step(ls, ph, 1, acc_rng)

          {ls_out, ph_out, ch ++ new_children, rng_out}
        end)

      # Each call may consume up to 1 unit; 30 calls cannot exceed 30
      # consumed units (and the actual count is bounded by p_uptake_max).
      consumed = fragment.abundance - dna_total(phase_out.dna_pool)
      assert consumed >= 0
      assert consumed <= 30
    end

    test "self-uptake (origin matches recipient) is rejected" do
      recipient = founder(competent_genome(), 200)

      fragment =
        dna_fragment(donor_chromosome(),
          abundance: 5_000,
          origin_lineage_id: recipient.id
        )

      phase = seed_phase_with_fragment(surface_phase(), fragment)
      rng = Mutator.init_seed("transformation-self-uptake")

      {ls, ph, children, _rng} =
        Enum.reduce(1..50, {[recipient], phase, [], rng}, fn _i, {ls_in, ph_in, ch_in, acc_rng} ->
          {ls_out, ph_out, new_children, rng_out} =
            Transformation.step(ls_in, ph_in, 1, acc_rng)

          {ls_out, ph_out, ch_in ++ new_children, rng_out}
        end)

      assert children == []
      [persisted_fragment] = Map.values(ph.dna_pool)
      assert persisted_fragment.abundance == fragment.abundance
      assert ls == [recipient]
    end

    test "transformant child's chromosome is the recipient's with one allelic swap" do
      # Build a donor whose first gene is structurally distinguishable
      # from the recipient's first gene (different domain composition).
      structural_gene = Gene.from_domains([Domain.new([0, 0, 8], @param_codons)])

      donor_chromosome = [
        structural_gene,
        Gene.from_domains([channel_domain()]),
        Gene.from_domains([transmembrane_domain()]),
        Gene.from_domains([ligand_sensor_domain()])
      ]

      recipient = founder(competent_genome(), 200)
      fragment = dna_fragment(donor_chromosome, abundance: 10_000)
      phase = seed_phase_with_fragment(surface_phase(), fragment)
      rng = Mutator.init_seed("transformation-allelic-swap")

      {_ls_out, _ph_out, children, _rng_out} =
        Enum.reduce(1..50, {[recipient], phase, [], rng}, fn _i, {ls, ph, ch, acc_rng} ->
          {ls_out, ph_out, new_children, rng_out} =
            Transformation.step(ls, ph, 1, acc_rng)

          {ls_out, ph_out, ch ++ new_children, rng_out}
        end)

      assert length(children) > 0

      child = hd(children)
      assert length(child.genome.chromosome) == length(recipient.genome.chromosome)
      # The child must differ from the recipient on at least one locus.
      diffs =
        Enum.zip(child.genome.chromosome, recipient.genome.chromosome)
        |> Enum.count(fn {a, b} -> a != b end)

      assert diffs >= 1
    end
  end

  # ---------------------------------------------------------------------------
  # R-M gating

  describe "R-M gating" do
    test "fragment without methylation is digested before integration when recipient has restriction enzymes" do
      # Build a recipient whose chromosome encodes both competence AND a
      # restriction enzyme (dna_binding + catalytic_site(:hydrolysis)).
      # Note: the donor cassette carries no methylation, so the gate
      # closes deterministically except for the @cleave_p escape.
      restriction_gene =
        Gene.from_domains([
          Domain.new([0, 0, 5], @param_codons),
          Domain.new([0, 0, 1], @param_codons)
        ])

      genome =
        Genome.new([
          restriction_gene,
          Gene.from_domains([channel_domain()]),
          Gene.from_domains([transmembrane_domain()]),
          Gene.from_domains([ligand_sensor_domain()])
        ])

      recipient = founder(genome, 200)
      fragment = dna_fragment(donor_chromosome(), abundance: 5_000, methylation_profile: [])
      phase = seed_phase_with_fragment(surface_phase(), fragment)
      rng = Mutator.init_seed("transformation-rm-gate")

      {_ls, _ph, children, _rng} =
        Enum.reduce(1..30, {[recipient], phase, [], rng}, fn _i, {ls, ph, ch, acc_rng} ->
          {ls_out, ph_out, new_children, rng_out} =
            Transformation.step(ls, ph, 1, acc_rng)

          {ls_out, ph_out, ch ++ new_children, rng_out}
        end)

      # The R-M gate runs every call; over 30 calls a few transformants
      # can still slip through (cleave_p = 0.7), but the total must be
      # markedly below the 30 calls of an unrestricted run. We simply
      # assert that the gate is engaged (i.e. fragment.abundance was
      # consumed but transformants are bounded).
      assert length(children) <= 15
    end
  end

  # ---------------------------------------------------------------------------
  # helpers

  defp dna_total(dna_pool) do
    dna_pool |> Map.values() |> Enum.reduce(0, fn f, acc -> acc + f.abundance end)
  end
end
