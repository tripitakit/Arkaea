defmodule Arkea.Views.MutationHotspot do
  @moduledoc """
  Pure view-model for the per-gene mutation hotspot map (Phase
  26 / 2.7).

  Given a gene (typically the descendant of interest) and the
  audit log entries that surface domain-level mutations
  (`:domain_flip`, `:gene_chimera_birth`) and lineage births
  (`:lineage_born` carrying a `mutation_summary`), aggregates
  the *number of mutational events that touched each codon
  position*. The output is one count per codon, ready to be
  rendered as a heatmap track aligned with the `CodonViewer`
  output.

  ## What counts

    * **`:domain_flip`** — every event with `gene_id == gene.id`
      contributes `+1` to the 23 codon positions of the
      affected domain (`domain_index * 23 .. domain_index * 23
      + 22`). The spike is on the whole domain, not on a single
      codon, because the audit shape doesn't carry the per-
      codon position of the substitution that flipped the
      tag.
    * **`:gene_chimera_birth`** — events where the gene is
      either `source_gene_id` or `dest_gene_id` contribute
      `codons_moved` to a representative slot (start of the
      destination's last domain by default; a future precise
      version will use `dest_position`).

  v1 deliberately does *not* try to reconstruct ancestral
  positions — the count is "events that affected this region
  during the lineage's recorded history", not "per-position
  substitutions since the MRCA". The latter requires the
  ancestral-sequence reconstruction of 3.7 (Phase 26 same
  tranche).
  """

  alias Arkea.Genome.Gene
  alias Arkea.Persistence.AuditLog

  @phase1_domain_size 23

  @type bin :: %{
          codon_index: non_neg_integer(),
          count: non_neg_integer(),
          contributors: [String.t()]
        }

  @type t :: %{
          gene_id: String.t(),
          codon_count: non_neg_integer(),
          total_events: non_neg_integer(),
          bins: [bin()]
        }

  @doc """
  Build the hotspot map for `gene` from the supplied audit log.

  `audit` should be the per-biotope audit list (the same one
  the ledger / phylogeny views consume). Pure: no DB.
  """
  @spec build(Gene.t(), [AuditLog.t()]) :: t()
  def build(%Gene{} = gene, audit) when is_list(audit) do
    n_codons = length(gene.codons)
    bins_acc = :array.new(n_codons, default: %{count: 0, contributors: []})

    bins_acc =
      audit
      |> Enum.filter(&relevant?(&1, gene.id))
      |> Enum.reduce(bins_acc, &accumulate_event(&1, gene, &2))

    bins =
      Enum.map(0..(n_codons - 1)//1, fn idx ->
        %{count: count, contributors: contribs} = :array.get(idx, bins_acc)
        %{codon_index: idx, count: count, contributors: Enum.reverse(contribs)}
      end)

    %{
      gene_id: gene.id,
      codon_count: n_codons,
      total_events: bins |> Enum.map(& &1.count) |> Enum.sum(),
      bins: bins
    }
  end

  defp relevant?(%AuditLog{event_type: "domain_flip", payload: %{} = payload}, gene_id) do
    Map.get(payload, "gene_id") == gene_id
  end

  defp relevant?(%AuditLog{event_type: "gene_chimera_birth", payload: %{} = payload}, gene_id) do
    Map.get(payload, "source_gene_id") == gene_id or
      Map.get(payload, "dest_gene_id") == gene_id
  end

  defp relevant?(_, _), do: false

  defp accumulate_event(
         %AuditLog{event_type: "domain_flip", payload: payload} = entry,
         _gene,
         acc
       ) do
    domain_index = Map.get(payload, "domain_index", 0)
    start = domain_index * @phase1_domain_size

    Enum.reduce(start..(start + @phase1_domain_size - 1)//1, acc, fn idx, a ->
      bump(a, idx, entry.event_type)
    end)
  end

  defp accumulate_event(%AuditLog{event_type: "gene_chimera_birth"} = entry, gene, acc) do
    # Drop the contribution at the end of the gene as a coarse
    # representative — the audit shape doesn't carry the per-
    # codon `dest_position`. A 3.7-precise version refines this
    # once the ancestral reconstruction shipped.
    last_index = max(length(gene.codons) - 1, 0)
    bump(acc, last_index, entry.event_type)
  end

  defp accumulate_event(_, _, acc), do: acc

  defp bump(acc, idx, contributor) do
    case :array.get(idx, acc) do
      :undefined ->
        acc

      %{count: count, contributors: contribs} ->
        :array.set(idx, %{count: count + 1, contributors: [contributor | contribs]}, acc)
    end
  end
end
