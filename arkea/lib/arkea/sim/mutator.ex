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
  alias Arkea.Sim.Intergenic

  @domain_size 23

  @base_rate 0.01
  @divisor 50.0
  @max_probability 0.95

  # Phase 17 — SOS response and error catastrophe (DESIGN.md Block 8).
  #
  # `dna_damage` accumulates with every mutational event scaled by the
  # genome size and inverse repair efficiency, mirroring the in vivo
  # observation that error-prone polymerases (DinB, Pol II, Pol V)
  # become active when DNA damage saturates the repair pool. SOS is
  # thresholded — below the threshold mutation rates and prophage
  # induction return to baseline; above, the polymerase activation
  # multiplies µ by `@sos_mutation_amplifier`.
  #
  # The error-catastrophe ceiling on µ is set by the Eigen quasispecies
  # criterion: replication is sustainable only when `µ × genome_size <
  # ~1`. Above the critical product, almost every offspring carries at
  # least one lethal mutation. Phase 17 implements the soft boundary:
  # spawn rolls ignored above `@critical_mu_per_gene` × genome_size.
  @dna_damage_decay 0.10
  @sos_active_threshold 0.50
  @sos_mutation_amplifier 4.0
  @sos_induction_amplifier 3.0
  @critical_mu_per_gene 0.20

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
  def generate(%Genome{chromosome: chromosome} = genome, rng) when chromosome != [] do
    {type, rng1} = sample_type(genome, rng)
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
    mutation_probability(abundance, repair_efficiency, 0.0)
  end

  @doc """
  SOS-aware mutation probability (Phase 17 — DESIGN.md Block 8).

  When the lineage's accumulated `dna_damage` crosses `@sos_active_threshold`,
  the per-cell mutation rate is amplified by `@sos_mutation_amplifier`
  (DinB-like error-prone polymerase activation). Below the threshold the
  formula reduces to `mutation_probability/2`.

  Pure.
  """
  @spec mutation_probability(non_neg_integer(), float(), float()) :: float()
  def mutation_probability(0, _repair_efficiency, _dna_damage), do: 0.0

  def mutation_probability(abundance, repair_efficiency, dna_damage)
      when is_integer(abundance) and abundance > 0 and is_float(repair_efficiency) and
             is_float(dna_damage) do
    sos_mult = if sos_active?(dna_damage), do: @sos_mutation_amplifier, else: 1.0
    mu = @base_rate * (1.0 - repair_efficiency) * sos_mult
    raw = mu * abundance / @divisor
    raw |> max(0.0) |> min(@max_probability)
  end

  @doc """
  True when the SOS response is active for the given dna_damage value.
  """
  @spec sos_active?(float()) :: boolean()
  def sos_active?(dna_damage) when is_float(dna_damage),
    do: dna_damage >= @sos_active_threshold

  @doc "SOS-active threshold (exposed for tests / docs)."
  def sos_active_threshold, do: @sos_active_threshold

  @doc "Per-tick decay applied to `dna_damage` independent of new accumulation."
  def dna_damage_decay, do: @dna_damage_decay

  @doc "Mutation-rate multiplier when SOS is active."
  def sos_mutation_amplifier, do: @sos_mutation_amplifier

  @doc "Prophage-induction multiplier when SOS is active."
  def sos_induction_amplifier, do: @sos_induction_amplifier

  @doc """
  Per-tick increment of `dna_damage`, scaled to a per-cell rate.

  Models the in vivo observation that DNA damage tracks mutation
  rate, replication intensity, and inverse repair capacity:

      damage_increment ∝ µ_baseline × growth_rate × (1 - repair_efficiency)

  `growth_rate` is `replications / max(abundance, 1)` — the per-cell
  replication probability. Normalising to a per-cell rate keeps the
  damage magnitudes comparable across small and large populations:
  a 200-cell colony growing at 30 % per tick accumulates the same
  per-tick damage as a 20-cell colony at the same growth rate.
  Without this normalisation, populous colonies saturate the SOS
  threshold within one or two ticks regardless of mutator status,
  which is biologically wrong.

  Returns a non-negative float. Damage compounds when SOS is already
  active (DinB-like polymerases lengthen the per-replication error
  count); the multiplier surfaces the runaway-mutator feedback loop
  that selection then has to neutralise.
  """
  @spec dna_damage_increment(float(), non_neg_integer(), non_neg_integer(), float()) :: float()
  def dna_damage_increment(repair_efficiency, replications, abundance, current_damage)
      when is_float(repair_efficiency) and is_integer(replications) and replications >= 0 and
             is_integer(abundance) and abundance >= 0 and is_float(current_damage) do
    if abundance == 0 or replications == 0 do
      0.0
    else
      growth_rate = replications / abundance
      base = @base_rate * growth_rate * (1.0 - clamp(repair_efficiency, 0.0, 1.0))
      if sos_active?(current_damage), do: base * 1.5, else: base
    end
  end

  @doc """
  Backwards-compatible 3-arg form (Phase 17 internal): infers a
  per-cell rate from `replications` only when `abundance` is
  unavailable; falls back to a coarse `replications/100` as the
  growth-rate proxy. Prefer the 4-arg form whenever possible.
  """
  @spec dna_damage_increment(float(), non_neg_integer(), float()) :: float()
  def dna_damage_increment(repair_efficiency, replications, current_damage),
    do: dna_damage_increment(repair_efficiency, replications, max(replications * 5, 1), current_damage)

  @doc """
  Apply per-tick decay to a `dna_damage` value, clamped at 0.
  """
  @spec decay_damage(float()) :: float()
  def decay_damage(damage) when is_float(damage) do
    (damage - @dna_damage_decay) |> max(0.0)
  end

  @doc """
  Error-catastrophe lethality probability for a freshly produced
  offspring, given the lineage's per-cell mutation rate `µ` and its
  genome size.

  Per Eigen's quasispecies result, `µ × genome_size > 1` means almost
  every replication produces at least one lethal mutation. Phase 17
  encodes the soft boundary as

      p_lethal = 1 - (1 - µ_critical_share)^genome_size
      where µ_critical_share = max(0, µ × genome_size - 1) / genome_size

  Returns 0 below the threshold; saturates near 1 well above.
  """
  @spec error_catastrophe_lethality(float(), pos_integer()) :: float()
  def error_catastrophe_lethality(mu, genome_size)
      when is_float(mu) and is_integer(genome_size) and genome_size > 0 do
    product = mu * genome_size

    if product <= 1.0 do
      0.0
    else
      share = (product - 1.0) / genome_size
      raw = 1.0 - :math.pow(1.0 - share, genome_size)
      raw |> max(0.0) |> min(1.0)
    end
  end

  @doc "Per-gene µ ceiling above which error catastrophe sets in."
  def critical_mu_per_gene, do: @critical_mu_per_gene

  defp clamp(value, lo, hi), do: value |> max(lo) |> min(hi)

  # ---------------------------------------------------------------------------
  # Private — type sampling

  # Sample a mutation type according to the cumulative weight table.
  # Returns {type_atom, new_rng}.
  defp sample_type(genome, rng) do
    type_weights = type_weights_for(genome)
    {n, rng1} = :rand.uniform_s(100, rng)

    type =
      Enum.find_value(type_weights, :substitution, fn {threshold, t} -> n <= threshold && t end)

    {type, rng1}
  end

  defp type_weights_for(%Genome{} = genome) do
    duplication_bonus = Intergenic.duplication_bonus(genome)
    substitution_weight = 70 - duplication_bonus
    duplication_weight = 8 + duplication_bonus

    [
      {substitution_weight, :substitution},
      {substitution_weight + 15, :indel},
      {substitution_weight + 15 + duplication_weight, :duplication},
      {substitution_weight + 15 + duplication_weight + 5, :inversion},
      {100, :translocation}
    ]
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
    {gene, rng1} = pick_weighted_random(chromosome, &Intergenic.duplication_weight/1, rng)
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

  defp pick_weighted_random(list, weight_fun, rng) when is_list(list) and list != [] do
    weighted =
      Enum.map(list, fn item ->
        {item, max(weight_fun.(item), 1)}
      end)

    total_weight = Enum.sum_by(weighted, fn {_item, weight} -> weight end)
    {n, rng1} = :rand.uniform_s(total_weight, rng)

    item =
      Enum.reduce_while(weighted, n, fn {candidate, weight}, remaining ->
        if remaining <= weight do
          {:halt, candidate}
        else
          {:cont, remaining - weight}
        end
      end)

    {item, rng1}
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
