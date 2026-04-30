defmodule Arkea.Sim.MutatorTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Genome.Mutation
  alias Arkea.Sim.Mutator

  @moduletag :sim

  # ---------------------------------------------------------------------------
  # Helpers

  defp gene_with_n_domains(n) do
    domains = Enum.map(1..n, fn _ -> Domain.new([0, 0, 0], List.duplicate(0, 20)) end)
    Gene.from_domains(domains)
  end

  defp single_gene_genome(n_domains) do
    Genome.new([gene_with_n_domains(n_domains)])
  end

  defp two_gene_genome do
    g1 = gene_with_n_domains(2)
    g2 = gene_with_n_domains(2)
    Genome.new([g1, g2])
  end

  defp fresh_rng do
    Mutator.init_seed("test-biotope-seed")
  end

  # ---------------------------------------------------------------------------
  # Unit: mutation_probability edge cases

  test "mutation_probability(0, _) == 0.0" do
    assert Mutator.mutation_probability(0, 0.5) == 0.0
    assert Mutator.mutation_probability(0, 0.0) == 0.0
    assert Mutator.mutation_probability(0, 1.0) == 0.0
  end

  test "mutation_probability is capped at 0.95 for high abundance + zero repair" do
    # µ = 0.01 * 1.0 = 0.01; P = 0.01 * 10_000 / 50.0 = 2.0 → capped at 0.95
    result = Mutator.mutation_probability(10_000, 0.0)
    assert result == 0.95
  end

  test "mutation_probability is 0.0 for any abundance with repair_efficiency == 1.0" do
    # µ = 0.01 * (1.0 - 1.0) = 0.0 → P = 0.0
    assert Mutator.mutation_probability(100, 1.0) == 0.0
    assert Mutator.mutation_probability(1_000, 1.0) == 0.0
  end

  test "mutation_probability is monotonically non-decreasing with abundance" do
    prob_100 = Mutator.mutation_probability(100, 0.5)
    prob_200 = Mutator.mutation_probability(200, 0.5)
    prob_1000 = Mutator.mutation_probability(1000, 0.5)

    assert prob_100 <= prob_200
    assert prob_200 <= prob_1000
  end

  # ---------------------------------------------------------------------------
  # Property: generate/2 always returns valid mutations

  property "Mutator.generate returns a mutation that passes Mutation.valid?" do
    check all(
            seed <- StreamData.integer(1..1_000_000),
            n_domains <- StreamData.integer(2..5),
            n_genes <- StreamData.integer(1..3)
          ) do
      rng = :rand.seed_s(:exsss, {seed, seed + 1, seed + 2})

      genes = Enum.map(1..n_genes, fn _ -> gene_with_n_domains(n_domains) end)
      genome = Genome.new(genes)

      case Mutator.generate(genome, rng) do
        {:ok, mutation, _new_rng} ->
          assert Mutation.valid?(mutation),
                 "Generated mutation is not valid?: #{inspect(mutation)}"

        {:skip, _new_rng} ->
          # Skip is acceptable when the genome is too small
          :ok
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Property: mutation type distribution roughly matches weights

  test "substitution type accounts for ~70% of generated mutations (±20%)" do
    genome = single_gene_genome(3)
    rng = fresh_rng()
    n_samples = 1000

    {counts, _rng} =
      Enum.reduce(1..n_samples, {%{}, rng}, fn _, {acc, r} ->
        case Mutator.generate(genome, r) do
          {:ok, mutation, r1} ->
            type = mutation_type(mutation)
            {Map.update(acc, type, 1, &(&1 + 1)), r1}

          {:skip, r1} ->
            {acc, r1}
        end
      end)

    total = Enum.sum(Map.values(counts))

    if total > 0 do
      sub_count = Map.get(counts, :substitution, 0)
      sub_fraction = sub_count / total

      assert sub_fraction >= 0.50,
             "Expected substitution ≥ 50%, got #{Float.round(sub_fraction * 100, 1)}%"

      assert sub_fraction <= 0.90,
             "Expected substitution ≤ 90%, got #{Float.round(sub_fraction * 100, 1)}%"
    end
  end

  # ---------------------------------------------------------------------------
  # Unit: init_seed is deterministic

  test "init_seed returns the same RNG state for the same biotope_id" do
    id = "test-biotope-abc"
    rng1 = Mutator.init_seed(id)
    rng2 = Mutator.init_seed(id)
    assert rng1 == rng2
  end

  test "init_seed returns different RNG states for different biotope_ids" do
    rng1 = Mutator.init_seed("biotope-a")
    rng2 = Mutator.init_seed("biotope-b")
    # Different seeds → different internal state
    refute rng1 == rng2
  end

  # ---------------------------------------------------------------------------
  # Unit: generate produces different mutations with single-gene and two-gene genomes

  test "generate works on a two-gene genome (translocation becomes possible)" do
    genome = two_gene_genome()
    rng = fresh_rng()

    results =
      Enum.map(1..50, fn _ ->
        {result, _} =
          Enum.reduce_while(1..20, {nil, rng}, fn _, {_acc, r} ->
            case Mutator.generate(genome, r) do
              {:ok, mutation, r1} -> {:halt, {{:ok, mutation}, r1}}
              {:skip, r1} -> {:cont, {nil, r1}}
            end
          end)

        result
      end)

    successful = Enum.filter(results, &(&1 != nil))
    assert successful != [], "Should produce at least one mutation in 50 attempts"
  end

  # ---------------------------------------------------------------------------
  # Private

  defp mutation_type(%Arkea.Genome.Mutation.Substitution{}), do: :substitution
  defp mutation_type(%Arkea.Genome.Mutation.Indel{}), do: :indel
  defp mutation_type(%Arkea.Genome.Mutation.Duplication{}), do: :duplication
  defp mutation_type(%Arkea.Genome.Mutation.Inversion{}), do: :inversion
  defp mutation_type(%Arkea.Genome.Mutation.Translocation{}), do: :translocation
end
