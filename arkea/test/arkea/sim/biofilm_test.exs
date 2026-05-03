defmodule Arkea.Sim.BiofilmTest do
  @moduledoc """
  Tests for Phase 18 biofilm capability and dilution discount
  (DESIGN.md Block 8 Phase 18).
  """
  use ExUnit.Case, async: true

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Phenotype
  alias Arkea.Sim.Tick

  @param_codons List.duplicate(10, 20)

  # Codons that yield :structural_fold with multimerization_n ≥ 2.
  # `multimerization_n = max(1, rem(sum_last_3, 8) + 1)`, so the last
  # three codons must sum to a value whose rem-by-8 is non-zero. The
  # default @param_codons (all 10s) sums to 30 in the last three;
  # rem(30, 8) = 6 → multimerization_n = 7. Good.
  defp structural_fold_high_n, do: Domain.new([0, 0, 8], @param_codons)

  defp surface_tag_domain, do: Domain.new([0, 0, 9], @param_codons)
  defp catalytic_domain, do: Domain.new([0, 0, 1], @param_codons)

  defp biofilm_genome do
    Genome.new([
      Gene.from_domains([surface_tag_domain(), structural_fold_high_n()]),
      Gene.from_domains([catalytic_domain()])
    ])
  end

  defp planktonic_genome do
    Genome.new([Gene.from_domains([catalytic_domain()])])
  end

  describe "Phenotype.biofilm_capable?/1" do
    test "true when surface tag + multimer structural fold are both present" do
      assert Phenotype.from_genome(biofilm_genome()).biofilm_capable?
    end

    test "false when only a surface tag is present" do
      genome = Genome.new([Gene.from_domains([surface_tag_domain()])])
      refute Phenotype.from_genome(genome).biofilm_capable?
    end

    test "false when only a structural fold is present (no anchor)" do
      genome = Genome.new([Gene.from_domains([structural_fold_high_n()])])
      refute Phenotype.from_genome(genome).biofilm_capable?
    end

    test "false on a stripped catalytic-only genome" do
      refute Phenotype.from_genome(planktonic_genome()).biofilm_capable?
    end
  end

  describe "Tick.step_environment/1 biofilm dilution discount" do
    test "biofilm-capable lineage washes out slower than planktonic at the same phase rate" do
      phase = Phase.new(:water_column, dilution_rate: 0.10)

      biofilm =
        Lineage.new_founder(biofilm_genome(), %{water_column: 1_000}, 0)

      planktonic =
        Lineage.new_founder(planktonic_genome(), %{water_column: 1_000}, 0)

      state =
        BiotopeState.new_from_opts(
          id: Arkea.UUID.v4(),
          archetype: :eutrophic_pond,
          phases: [phase],
          dilution_rate: 0.10,
          lineages: [biofilm, planktonic]
        )

      after_one = Tick.step_environment(state)

      biofilm_after = Enum.find(after_one.lineages, &(&1.id == biofilm.id))
      planktonic_after = Enum.find(after_one.lineages, &(&1.id == planktonic.id))

      biofilm_count = Lineage.abundance_in(biofilm_after, :water_column)
      planktonic_count = Lineage.abundance_in(planktonic_after, :water_column)

      # Biofilm gets a 50 % discount → effective rate 0.05 instead of
      # 0.10 → ~950 vs ~900 cells after one tick.
      assert biofilm_count > planktonic_count
    end

    test "non-biofilm phenotypes are unaffected by the discount" do
      phase = Phase.new(:water_column, dilution_rate: 0.10)

      l1 = Lineage.new_founder(planktonic_genome(), %{water_column: 1_000}, 0)
      l2 = Lineage.new_founder(planktonic_genome(), %{water_column: 1_000}, 0)

      state =
        BiotopeState.new_from_opts(
          id: Arkea.UUID.v4(),
          archetype: :eutrophic_pond,
          phases: [phase],
          dilution_rate: 0.10,
          lineages: [l1, l2]
        )

      after_one = Tick.step_environment(state)

      counts =
        Enum.map(after_one.lineages, fn l ->
          Lineage.abundance_in(l, :water_column)
        end)

      [a, b] = counts
      assert a == b
    end
  end
end
