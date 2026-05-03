defmodule Arkea.Sim.XenobioticTest do
  @moduledoc """
  Tests for Phase 15 xenobiotic exposure (DESIGN.md Block 8).

  Coverage:
    - `Xenobiotic.bound_fraction/2`, `intracellular_concentration/2`,
      `survival_factor/3`, `degradation_amount/3`
    - `Phenotype` derivations: `target_classes`, `hydrolase_capacity`,
      `efflux_capacity`
    - End-to-end RAS scenario: a hydrolase-bearing population
      detoxifies a β-lactam pulse over time.
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
  alias Arkea.Sim.Xenobiotic

  @param_codons List.duplicate(10, 20)

  # Codons that produce a `:catalytic_site(:hydrolysis)`. The reaction
  # class is `Enum.at([:hydrolysis, :oxidation, :reduction,
  # :isomerization, :ligation, :lyase], rem(sum(first_3), 6))`. We need
  # rem(sum, 6) == 0 → use [0, 0, 0 | rest].
  defp catalytic_hydrolysis_codons, do: [0, 0, 0 | List.duplicate(10, 17)]

  # ---------------------------------------------------------------------------
  # bound_fraction / intracellular_concentration

  describe "bound_fraction/2" do
    test "zero concentration → zero bound fraction" do
      assert Xenobiotic.bound_fraction(0.0, 10.0) == 0.0
    end

    test "concentration much above Kd saturates near 1.0" do
      assert Xenobiotic.bound_fraction(1_000.0, 10.0) > 0.98
    end

    test "concentration equal to Kd produces ~0.5 bound fraction" do
      assert Xenobiotic.bound_fraction(10.0, 10.0) == 0.5
    end

    test "monotonic in concentration" do
      f1 = Xenobiotic.bound_fraction(5.0, 10.0)
      f2 = Xenobiotic.bound_fraction(20.0, 10.0)
      f3 = Xenobiotic.bound_fraction(80.0, 10.0)
      assert f1 < f2
      assert f2 < f3
    end
  end

  describe "intracellular_concentration/2" do
    test "no efflux → full extracellular concentration" do
      assert Xenobiotic.intracellular_concentration(50.0, 0.0) == 50.0
    end

    test "max efflux knocks concentration down by 90%" do
      assert_in_delta Xenobiotic.intracellular_concentration(50.0, 1.0), 5.0, 0.001
    end

    test "intermediate efflux scales linearly" do
      mid = Xenobiotic.intracellular_concentration(50.0, 0.5)
      assert mid > 5.0
      assert mid < 50.0
    end
  end

  # ---------------------------------------------------------------------------
  # survival_factor

  describe "survival_factor/3" do
    test "empty pool yields full survival" do
      assert Xenobiotic.survival_factor(%{}, %{pbp_like: 1.0}, 0.0) == 1.0
    end

    test "lineage without target_class is intrinsically resistant" do
      pool = %{beta_lactam: 100.0}
      assert Xenobiotic.survival_factor(pool, %{}, 0.0) == 1.0
    end

    test "fully susceptible lineage takes a hit at lethal dose" do
      pool = %{beta_lactam: 1_000.0}
      assert Xenobiotic.survival_factor(pool, %{pbp_like: 1.0}, 0.0) < 0.1
    end

    test "efflux pump rescues a susceptible lineage" do
      pool = %{beta_lactam: 1_000.0}
      shielded = Xenobiotic.survival_factor(pool, %{pbp_like: 1.0}, 1.0)
      bare = Xenobiotic.survival_factor(pool, %{pbp_like: 1.0}, 0.0)

      assert shielded > bare
    end

    test "unknown drug is silently ignored" do
      pool = %{unknown: 1_000.0}
      assert Xenobiotic.survival_factor(pool, %{pbp_like: 1.0}, 0.0) == 1.0
    end
  end

  # ---------------------------------------------------------------------------
  # degradation_amount

  describe "degradation_amount/3" do
    test "non-hydrolase population removes nothing" do
      assert Xenobiotic.degradation_amount(100.0, 0.0, 1_000) == 0.0
    end

    test "hydrolase removes drug proportional to abundance × capacity × concentration" do
      r1 = Xenobiotic.degradation_amount(100.0, 1.0, 100)
      r2 = Xenobiotic.degradation_amount(100.0, 1.0, 1_000)
      r3 = Xenobiotic.degradation_amount(100.0, 5.0, 1_000)

      assert r1 > 0.0
      assert r2 > r1
      assert r3 > r2
    end

    test "removal cannot exceed available drug" do
      assert Xenobiotic.degradation_amount(10.0, 1_000.0, 1_000_000) <= 10.0
    end
  end

  # ---------------------------------------------------------------------------
  # Phenotype derivations

  describe "Phenotype derivations" do
    test "PBP-like lineage exposes a non-zero pbp_like target" do
      pbp_gene =
        Gene.from_domains([
          Domain.new([0, 0, 2], @param_codons),
          Domain.new([0, 0, 1], @param_codons)
        ])

      genome = Genome.new([pbp_gene])
      phenotype = Phenotype.from_genome(genome)

      assert phenotype.target_classes.pbp_like > 0.0
    end

    test "ribosome_like is always 1.0 (intrinsic)" do
      genome = Genome.new([Gene.from_domains([Domain.new([0, 0, 0], @param_codons)])])
      phenotype = Phenotype.from_genome(genome)

      assert phenotype.target_classes.ribosome_like == 1.0
    end

    test "hydrolase-bearing genome yields capacity > 0" do
      hydrolase_gene =
        Gene.from_domains([
          Domain.new([0, 0, 0], @param_codons),
          Domain.new([0, 0, 1], catalytic_hydrolysis_codons())
        ])

      genome = Genome.new([hydrolase_gene])
      phenotype = Phenotype.from_genome(genome)

      assert phenotype.hydrolase_capacity > 0.0
    end

    test "non-hydrolase genome has zero hydrolase capacity" do
      naked = Genome.new([Gene.from_domains([Domain.new([0, 0, 0], @param_codons)])])
      assert Phenotype.from_genome(naked).hydrolase_capacity == 0.0
    end

    test "efflux pump composition yields non-zero efflux capacity" do
      pump_gene =
        Gene.from_domains([
          Domain.new([0, 0, 2], @param_codons),
          Domain.new([0, 0, 3], @param_codons),
          Domain.new([0, 0, 4], @param_codons),
          Domain.new([0, 0, 0], @param_codons)
        ])

      genome = Genome.new([pump_gene])
      phenotype = Phenotype.from_genome(genome)

      assert phenotype.efflux_capacity > 0.0
    end
  end

  # ---------------------------------------------------------------------------
  # End-to-end RAS — drug pool decays under hydrolase pressure

  describe "end-to-end RAS" do
    test "β-lactam pool shrinks under sustained hydrolase population" do
      hydrolase_gene =
        Gene.from_domains([
          Domain.new([0, 0, 0], @param_codons),
          Domain.new([0, 0, 1], catalytic_hydrolysis_codons())
        ])

      genome = Genome.new([hydrolase_gene])

      # Populate the lineage in a phase with a β-lactam pulse already
      # injected. We are not testing growth here — only drug
      # degradation by step_xenobiotic across many ticks.
      phase_name = :surface

      phase =
        Phase.new(phase_name, dilution_rate: 0.0)
        |> Phase.update_metabolite(:glucose, 1_000.0)
        |> Phase.add_xenobiotic(:beta_lactam, 200.0)

      lineage = Lineage.new_founder(genome, %{phase_name => 5_000}, 0)

      state =
        BiotopeState.new_from_opts(
          id: Arkea.UUID.v4(),
          archetype: :eutrophic_pond,
          phases: [phase],
          dilution_rate: 0.0,
          lineages: [lineage],
          metabolite_inflow: %{glucose: 50.0}
        )

      final =
        Enum.reduce(1..200, state, fn _, acc ->
          {next, _events} = Tick.tick(acc)
          next
        end)

      [final_phase] = final.phases
      starting = 200.0
      final_conc = Map.get(final_phase.xenobiotic_pool, :beta_lactam, 0.0)

      assert final_conc < starting,
             "Expected hydrolase population to shrink the β-lactam pool from #{starting}, got #{final_conc}"
    end
  end
end
