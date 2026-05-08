defmodule Arkea.Genome.Operon do
  @moduledoc """
  Operon — coordinated transcriptional unit (Phase 25 / 7.2).

  An operon is a set of contiguous genes on the same chromosome
  that share a `Gene.operon_id` (binary tag). In bacteria
  operons are transcribed as a single polycistronic mRNA driven
  by the promoter of the *leader gene* (the first gene in the
  operon's order on the chromosome); regulatory inputs (sigma
  factors, repressors, riboswitches) on that leader gene
  modulate the expression of every downstream member at once.

  ## Phase 25 staging

  This module ships the *structural surface* (grouping helpers,
  membership predicates, leader-gene lookup) that downstream
  callers need. It is deliberately **pure** (no runtime sigma /
  no kcat scaling here) so the data model can be consumed by:

    * `Arkea.Sim.Phenotype.from_genome/1` — when the runtime
      coordination ships in the same phase, the operon view
      becomes the unit of σ-factor application.
    * `Arkea.Views.RegulatoryNetwork` — the UI builder that
      surfaces "gene X regulates operon Y" edges.
    * Future phylogeny views (operon dissolution as a salient
      mutation event).

  ## Identity

  Two genes belong to the same operon iff they share a
  non-`nil` `operon_id`. Stand-alone genes (`operon_id == nil`)
  are *not* grouped — they each form their own implicit
  one-gene operon at the runtime layer, but for the purposes of
  this module they show up under `solo_genes/1` rather than
  `operons/1`.

  Order is preserved as it appears in the chromosome: the leader
  gene is the *first* member of the operon in chromosome order,
  not the lowest UUID or the highest catalytic activity.
  """

  alias Arkea.Genome
  alias Arkea.Genome.Gene

  @type t :: %{
          id: String.t(),
          leader_gene_id: String.t(),
          gene_ids: [String.t()],
          gene_count: non_neg_integer()
        }

  @doc """
  Group the chromosome's genes by `operon_id`. Returns one entry
  per distinct operon, each carrying the leader-gene id (first
  occurrence in chromosome order) and the list of member gene
  ids in chromosome order.

  Genes with `operon_id == nil` are excluded — see
  `solo_genes/1` for those.
  """
  @spec operons(Genome.t()) :: [t()]
  def operons(%Genome{chromosome: chromosome}) do
    chromosome
    |> Enum.with_index()
    |> Enum.reduce({[], %{}}, fn {%Gene{} = gene, _idx}, {order, acc} ->
      case gene.operon_id do
        nil ->
          {order, acc}

        op_id ->
          case Map.get(acc, op_id) do
            nil ->
              entry = %{leader_gene_id: gene.id, gene_ids: [gene.id]}
              {order ++ [op_id], Map.put(acc, op_id, entry)}

            existing ->
              updated = %{existing | gene_ids: existing.gene_ids ++ [gene.id]}
              {order, Map.put(acc, op_id, updated)}
          end
      end
    end)
    |> finalise_operons()
  end

  @doc """
  List the chromosome's genes that do NOT belong to any operon
  (`operon_id == nil`). Returned in chromosome order.
  """
  @spec solo_genes(Genome.t()) :: [Gene.t()]
  def solo_genes(%Genome{chromosome: chromosome}) do
    Enum.filter(chromosome, fn %Gene{operon_id: id} -> is_nil(id) end)
  end

  @doc """
  Look up the operon entry that contains `gene_id`, or `nil` if
  the gene is solo / unknown.
  """
  @spec containing(Genome.t(), String.t()) :: t() | nil
  def containing(%Genome{} = genome, gene_id) when is_binary(gene_id) do
    Enum.find(operons(genome), fn op -> gene_id in op.gene_ids end)
  end

  @doc """
  True if two gene ids belong to the same operon. Two solo genes
  are *not* in the same operon (returns false).
  """
  @spec same_operon?(Genome.t(), String.t(), String.t()) :: boolean()
  def same_operon?(%Genome{} = genome, gene_id_a, gene_id_b)
      when is_binary(gene_id_a) and is_binary(gene_id_b) do
    case containing(genome, gene_id_a) do
      nil -> false
      %{gene_ids: ids} -> gene_id_b in ids
    end
  end

  @doc """
  Return the leader gene struct of `operon`, or `nil` if the
  leader is no longer present in the chromosome (e.g. transient
  state during a mutation that dropped the gene).
  """
  @spec leader_gene(Genome.t(), t()) :: Gene.t() | nil
  def leader_gene(%Genome{chromosome: chromosome}, %{leader_gene_id: leader_id}) do
    Enum.find(chromosome, fn %Gene{id: id} -> id == leader_id end)
  end

  defp finalise_operons({order, by_id}) do
    Enum.map(order, fn op_id ->
      %{leader_gene_id: leader_id, gene_ids: ids} = Map.fetch!(by_id, op_id)

      %{
        id: op_id,
        leader_gene_id: leader_id,
        gene_ids: ids,
        gene_count: length(ids)
      }
    end)
  end
end
