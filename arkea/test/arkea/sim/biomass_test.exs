defmodule Arkea.Sim.BiomassTest do
  @moduledoc """
  Property + unit tests for Phase 14 biomass and toxicity (DESIGN.md
  Block 8).
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Sim.Biomass
  alias Arkea.Sim.Metabolism
  alias Arkea.Sim.Phenotype

  @param_codons List.duplicate(10, 20)

  # ---------------------------------------------------------------------------
  # Genome / phenotype builders

  # :substrate_binding has type_tag with sum%11 == 0; we use [0,0,0].
  # The first parameter codon picks the metabolite (rem(c, 13)).
  defp substrate_binding_for_metabolite(metabolite_id) do
    Domain.new([0, 0, 0], [metabolite_id | List.duplicate(0, 19)])
  end

  # Force a :catalytic_site with a desired reaction class.
  # `:catalytic_site` lives at type_tag whose sum%11 == 1 (e.g. [0,0,1]).
  # The reaction_class is `Enum.at(@reaction_classes, rem(sum(first_3), 6))`,
  # with @reaction_classes = [:hydrolysis, :oxidation, :reduction,
  # :isomerization, :ligation, :lyase].
  defp catalytic_reduction_codons do
    # sum of first 3 = 2 → rem(2, 6) = 2 → :reduction
    [2, 0, 0 | List.duplicate(0, 17)]
  end

  defp catalytic_reduction_domain do
    Domain.new([0, 0, 1], catalytic_reduction_codons())
  end

  defp generic_catalytic_domain, do: Domain.new([0, 0, 1], @param_codons)

  # Genome with no detoxify activity (anaerobe-like).
  defp anaerobe_genome do
    Genome.new([Gene.from_domains([generic_catalytic_domain()])])
  end

  # Genome with catalase-like activity for oxygen.
  defp aerobe_with_catalase do
    catalase_gene =
      Gene.from_domains([
        substrate_binding_for_metabolite(6),
        catalytic_reduction_domain()
      ])

    Genome.new([catalase_gene, Gene.from_domains([generic_catalytic_domain()])])
  end

  defp basic_phase(opts \\ []) do
    Phase.new(:water_column,
      temperature: 25.0,
      ph: 7.0,
      osmolarity: Keyword.get(opts, :osmolarity, 300.0),
      dilution_rate: 0.0
    )
  end

  # ---------------------------------------------------------------------------
  # toxicity_factor / detoxify_targets

  describe "Metabolism.toxicity_factor/2" do
    test "no oxygen + no detoxify → factor 1.0" do
      assert Metabolism.toxicity_factor(%{}, MapSet.new()) == 1.0
    end

    test "oxygen below threshold has no effect" do
      assert Metabolism.toxicity_factor(%{oxygen: 100.0}, MapSet.new()) == 1.0
    end

    test "oxygen above threshold drags survival down for unprotected lineages" do
      assert Metabolism.toxicity_factor(%{oxygen: 600.0}, MapSet.new()) < 1.0
    end

    test "extreme oxygen knocks survival close to zero for unprotected lineages" do
      assert Metabolism.toxicity_factor(%{oxygen: 5_000.0}, MapSet.new()) == 0.0
    end

    test "catalase-like lineage is fully shielded from oxygen toxicity" do
      assert Metabolism.toxicity_factor(%{oxygen: 5_000.0}, MapSet.new([:oxygen])) == 1.0
    end

    test "toxicity is monotonically non-increasing in [O₂] for unprotected lineages" do
      f1 = Metabolism.toxicity_factor(%{oxygen: 250.0}, MapSet.new())
      f2 = Metabolism.toxicity_factor(%{oxygen: 500.0}, MapSet.new())
      f3 = Metabolism.toxicity_factor(%{oxygen: 800.0}, MapSet.new())

      assert f1 >= f2
      assert f2 >= f3
    end

    property "factor is always in [0.0, 1.0]" do
      check all(
              o2 <- StreamData.float(min: 0.0, max: 5_000.0),
              h2s <- StreamData.float(min: 0.0, max: 1_000.0),
              max_runs: 100
            ) do
        f = Metabolism.toxicity_factor(%{oxygen: o2, h2s: h2s}, MapSet.new())
        assert f >= 0.0
        assert f <= 1.0
      end
    end
  end

  describe "Phenotype.detoxify_targets/1" do
    test "anaerobe genome has empty detoxify_targets" do
      genome = anaerobe_genome()
      assert MapSet.size(Phenotype.detoxify_targets(genome)) == 0
    end

    test "aerobe with catalase lists oxygen" do
      genome = aerobe_with_catalase()
      targets = Phenotype.detoxify_targets(genome)
      assert MapSet.member?(targets, :oxygen)
    end
  end

  # ---------------------------------------------------------------------------
  # elemental_factor

  describe "Metabolism.elemental_factor/3" do
    test "lineage with no elemental affinities is unconstrained" do
      affinities = %{glucose: %{km: 1.0, kcat: 1.0}}
      assert Metabolism.elemental_factor(%{glucose: 100.0}, affinities, 100) == 1.0
    end

    test "P-affinity lineage with adequate uptake reaches 1.0" do
      affinities = %{po4: %{km: 1.0, kcat: 1.0}}
      uptake = %{po4: 100.0}
      assert Metabolism.elemental_factor(uptake, affinities, 50) == 1.0
    end

    test "P-affinity lineage with depleted pool drops factor sharply" do
      affinities = %{po4: %{km: 1.0, kcat: 1.0}}
      uptake = %{po4: 0.0}
      f = Metabolism.elemental_factor(uptake, affinities, 100)
      assert f < 0.05
    end

    test "factor is monotonically non-decreasing in P uptake" do
      affinities = %{po4: %{km: 1.0, kcat: 1.0}}

      f_low = Metabolism.elemental_factor(%{po4: 0.001}, affinities, 100)
      f_mid = Metabolism.elemental_factor(%{po4: 0.5}, affinities, 100)
      f_high = Metabolism.elemental_factor(%{po4: 10.0}, affinities, 100)

      assert f_low <= f_mid
      assert f_mid <= f_high
    end
  end

  # ---------------------------------------------------------------------------
  # Biomass.compute_delta and apply_delta

  describe "Biomass.compute_delta/5 + apply_delta/2" do
    test "fully intact cell with no stress and no ATP yields zero delta" do
      genome = anaerobe_genome()
      phenotype = Phenotype.from_genome(genome)

      delta = Biomass.compute_delta(phenotype, 0.0, 1.0, 1.0, basic_phase())

      assert delta.progress.dna == 0.0
      assert delta.decay.dna == 0.0
    end

    test "P-limited cell with high ATP accumulates DNA decay only when elemental drops" do
      genome = anaerobe_genome()
      phenotype = Phenotype.from_genome(genome)
      delta = Biomass.compute_delta(phenotype, 100.0, 0.05, 1.0, basic_phase())

      assert delta.decay.dna > 0.0
    end

    test "osmotic shock outside tolerance drives membrane and wall decay" do
      genome = anaerobe_genome()
      phenotype = Phenotype.from_genome(genome)
      shock_phase = basic_phase(osmolarity: 2_000.0)

      delta = Biomass.compute_delta(phenotype, 100.0, 1.0, 1.0, shock_phase)
      assert delta.decay.membrane > 0.0
      assert delta.decay.wall > 0.0
    end

    test "apply_delta clamps biomass into [0.0, 1.0]" do
      starting = %{membrane: 0.5, wall: 0.5, dna: 0.5}

      delta = %{
        progress: %{membrane: 5.0, wall: 0.0, dna: 0.0},
        decay: %{membrane: 0.0, wall: 5.0, dna: 0.0}
      }

      result = Biomass.apply_delta(starting, delta)
      assert result.membrane == 1.0
      assert result.wall == 0.0
      assert result.dna == 0.5
    end
  end

  # ---------------------------------------------------------------------------
  # lysis_probability

  describe "Biomass.lysis_probability/1" do
    test "intact biomass yields zero probability" do
      assert Biomass.lysis_probability(%{membrane: 1.0, wall: 1.0, dna: 1.0}) == 0.0
    end

    test "wall below threshold drives a positive probability" do
      assert Biomass.lysis_probability(%{membrane: 1.0, wall: 0.1, dna: 1.0}) > 0.0
    end

    test "the most-collapsed component dominates" do
      p =
        Biomass.lysis_probability(%{
          membrane: 0.5,
          wall: 0.05,
          dna: 0.5
        })

      # Wall 0.05 is much further below its 0.40 threshold than membrane
      # 0.5 (above its 0.30 threshold) — wall pressure wins.
      assert p > 0.5
    end

    property "probability stays in [0.0, 1.0] for any biomass map" do
      check all(
              m <- StreamData.float(min: 0.0, max: 1.0),
              w <- StreamData.float(min: 0.0, max: 1.0),
              d <- StreamData.float(min: 0.0, max: 1.0),
              max_runs: 200
            ) do
        p = Biomass.lysis_probability(%{membrane: m, wall: w, dna: d})
        assert p >= 0.0
        assert p <= 1.0
      end
    end
  end
end
