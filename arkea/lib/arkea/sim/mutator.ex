defmodule Arkea.Sim.Mutator do
  @moduledoc """
  Pure stochastic mutation generator for Phase 4 (IMPLEMENTATION-PLAN.md §5).

  ## Responsibilities

  - `generate/2` — sample a valid `Mutation.t()` for a given `Genome.t()`,
    using a stateless BEAM `:rand` state for deterministic reproducibility.
  - `mutation_probability/2` — compute the per-tick probability that a lineage
    produces a mutant offspring.
  - `init_seed/1` — derive a deterministic initial RNG seed from a biotope id.

  ## Mutation type weights (DESIGN.md Block 5)

  | Type | Weight |
  |---|---|
  | Substitution | 70 % |
  | Indel | 15 % |
  | Duplication | 8 % |
  | Inversion | 5 % |
  | Translocation | 2 % |

  ## Mutation probability formula

      µ = base_rate * (1.0 - repair_efficiency)
      P = clamp(µ * abundance / divisor, 0.0, 0.95)

  With `base_rate = 0.01` and `divisor = 50.0`, an abundance of 100 and
  `repair_efficiency = 0.5` gives P ≈ 0.01, roughly 1 mutant per 5 ticks
  on average when many such lineages are processed.

  ## Domain-granularity invariant

  All generated mutations operate at 23-codon domain boundaries so that the
  Phase 1 grammar invariant (`Gene.from_codons/1` requires multiples of 23)
  is preserved when `Applicator.apply/2` is called.

  ## RNG discipline

  Uses `:rand.uniform_s/2` exclusively — pure, no global state. The RNG
  state is threaded through all calls as an explicit value that callers must
  store (in `BiotopeState.rng_seed`).
  """

  alias Arkea.Genome
  alias Arkea.Genome.Mutation.Duplication
  alias Arkea.Genome.Mutation.Indel
  alias Arkea.Genome.Mutation.Inversion
  alias Arkea.Genome.Mutation.Substitution
  alias Arkea.Genome.Mutation.Translocation

  @domain_size 23

  @base_rate 0.01
  @divisor 50.0
  @max_probability 0.95

  # Cumulative weights for mutation-type selection.
  # Layout: {cumulative_threshold, type_atom}
  # Thresholds must sum to 100.
  @type_weights [
    {70, :substitution},
    {85, :indel},
    {93, :duplication},
    {98, :inversion},
    {100, :translocation}
  ]

  @type rng_state :: :rand.state()

  @doc """
  Initialise a deterministic RNG seed from a biotope id string.

  Uses `:erlang.phash2/1` to fold the binary into an integer, then seeds
  the `:exsss` algorithm (Xoshiro256** — fast and well-distributed).

  Pure.
  """
  @spec init_seed(binary()) :: rng_state()
  def init_seed(biotope_id) when is_binary(biotope_id) do
    hash = :erlang.phash2(biotope_id)
    :rand.seed_s(:exsss, {hash, hash + 1, hash + 2})
  end

  @doc """
  Generate a valid mutation for the given genome using the given RNG state.

  Returns `{:ok, mutation, new_rng}` when a valid mutation is produced, or
  `{:skip, new_rng}` when the genome is structurally too small for the sampled
  mutation type (e.g. single-domain gene sampled for deletion).

  The genome's chromosome is the only source of genes for Phase 4. Plasmid
  and prophage mutations are Phase 6 scope.

  Pure.
  """
  @spec generate(Genome.t(), rng_state()) ::
          {:ok, Arkea.Genome.Mutation.t(), rng_state()} | {:skip, rng_state()}
  def generate(%Genome{chromosome: chromosome} = _genome, rng) when chromosome != [] do
    {type, rng1} = sample_type(rng)
    generate_of_type(type, chromosome, rng1)
  end

  @doc """
  Compute the probability that a lineage produces a mutant offspring this tick.

  Formula:

      µ = base_rate * (1.0 - repair_efficiency)
      P = clamp(µ * abundance / divisor, 0.0, 0.95)

  Returns `0.0` when `abundance == 0` regardless of repair_efficiency.

  Pure.
  """
  @spec mutation_probability(non_neg_integer(), float()) :: float()
  def mutation_probability(0, _repair_efficiency), do: 0.0

  def mutation_probability(abundance, repair_efficiency)
      when is_integer(abundance) and abundance > 0 and is_float(repair_efficiency) do
    mu = @base_rate * (1.0 - repair_efficiency)
    raw = mu * abundance / @divisor
    raw |> max(0.0) |> min(@max_probability)
  end

  # ---------------------------------------------------------------------------
  # Private — type sampling

  # Sample a mutation type according to the cumulative weight table.
  # Returns {type_atom, new_rng}.
  defp sample_type(rng) do
    {n, rng1} = :rand.uniform_s(100, rng)

    type =
      Enum.find_value(@type_weights, :substitution, fn {threshold, t} -> n <= threshold && t end)

    {type, rng1}
  end

  # ---------------------------------------------------------------------------
  # Private — per-type generation

  defp generate_of_type(:substitution, chromosome, rng) do
    {gene, rng1} = pick_random(chromosome, rng)
    {pos, rng2} = :rand.uniform_s(length(gene.codons), rng1)
    pos = pos - 1
    old_codon = Enum.at(gene.codons, pos)
    {new_codon, rng3} = pick_different_codon(old_codon, rng2)

    mutation = %Substitution{
      gene_id: gene.id,
      position: pos,
      old_codon: old_codon,
      new_codon: new_codon
    }

    {:ok, mutation, rng3}
  end

  defp generate_of_type(:indel, chromosome, rng) do
    {gene, rng1} = pick_random(chromosome, rng)
    {kind_n, rng2} = :rand.uniform_s(2, rng1)
    kind = if kind_n == 1, do: :insertion, else: :deletion

    case kind do
      :insertion ->
        n_domains = div(length(gene.codons), @domain_size)
        # pick a domain boundary (0..n_domains) as insertion point
        {boundary_idx, rng3} = :rand.uniform_s(n_domains + 1, rng2)
        position = (boundary_idx - 1) * @domain_size
        position = max(position, 0)
        {new_codons, rng4} = gen_codons(@domain_size, rng3)

        mutation = %Indel{
          gene_id: gene.id,
          position: position,
          kind: :insertion,
          codons: new_codons
        }

        {:ok, mutation, rng4}

      :deletion ->
        n_domains = div(length(gene.codons), @domain_size)

        if n_domains < 2 do
          {:skip, rng2}
        else
          # pick which domain to delete (0-indexed domain index)
          {dom_idx, rng3} = :rand.uniform_s(n_domains, rng2)
          dom_idx = dom_idx - 1
          position = dom_idx * @domain_size
          deleted = Enum.slice(gene.codons, position, @domain_size)

          mutation = %Indel{
            gene_id: gene.id,
            position: position,
            kind: :deletion,
            codons: deleted
          }

          {:ok, mutation, rng3}
        end
    end
  end

  defp generate_of_type(:duplication, chromosome, rng) do
    {gene, rng1} = pick_random(chromosome, rng)
    n_domains = div(length(gene.codons), @domain_size)
    {dom_idx, rng2} = :rand.uniform_s(n_domains, rng1)
    dom_idx = dom_idx - 1
    range_start = dom_idx * @domain_size
    range_end = range_start + @domain_size - 1

    # pick an insertion boundary different from the duplicated range
    {boundary_idx, rng3} = :rand.uniform_s(n_domains, rng2)
    boundary_idx = boundary_idx - 1
    # shift boundary past the copied domain to avoid degenerate overlap
    insert_at =
      if boundary_idx >= dom_idx,
        do: (boundary_idx + 1) * @domain_size,
        else: boundary_idx * @domain_size

    mutation = %Duplication{
      gene_id: gene.id,
      range_start: range_start,
      range_end: range_end,
      insert_at: insert_at
    }

    {:ok, mutation, rng3}
  end

  defp generate_of_type(:inversion, chromosome, rng) do
    {gene, rng1} = pick_random(chromosome, rng)
    n_domains = div(length(gene.codons), @domain_size)
    # pick 1..n_domains consecutive domains to invert
    {n_inv, rng2} = :rand.uniform_s(n_domains, rng1)
    max_start = n_domains - n_inv
    {start_dom, rng3} = :rand.uniform_s(max_start + 1, rng2)
    start_dom = start_dom - 1
    range_start = start_dom * @domain_size
    range_end = range_start + n_inv * @domain_size - 1

    mutation = %Inversion{
      gene_id: gene.id,
      range_start: range_start,
      range_end: range_end
    }

    {:ok, mutation, rng3}
  end

  defp generate_of_type(:translocation, chromosome, rng) do
    if length(chromosome) < 2 do
      {:skip, rng}
    else
      {src_gene, rng1} = pick_random(chromosome, rng)
      n_src_domains = div(length(src_gene.codons), @domain_size)

      if n_src_domains < 2 do
        {:skip, rng1}
      else
        # pick a different destination gene
        other_genes = Enum.reject(chromosome, fn g -> g.id == src_gene.id end)
        {dst_gene, rng2} = pick_random(other_genes, rng1)

        # pick a domain from source to move
        {dom_idx, rng3} = :rand.uniform_s(n_src_domains, rng2)
        dom_idx = dom_idx - 1
        rs = dom_idx * @domain_size
        re = rs + @domain_size - 1

        # pick a boundary in dest
        n_dst_domains = div(length(dst_gene.codons), @domain_size)
        {dst_boundary, rng4} = :rand.uniform_s(n_dst_domains + 1, rng3)
        dest_position = (dst_boundary - 1) * @domain_size
        dest_position = max(dest_position, 0)

        mutation = %Translocation{
          source_gene_id: src_gene.id,
          dest_gene_id: dst_gene.id,
          source_range: {rs, re},
          dest_position: dest_position
        }

        {:ok, mutation, rng4}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private — RNG helpers

  # Pick a random element from a non-empty list. Returns {element, new_rng}.
  defp pick_random(list, rng) when is_list(list) and list != [] do
    n = length(list)
    {idx, rng1} = :rand.uniform_s(n, rng)
    {Enum.at(list, idx - 1), rng1}
  end

  # Pick a codon different from `exclude`. Returns {codon, new_rng}.
  defp pick_different_codon(exclude, rng) do
    {c, rng1} = :rand.uniform_s(20, rng)
    codon = c - 1

    if codon == exclude do
      pick_different_codon(exclude, rng1)
    else
      {codon, rng1}
    end
  end

  # Generate `n` random codons (0..19). Returns {codons, new_rng}.
  defp gen_codons(0, rng), do: {[], rng}

  defp gen_codons(n, rng) when n > 0 do
    {c, rng1} = :rand.uniform_s(20, rng)
    {rest, rng2} = gen_codons(n - 1, rng1)
    {[c - 1 | rest], rng2}
  end
end
