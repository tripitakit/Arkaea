defmodule Arkea.Views.AncestralReconstruction do
  @moduledoc """
  Pure view-model for the ancestral-state trajectory along a
  lineage chain (Phase 26 / 3.6 + 3.7).

  Given a population of `Lineage.t()` and a target lineage id,
  walks the `parent_id` chain to surface the ordered list of
  ancestors (target → root) and a per-ancestor snapshot of the
  genome at that node:

    * **3.6 (genome-level)** — `genome_trace/2` returns one entry
      per ancestor with the chromosome / plasmid / prophage gene
      counts and a stable digest, so the consumer can render a
      "history of changes in genome composition" timeline.
    * **3.7 (sequence-level)** — `gene_trace/3` walks the same
      chain and surfaces, for a gene identified by its
      chromosome position at the target node, the codon
      sequence + domain summary at every ancestor that still
      has a gene at that position. Best-effort *positional*
      tracking: a transposition or gene-loss event upstream
      breaks the trace and we surface a `:lost` marker rather
      than fabricating a reconstruction.

  ## What this view is NOT

  This is **not** a phylogenetic ancestral-character
  reconstruction (Felsenstein 1981, Yang 1997). True
  reconstruction infers the most likely state at *unsampled*
  internal nodes from the observed states at the leaves under
  a substitution model — that is a separate, heavier
  computation that requires a calibrated mutation model and a
  rooted tree.

  Instead this view exploits the fact that Arkea retains the
  full lineage chain *with stored ancestor genomes* — every
  ancestral lineage that is still resident (or that was
  persisted) carries its genome explicitly, so "reconstruction"
  reduces to a walk + projection. When an ancestor has been
  delta-encoded (`genome: nil`), the entry is surfaced with
  `genome: nil` rather than rebuilt — runtime delta replay is
  out of scope for the view layer (a future tranche could plug
  in `Mutation.apply/2` here, but it would require the
  reference-genome resolution machinery, which lives in the
  ledger).

  ## Output shapes

      %{
        target_id: ...,
        depth: K,
        ancestors: [%{lineage_id, parent_id, tick, generation,
                      genome_present?, gene_count}, ...]
      }

      %{
        target_id: ...,
        gene_chromosome_index: i,
        depth: K,
        trace: [%{lineage_id, tick, generation, codons, type,
                  params, status: :present | :lost | :delta_only}, ...]
      }
  """

  alias Arkea.Ecology.Lineage
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene

  @type ancestor_entry :: %{
          lineage_id: String.t(),
          parent_id: String.t() | nil,
          tick: non_neg_integer(),
          generation: non_neg_integer(),
          genome_present?: boolean(),
          gene_count: non_neg_integer() | nil,
          plasmid_count: non_neg_integer(),
          prophage_count: non_neg_integer()
        }

  @type genome_trace :: %{
          target_id: String.t(),
          depth: non_neg_integer(),
          ancestors: [ancestor_entry()]
        }

  @type gene_entry :: %{
          lineage_id: String.t(),
          tick: non_neg_integer(),
          generation: non_neg_integer(),
          status: :present | :lost | :delta_only,
          codons: [integer()] | nil,
          type: atom() | nil,
          params: map() | nil
        }

  @type gene_trace :: %{
          target_id: String.t(),
          gene_chromosome_index: non_neg_integer(),
          depth: non_neg_integer(),
          trace: [gene_entry()]
        }

  @doc """
  Build the ancestor chain (target → root) for `target_id`.
  Returns `:not_found` if the target is not in the population.
  """
  @spec lineage_chain([Lineage.t()], String.t()) :: [Lineage.t()] | :not_found
  def lineage_chain(lineages, target_id) when is_list(lineages) and is_binary(target_id) do
    by_id = Map.new(lineages, &{&1.id, &1})

    case Map.get(by_id, target_id) do
      nil -> :not_found
      target -> walk_up(target, by_id, [])
    end
  end

  @doc """
  Genome-level ancestral trace (3.6). Returns one entry per
  ancestor in target → root order, surfacing gene-count and
  replicon counts. Lineages with `genome: nil` are reported
  with `genome_present?: false` and `gene_count: nil`.
  """
  @spec genome_trace([Lineage.t()], String.t()) :: genome_trace() | :not_found
  def genome_trace(lineages, target_id) when is_list(lineages) and is_binary(target_id) do
    case lineage_chain(lineages, target_id) do
      :not_found ->
        :not_found

      chain ->
        ancestors =
          chain
          |> Enum.with_index()
          |> Enum.map(fn {l, generations_back} ->
            %{
              lineage_id: l.id,
              parent_id: l.parent_id,
              tick: l.created_at_tick,
              generation: generations_back,
              genome_present?: not is_nil(l.genome),
              gene_count: gene_count(l.genome),
              plasmid_count: replicon_count(l.genome, :plasmids),
              prophage_count: replicon_count(l.genome, :prophages)
            }
          end)

        %{
          target_id: target_id,
          depth: length(ancestors),
          ancestors: ancestors
        }
    end
  end

  @doc """
  Sequence-level ancestral trace (3.7) for the chromosome gene
  at position `gene_chromosome_index` at the target node.

  The "same gene" is identified positionally — at every
  ancestor we look at chromosome[gene_chromosome_index]. If the
  ancestor's chromosome is shorter, the entry is `:lost`; if
  the ancestor is delta-only, the entry is `:delta_only`.
  """
  @spec gene_trace([Lineage.t()], String.t(), non_neg_integer()) ::
          gene_trace() | :not_found
  def gene_trace(lineages, target_id, gene_chromosome_index)
      when is_list(lineages) and is_binary(target_id) and is_integer(gene_chromosome_index) and
             gene_chromosome_index >= 0 do
    case lineage_chain(lineages, target_id) do
      :not_found ->
        :not_found

      chain ->
        trace =
          chain
          |> Enum.with_index()
          |> Enum.map(fn {l, generations_back} ->
            entry_for_gene(l, gene_chromosome_index, generations_back)
          end)

        %{
          target_id: target_id,
          gene_chromosome_index: gene_chromosome_index,
          depth: length(trace),
          trace: trace
        }
    end
  end

  defp walk_up(%Lineage{parent_id: nil} = l, _by_id, acc), do: Enum.reverse([l | acc])

  defp walk_up(%Lineage{parent_id: pid} = l, by_id, acc) do
    case Map.get(by_id, pid) do
      nil -> Enum.reverse([l | acc])
      parent -> walk_up(parent, by_id, [l | acc])
    end
  end

  defp gene_count(nil), do: nil
  defp gene_count(%Genome{gene_count: n}), do: n

  defp replicon_count(nil, _), do: 0
  defp replicon_count(%Genome{} = g, :plasmids), do: length(g.plasmids)
  defp replicon_count(%Genome{} = g, :prophages), do: length(g.prophages)

  defp entry_for_gene(%Lineage{} = l, idx, generation) do
    base = %{
      lineage_id: l.id,
      tick: l.created_at_tick,
      generation: generation
    }

    case l.genome do
      nil ->
        Map.merge(base, %{status: :delta_only, codons: nil, type: nil, params: nil})

      %Genome{chromosome: chromosome} ->
        case Enum.at(chromosome, idx) do
          nil ->
            Map.merge(base, %{status: :lost, codons: nil, type: nil, params: nil})

          %Gene{} = gene ->
            Map.merge(base, gene_summary(gene))
        end
    end
  end

  defp gene_summary(%Gene{codons: codons, domains: domains}) do
    {type, params} =
      case domains do
        [%Domain{type: t, params: p} | _] -> {t, p}
        _ -> {nil, nil}
      end

    %{status: :present, codons: codons, type: type, params: params}
  end
end
