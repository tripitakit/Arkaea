defmodule Arkea.Genome.Mutation.Applicator do
  @moduledoc """
  Pure function `apply/2` that applies any of the five mutation types to a
  genome (Phase 4 — 03-IMPLEMENTATION-PLAN.md §5, Phase 4 deliverable).

  ## Phase 1 grammar invariant

  `Gene.from_codons/1` requires the codon count to be an exact positive
  multiple of 23 (the fixed Phase 1 domain width: 3 type-tag + 20 parameters).
  Every mutation in this module operates at **domain granularity** (23-codon
  boundaries) to preserve this invariant.  After modifying a gene's codons the
  module re-parses it with `Gene.reparse/1` so that `gene.domains` remains
  consistent with `gene.codons`.

  The mutated gene keeps its original `id` — gene identity is stable across
  mutations (the id tracks provenance, not sequence).

  ## Error values

  - `{:error, :invalid_target}` — `gene_id` not found in the genome.
  - `{:error, :gene_too_short}` — deletion or translocation source would leave
    fewer than one domain (< 23 codons) in the gene.
  """

  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Genome.Mutation.Duplication
  alias Arkea.Genome.Mutation.Indel
  alias Arkea.Genome.Mutation.Inversion
  alias Arkea.Genome.Mutation.Substitution
  alias Arkea.Genome.Mutation.Translocation

  @domain_size 23

  @doc """
  Apply a mutation to a genome.

  Returns `{:ok, new_genome}` on success or `{:error, reason}` on failure.
  The original genome is never mutated (pure).
  """
  @spec apply(Genome.t(), Arkea.Genome.Mutation.t()) ::
          {:ok, Genome.t()} | {:error, atom()}
  def apply(%Genome{} = genome, %Substitution{} = m) do
    find_and_update_gene(genome, m.gene_id, fn gene ->
      new_codons = List.replace_at(gene.codons, m.position, m.new_codon)
      reparse_gene(gene, new_codons)
    end)
  end

  def apply(%Genome{} = genome, %Indel{kind: :insertion} = m) do
    find_and_update_gene(genome, m.gene_id, fn gene ->
      {before, after_} = Enum.split(gene.codons, m.position)
      new_codons = before ++ m.codons ++ after_
      reparse_gene(gene, new_codons)
    end)
  end

  def apply(%Genome{} = genome, %Indel{kind: :deletion} = m) do
    find_and_update_gene(genome, m.gene_id, fn gene ->
      n_codons = length(gene.codons)

      if n_codons - length(m.codons) < @domain_size do
        {:error, :gene_too_short}
      else
        {before, rest} = Enum.split(gene.codons, m.position)
        after_ = Enum.drop(rest, length(m.codons))
        new_codons = before ++ after_
        reparse_gene(gene, new_codons)
      end
    end)
  end

  def apply(%Genome{} = genome, %Duplication{} = m) do
    find_and_update_gene(genome, m.gene_id, fn gene ->
      # range_end is inclusive
      copied = Enum.slice(gene.codons, m.range_start..m.range_end)
      {before, after_} = Enum.split(gene.codons, m.insert_at)
      new_codons = before ++ copied ++ after_
      reparse_gene(gene, new_codons)
    end)
  end

  def apply(%Genome{} = genome, %Inversion{} = m) do
    find_and_update_gene(genome, m.gene_id, fn gene ->
      before = Enum.take(gene.codons, m.range_start)
      segment = Enum.slice(gene.codons, m.range_start..m.range_end)
      after_ = Enum.drop(gene.codons, m.range_end + 1)
      new_codons = before ++ Enum.reverse(segment) ++ after_
      reparse_gene(gene, new_codons)
    end)
  end

  def apply(%Genome{} = genome, %Translocation{} = m) do
    with {:ok, source_gene} <- find_gene(genome, m.source_gene_id),
         {:ok, dest_gene} <- find_gene(genome, m.dest_gene_id) do
      apply_translocation(genome, m, source_gene, dest_gene)
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers

  # Core logic for Translocation, extracted to keep apply/2 depth ≤ 2.
  defp apply_translocation(genome, m, source_gene, dest_gene) do
    {rs, re} = m.source_range
    n_source = length(source_gene.codons)

    if n_source - (re - rs + 1) < @domain_size do
      {:error, :gene_too_short}
    else
      build_translocated_genome(genome, m, source_gene, dest_gene, rs, re)
    end
  end

  defp build_translocated_genome(genome, m, source_gene, dest_gene, rs, re) do
    moved = Enum.slice(source_gene.codons, rs..re)
    new_src_codons = Enum.take(source_gene.codons, rs) ++ Enum.drop(source_gene.codons, re + 1)
    {dst_before, dst_after} = Enum.split(dest_gene.codons, m.dest_position)
    new_dst_codons = dst_before ++ moved ++ dst_after

    with {:ok, new_src} <- reparse_gene(source_gene, new_src_codons),
         {:ok, new_dst} <- reparse_gene(dest_gene, new_dst_codons) do
      {:ok, replace_two_genes(genome, m.source_gene_id, new_src, m.dest_gene_id, new_dst)}
    end
  end

  defp replace_two_genes(genome, src_id, new_src, dst_id, new_dst) do
    new_chromosome =
      Enum.map(genome.chromosome, fn g ->
        cond do
          g.id == src_id -> new_src
          g.id == dst_id -> new_dst
          true -> g
        end
      end)

    rebuild_genome(genome, new_chromosome)
  end

  # Find a gene by id, returning {:ok, gene} | {:error, :invalid_target}.
  defp find_gene(%Genome{chromosome: chr}, gene_id) do
    case Enum.find(chr, fn g -> g.id == gene_id end) do
      nil -> {:error, :invalid_target}
      gene -> {:ok, gene}
    end
  end

  # Find a gene in the chromosome, apply `fun` to it, replace it in the genome.
  # `fun` receives a `Gene.t()` and must return `{:ok, Gene.t()} | {:error, atom()}`.
  @spec find_and_update_gene(Genome.t(), binary(), (Gene.t() ->
                                                      {:ok, Gene.t()} | {:error, atom()})) ::
          {:ok, Genome.t()} | {:error, atom()}
  defp find_and_update_gene(%Genome{chromosome: chr} = genome, gene_id, fun) do
    case Enum.find_index(chr, fn g -> g.id == gene_id end) do
      nil ->
        {:error, :invalid_target}

      idx ->
        gene = Enum.at(chr, idx)

        case fun.(gene) do
          {:ok, new_gene} ->
            new_chr = List.replace_at(chr, idx, new_gene)
            {:ok, rebuild_genome(genome, new_chr)}

          {:error, _} = err ->
            err
        end
    end
  end

  # Re-parse a gene with new codons, preserving the original gene id.
  # Returns {:ok, gene} | {:error, atom()}.
  defp reparse_gene(%Gene{} = gene, new_codons) do
    case Gene.from_codons(new_codons) do
      {:ok, parsed} ->
        {:ok,
         %{
           parsed
           | id: gene.id,
             promoter_block: gene.promoter_block,
             regulatory_block: gene.regulatory_block,
             intergenic_blocks: gene.intergenic_blocks
         }}

      {:error, _} = err ->
        err
    end
  end

  # Rebuild the genome with a new chromosome, recomputing gene_count.
  defp rebuild_genome(%Genome{plasmids: p, prophages: pr}, new_chromosome) do
    Genome.new(new_chromosome, plasmids: p, prophages: pr)
  end

  # ---------------------------------------------------------------------------
  # Phase 26 / 1.13 + 1.14 — mutation-level audit-event detectors.
  #
  # `apply/2` stays pure and signature-stable; this companion helper
  # is the diff-derived event extractor that callers (Tick) invoke
  # after the mutation has been applied. Returns a list of typed
  # event maps ready for `BiotopeState.pending_events`.

  @typedoc "Audit-shape events that a successful mutation can fire."
  @type mutation_event ::
          %{
            type: :domain_flip,
            tick: non_neg_integer(),
            lineage_id: String.t() | nil,
            gene_id: String.t(),
            domain_index: non_neg_integer(),
            from_type: atom(),
            to_type: atom()
          }
          | %{
              type: :gene_chimera_birth,
              tick: non_neg_integer(),
              lineage_id: String.t() | nil,
              source_gene_id: String.t(),
              dest_gene_id: String.t(),
              codons_moved: non_neg_integer()
            }

  @doc """
  Compare an old / new genome pair plus the `mutation` that
  produced the change, and return the typed audit events the
  mutation surfaced. Pure, deterministic.

  ## What surfaces

  * **`:domain_flip`** — every position in a *substituted /
    indel'd / inverted gene* whose `Domain.type` changed
    between old and new. A single mutation can flip several
    domains at once (e.g. an inversion swapping two domains
    of different categories) — they all surface as separate
    events with the per-position `domain_index`.

  * **`:gene_chimera_birth`** — fires once whenever a
    `Translocation` succeeded: codons moved from one gene to
    another *always* produce a chimera at the molecular level
    (the destination gene now carries a sub-sequence that did
    not originate there). Carries `source_gene_id`,
    `dest_gene_id`, and `codons_moved`.

  Mutations that don't reshape categories (e.g. a substitution
  inside a `parameter_codon` window — drift only, no
  type_tag flip) return `[]`.

  Other arguments: `tick` is stamped on every event;
  `lineage_id` is optional — the caller can leave it `nil` and
  patch it after spawning the child lineage if it's not
  available at detection time.
  """
  @spec detect_mutation_events(
          Genome.t(),
          Genome.t(),
          Arkea.Genome.Mutation.t(),
          keyword()
        ) :: [mutation_event()]
  def detect_mutation_events(old_genome, new_genome, mutation, opts \\ [])

  def detect_mutation_events(%Genome{} = old, %Genome{} = new, %Translocation{} = m, opts) do
    {rs, re} = m.source_range
    codons_moved = max(re - rs + 1, 0)

    chimera_event = %{
      type: :gene_chimera_birth,
      tick: Keyword.get(opts, :tick, 0),
      lineage_id: Keyword.get(opts, :lineage_id),
      source_gene_id: m.source_gene_id,
      dest_gene_id: m.dest_gene_id,
      codons_moved: codons_moved
    }

    # The translocation can also flip domain types in either the
    # source (truncation may shift type tags) or the destination
    # (insertion mid-domain may reframe a tag). Detect both.
    flip_events =
      collect_domain_flips(old, new, [m.source_gene_id, m.dest_gene_id], opts)

    [chimera_event | flip_events]
  end

  def detect_mutation_events(%Genome{} = old, %Genome{} = new, mutation, opts) do
    gene_id = mutation_gene_id(mutation)

    if is_nil(gene_id) do
      []
    else
      collect_domain_flips(old, new, [gene_id], opts)
    end
  end

  defp mutation_gene_id(%Substitution{gene_id: id}), do: id
  defp mutation_gene_id(%Indel{gene_id: id}), do: id
  defp mutation_gene_id(%Inversion{gene_id: id}), do: id
  defp mutation_gene_id(%Duplication{gene_id: id}), do: id
  defp mutation_gene_id(_), do: nil

  defp collect_domain_flips(%Genome{} = old, %Genome{} = new, gene_ids, opts) do
    tick = Keyword.get(opts, :tick, 0)
    lineage_id = Keyword.get(opts, :lineage_id)

    old_by_id = Map.new(old.chromosome, fn g -> {g.id, g} end)
    new_by_id = Map.new(new.chromosome, fn g -> {g.id, g} end)

    Enum.flat_map(gene_ids, fn gid ->
      with %Gene{domains: old_doms} <- Map.get(old_by_id, gid),
           %Gene{domains: new_doms} <- Map.get(new_by_id, gid) do
        flips_for_gene(gid, old_doms, new_doms, tick, lineage_id)
      else
        _ -> []
      end
    end)
  end

  defp flips_for_gene(gene_id, old_doms, new_doms, tick, lineage_id) do
    # Compare domain-by-domain at the same index; the shorter list
    # truncates the diff (an indel that drops a domain doesn't fire
    # a "phantom flip" — that's covered separately by the future
    # `:domain_loss` audit event).
    pairs = Enum.zip(old_doms, new_doms)

    pairs
    |> Enum.with_index()
    |> Enum.flat_map(fn {{%Domain{type: from_t}, %Domain{type: to_t}}, idx} ->
      if from_t == to_t do
        []
      else
        [
          %{
            type: :domain_flip,
            tick: tick,
            lineage_id: lineage_id,
            gene_id: gene_id,
            domain_index: idx,
            from_type: from_t,
            to_type: to_t
          }
        ]
      end
    end)
  end
end
