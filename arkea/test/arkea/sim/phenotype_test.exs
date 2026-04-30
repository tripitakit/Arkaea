defmodule Arkea.Sim.PhenotypeTest do
  @moduledoc """
  Tests for `Arkea.Sim.Phenotype` — the emergent phenotype derived from a genome.

  Coverage:
  - Determinism: same genome always yields the same phenotype.
  - Range invariants: all float fields are within their documented bounds.
  - Aggregation unit tests: specific genome compositions yield predictable outcomes.
  - Surface tags: only valid tag_class atoms are produced.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Sim.Phenotype

  import Arkea.Generators, only: [genome: 0]

  # ---------------------------------------------------------------------------
  # Property: determinism

  property "Phenotype.from_genome/1 is deterministic for the same genome" do
    check all(g <- genome(), max_runs: 150) do
      p1 = Phenotype.from_genome(g)
      p2 = Phenotype.from_genome(g)
      assert p1 == p2, "from_genome/1 returned different results for the same genome"
    end
  end

  # ---------------------------------------------------------------------------
  # Property: range invariants

  property "base_growth_rate is in 0.0..1.0" do
    check all(g <- genome(), max_runs: 200) do
      phenotype = Phenotype.from_genome(g)

      assert phenotype.base_growth_rate >= 0.0 and phenotype.base_growth_rate <= 1.0,
             "base_growth_rate #{phenotype.base_growth_rate} out of 0.0..1.0"
    end
  end

  property "energy_cost is in 0.0..5.0" do
    check all(g <- genome(), max_runs: 200) do
      phenotype = Phenotype.from_genome(g)

      assert phenotype.energy_cost >= 0.0 and phenotype.energy_cost <= 5.0,
             "energy_cost #{phenotype.energy_cost} out of 0.0..5.0"
    end
  end

  property "repair_efficiency is in 0.0..1.0" do
    check all(g <- genome(), max_runs: 200) do
      phenotype = Phenotype.from_genome(g)

      assert phenotype.repair_efficiency >= 0.0 and phenotype.repair_efficiency <= 1.0,
             "repair_efficiency #{phenotype.repair_efficiency} out of 0.0..1.0"
    end
  end

  property "structural_stability is in 0.0..1.0" do
    check all(g <- genome(), max_runs: 200) do
      phenotype = Phenotype.from_genome(g)

      assert phenotype.structural_stability >= 0.0 and phenotype.structural_stability <= 1.0,
             "structural_stability #{phenotype.structural_stability} out of 0.0..1.0"
    end
  end

  property "n_transmembrane is a non-negative integer" do
    check all(g <- genome(), max_runs: 150) do
      phenotype = Phenotype.from_genome(g)
      assert is_integer(phenotype.n_transmembrane) and phenotype.n_transmembrane >= 0
    end
  end

  property "surface_tags is a list of atoms" do
    valid_tag_classes = [:pilus_receptor, :phage_receptor, :surface_antigen]

    check all(g <- genome(), max_runs: 150) do
      phenotype = Phenotype.from_genome(g)
      assert is_list(phenotype.surface_tags)

      for tag <- phenotype.surface_tags do
        assert is_atom(tag),
               "surface tag #{inspect(tag)} is not an atom"

        assert tag in valid_tag_classes,
               "surface tag #{inspect(tag)} not in valid_tag_classes"
      end
    end
  end

  property "substrate_affinities keys are integers in 0..12" do
    check all(g <- genome(), max_runs: 150) do
      phenotype = Phenotype.from_genome(g)
      assert is_map(phenotype.substrate_affinities)

      for {metabolite_id, entry} <- phenotype.substrate_affinities do
        assert is_integer(metabolite_id) and metabolite_id in 0..12,
               "metabolite_id #{metabolite_id} out of 0..12"

        assert Map.has_key?(entry, :km) and Map.has_key?(entry, :kcat),
               "substrate_affinity entry missing :km or :kcat: #{inspect(entry)}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Unit tests: specific genome compositions

  test "genome with only substrate_binding domains → base_growth_rate == 0.1 (default)" do
    # No catalytic_site domains → default base_growth_rate = 0.1
    # Type 0 = :substrate_binding → type_tag sum rem 11 = 0 → [0, 0, 0]
    domain = Domain.new([0, 0, 0], List.duplicate(5, 20))
    gene = Gene.from_domains([domain])
    genome = Genome.new([gene])

    phenotype = Phenotype.from_genome(genome)
    assert phenotype.base_growth_rate == 0.1
  end

  test "genome with catalytic_site domain of kcat ≈ 1.0 → base_growth_rate ≈ 1.0" do
    # catalytic_site with all-max parameter_codons: norm ≈ 1.0 → kcat = 10.0
    # clamped to 1.0 as base_growth_rate.
    # Type 1 = :catalytic_site → type_tag [0, 0, 1]
    domain = Domain.new([0, 0, 1], List.duplicate(19, 20))
    assert domain.type == :catalytic_site
    # kcat = norm * 10.0, norm = min(raw_sum/500, 1.0) ≈ 1.0 for all-19 codons
    assert domain.params.kcat > 9.0

    gene = Gene.from_domains([domain])
    genome = Genome.new([gene])

    phenotype = Phenotype.from_genome(genome)
    # base_growth_rate = mean([kcat]) clamped to 1.0 → 1.0
    assert phenotype.base_growth_rate == 1.0
  end

  test "genome with zero-kcat catalytic_site → base_growth_rate == 0.0" do
    # All-zero parameter_codons → raw_sum = 0 → norm = 0 → kcat = 0.0
    domain = Domain.new([0, 0, 1], List.duplicate(0, 20))
    assert domain.type == :catalytic_site
    assert domain.params.kcat == 0.0

    gene = Gene.from_domains([domain])
    genome = Genome.new([gene])

    phenotype = Phenotype.from_genome(genome)
    assert phenotype.base_growth_rate == 0.0
  end

  test "genome with no repair_fidelity domains → repair_efficiency == 0.5 (default)" do
    # Only substrate_binding domains, no repair_fidelity
    domain = Domain.new([0, 0, 0], List.duplicate(5, 20))
    gene = Gene.from_domains([domain])
    genome = Genome.new([gene])

    phenotype = Phenotype.from_genome(genome)
    assert phenotype.repair_efficiency == 0.5
  end

  test "genome with no structural_fold domains → structural_stability == 0.5 (default)" do
    domain = Domain.new([0, 0, 0], List.duplicate(5, 20))
    gene = Gene.from_domains([domain])
    genome = Genome.new([gene])

    phenotype = Phenotype.from_genome(genome)
    assert phenotype.structural_stability == 0.5
  end

  test "genome with no energy_coupling domains → energy_cost == 0.0" do
    domain = Domain.new([0, 0, 0], List.duplicate(5, 20))
    gene = Gene.from_domains([domain])
    genome = Genome.new([gene])

    phenotype = Phenotype.from_genome(genome)
    assert phenotype.energy_cost == 0.0
  end

  test "genome with transmembrane_anchor domain → n_transmembrane >= 1" do
    # Type 2 = :transmembrane_anchor → type_tag sum rem 11 = 2 → [0, 0, 2]
    domain = Domain.new([0, 0, 2], List.duplicate(5, 20))
    assert domain.type == :transmembrane_anchor

    gene = Gene.from_domains([domain])
    genome = Genome.new([gene])

    phenotype = Phenotype.from_genome(genome)
    assert phenotype.n_transmembrane >= 1
  end

  test "genome with surface_tag domain → surface_tags contains a valid atom" do
    # Type 9 = :surface_tag → type_tag sum rem 11 = 9 → [0, 0, 9]
    domain = Domain.new([0, 0, 9], List.duplicate(5, 20))
    assert domain.type == :surface_tag

    gene = Gene.from_domains([domain])
    genome = Genome.new([gene])

    phenotype = Phenotype.from_genome(genome)
    assert length(phenotype.surface_tags) == 1
    assert hd(phenotype.surface_tags) in [:pilus_receptor, :phage_receptor, :surface_antigen]
  end

  test "genome with substrate_binding domain → substrate_affinities has one entry" do
    # substrate_binding: type 0, type_tag [0,0,0]
    domain = Domain.new([0, 0, 0], List.duplicate(10, 20))
    assert domain.type == :substrate_binding

    gene = Gene.from_domains([domain])
    genome = Genome.new([gene])

    phenotype = Phenotype.from_genome(genome)
    assert map_size(phenotype.substrate_affinities) == 1

    metabolite_id = domain.params.target_metabolite_id
    entry = Map.fetch!(phenotype.substrate_affinities, metabolite_id)
    assert entry.km == domain.params.km
  end

  test "multiple substrate_binding domains for same metabolite_id → last one wins" do
    # Two substrate_binding domains sharing the same first codon (0) → same
    # target_metabolite_id = rem(0, 13) = 0. The last domain in gene order wins.
    # We vary only codons 1..19 to change raw_sum while keeping first codon = 0.
    codons1 = [0 | List.duplicate(1, 19)]
    codons2 = [0 | List.duplicate(10, 19)]

    domain1 = Domain.new([0, 0, 0], codons1)
    domain2 = Domain.new([0, 0, 0], codons2)

    assert domain1.type == :substrate_binding
    assert domain2.type == :substrate_binding
    assert domain1.params.target_metabolite_id == 0
    assert domain2.params.target_metabolite_id == 0

    gene = Gene.from_domains([domain1, domain2])
    genome = Genome.new([gene])

    phenotype = Phenotype.from_genome(genome)
    entry = Map.fetch!(phenotype.substrate_affinities, 0)

    # domain2 appears last in gene order → its km wins
    assert_in_delta entry.km, domain2.params.km, 0.001
  end
end
