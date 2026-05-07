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
  alias Arkea.Sim.Metabolism
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

  property "substrate_affinities keys are canonical metabolite atoms" do
    # Phase 5: integer target_metabolite_id (0..12) is converted to the
    # canonical atom key (:glucose, :acetate, … :po4) by from_genome/1 via
    # Arkea.Sim.Metabolism.metabolite_atom/1.
    valid_metabolite_atoms = Metabolism.canonical_metabolites()

    check all(g <- genome(), max_runs: 150) do
      phenotype = Phenotype.from_genome(g)
      assert is_map(phenotype.substrate_affinities)

      for {metabolite_atom, entry} <- phenotype.substrate_affinities do
        assert is_atom(metabolite_atom) and metabolite_atom in valid_metabolite_atoms,
               "metabolite atom #{metabolite_atom} not in canonical list"

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

  test "genome with substrate_binding domain → substrate_affinities has one atom-keyed entry" do
    # substrate_binding: type 0, type_tag [0,0,0]
    # first_codon of parameter_codons = 0 → target_metabolite_id = rem(0, 13) = 0 → :glucose
    # Use [0 | rest] to ensure first_codon = 0.
    domain = Domain.new([0, 0, 0], [0 | List.duplicate(5, 19)])
    assert domain.type == :substrate_binding
    assert domain.params.target_metabolite_id == 0

    gene = Gene.from_domains([domain])
    genome = Genome.new([gene])

    phenotype = Phenotype.from_genome(genome)
    assert map_size(phenotype.substrate_affinities) == 1

    # Phase 5: key is now the canonical atom (:glucose for id 0), not integer 0
    entry = Map.fetch!(phenotype.substrate_affinities, :glucose)
    assert entry.km == domain.params.km
  end

  test "multiple substrate_binding domains for same metabolite_id → last one wins (atom key)" do
    # Two substrate_binding domains sharing first codon 0 → same
    # target_metabolite_id = rem(0, 13) = 0 → both map to :glucose.
    # The last domain in gene order wins.
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
    # Phase 5: key is :glucose (canonical atom for id 0), not integer 0
    entry = Map.fetch!(phenotype.substrate_affinities, :glucose)

    # domain2 appears last in gene order → its km wins
    assert_in_delta entry.km, domain2.params.km, 0.001
  end

  # ---------------------------------------------------------------------------
  # ribosome_like generative derivation (Block 5)

  describe "ribosome_like generative derivation (Block 5)" do
    # Helpers — codon constructions validated against Domain.new/2:
    #   - [0,0,8] type_tag → :structural_fold (sum 8, idx 8 in canonical list).
    #   - [0,0,1] type_tag → :catalytic_site  (sum 1, idx 1).
    #   - structural_fold params: multimerization_n = max(1, rem(sum_last_3, 8) + 1).
    #     all-5 codons → last_3 [5,5,5] sum 15 → rem 7 → +1 = 8.
    #     all-0 codons → last_3 [0,0,0] sum  0 → rem 0 → +1 = 1.
    #   - catalytic_site params: reaction_class = @reaction_classes[rem(sum_first_3, 6)],
    #     where @reaction_classes = [:hydrolysis, :oxidation, :reduction,
    #     :isomerization, :ligation, :lyase]. So first_3 sum 4 → :ligation,
    #     first_3 sum 0 → :hydrolysis.
    defp high_multimer_fold,
      do: Domain.new([0, 0, 8], List.duplicate(5, 20))

    defp low_multimer_fold,
      do: Domain.new([0, 0, 8], List.duplicate(0, 20))

    defp ligation_catalytic,
      do: Domain.new([0, 0, 1], [4, 0, 0 | List.duplicate(10, 17)])

    defp hydrolysis_catalytic,
      do: Domain.new([0, 0, 1], List.duplicate(10, 20))

    test "empty (chromosome-less) genome → ribosome_like == 0.0" do
      # Genome.new([]) is not allowed by chromosome invariants; build a
      # genome with a single non-ribosome gene to express "no proxy".
      gene = Gene.from_domains([Domain.new([0, 0, 0], List.duplicate(5, 20))])
      genome = Genome.new([gene])

      assert Phenotype.target_classes(genome).ribosome_like == 0.0
    end

    test "structural_fold alone (no ligation site) → ribosome_like == 0.0" do
      gene = Gene.from_domains([high_multimer_fold()])
      genome = Genome.new([gene])

      assert Phenotype.target_classes(genome).ribosome_like == 0.0
    end

    test "ligation site alone (no structural_fold) → ribosome_like == 0.0" do
      gene = Gene.from_domains([ligation_catalytic()])
      genome = Genome.new([gene])

      assert Phenotype.target_classes(genome).ribosome_like == 0.0
    end

    test "low-multimerization fold + ligation → ribosome_like == 0.0" do
      # multimerization_n = 1 fails the >= 4 threshold even with a
      # co-occurring ligation site.
      fold = low_multimer_fold()
      assert fold.type == :structural_fold
      assert fold.params.multimerization_n == 1

      gene = Gene.from_domains([fold, ligation_catalytic()])
      genome = Genome.new([gene])

      assert Phenotype.target_classes(genome).ribosome_like == 0.0
    end

    test "high-multimerization fold + non-ligation catalytic → ribosome_like == 0.0" do
      # The catalytic site is :hydrolysis here, not :ligation.
      catalytic = hydrolysis_catalytic()
      assert catalytic.params.reaction_class == :hydrolysis

      gene = Gene.from_domains([high_multimer_fold(), catalytic])
      genome = Genome.new([gene])

      assert Phenotype.target_classes(genome).ribosome_like == 0.0
    end

    test "both prongs co-occurring in one gene → ribosome_like > 0.0" do
      fold = high_multimer_fold()
      catalytic = ligation_catalytic()
      assert fold.params.multimerization_n >= 4
      assert catalytic.params.reaction_class == :ligation

      gene = Gene.from_domains([fold, catalytic])
      genome = Genome.new([gene])

      assert Phenotype.target_classes(genome).ribosome_like > 0.0
    end

    test "two ribosome-like genes → higher index, capped at ≤ 1.0" do
      ribo_gene1 = Gene.from_domains([high_multimer_fold(), ligation_catalytic()])
      ribo_gene2 = Gene.from_domains([high_multimer_fold(), ligation_catalytic()])

      single = Phenotype.target_classes(Genome.new([ribo_gene1])).ribosome_like
      double = Phenotype.target_classes(Genome.new([ribo_gene1, ribo_gene2])).ribosome_like

      assert double > single
      assert double <= 1.0
    end

    test "two prongs split across two genes → ribosome_like == 0.0 (must co-occur in one gene)" do
      # Block 5 invariant: the proxy must co-occur within the SAME gene,
      # not just within the same genome.
      fold_only = Gene.from_domains([high_multimer_fold()])
      catalytic_only = Gene.from_domains([ligation_catalytic()])
      genome = Genome.new([fold_only, catalytic_only])

      assert Phenotype.target_classes(genome).ribosome_like == 0.0
    end

    property "random genome without proxy → ribosome_like == 0.0; with proxy → > 0.0" do
      check all(g <- genome(), max_runs: 100) do
        # Negative direction: when the random genome contains no
        # ribosome-shaped gene (a single gene that simultaneously carries an
        # oligomeric `:structural_fold` and a `:ligation` `:catalytic_site`),
        # the proxy must read 0.0. When such a gene is present (rare but
        # possible), the proxy must read > 0.0.
        if Enum.any?(g.chromosome, &ribosome_like_gene?/1) do
          assert Phenotype.target_classes(g).ribosome_like > 0.0
        else
          assert Phenotype.target_classes(g).ribosome_like == 0.0
        end

        # Positive direction (augmentation): appending a guaranteed
        # ribosome-shaped gene must drive ribosome_like > 0.0 regardless of
        # the original genome.
        ribo_gene =
          Gene.from_domains([
            Domain.new([0, 0, 8], List.duplicate(5, 20)),
            Domain.new([0, 0, 1], [4, 0, 0 | List.duplicate(10, 17)])
          ])

        augmented = Genome.new(g.chromosome ++ [ribo_gene])
        assert Phenotype.target_classes(augmented).ribosome_like > 0.0
      end
    end
  end

  # Mirror of the private `ribosome_like?/1` predicate in
  # `Arkea.Sim.Phenotype` (lib/arkea/sim/phenotype.ex). Kept in sync so the
  # property test can pivot on the same shape the production code uses.
  defp ribosome_like_gene?(%Gene{domains: domains}) do
    has_oligomeric_fold =
      Enum.any?(domains, fn d ->
        d.type == :structural_fold and (d.params[:multimerization_n] || 1) >= 4
      end)

    has_ligation_site =
      Enum.any?(domains, fn d ->
        d.type == :catalytic_site and d.params[:reaction_class] == :ligation
      end)

    has_oligomeric_fold and has_ligation_site
  end
end
