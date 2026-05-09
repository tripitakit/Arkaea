defmodule Arkea.Views.GeneTree do
  @moduledoc """
  Pure view-model for the gene-tree-vs-species-tree comparison
  (Phase 26 / 3.8).

  Given a population of lineages and a `gene_extractor` that
  picks the "gene of interest" out of each lineage's genome
  (e.g. `fn l -> Enum.at(l.genome.chromosome, 0) end` for the
  first chromosome gene, or a function that walks plasmids
  looking for a specific signature), this view:

    1. **Clusters** lineages by gene-codon similarity. Two
       lineages join the same cluster when the p-distance
       between their genes is `≤ :max_distance` (default
       `0.05`, i.e. 95 % codon identity).

    2. For each cluster surfaces the member lineages, the
       representative codon sequence (the gene of the first
       lineage that founded the cluster), and each member's
       p-distance to that representative.

    3. **Flags topological incongruence**: a cluster is tagged
       `:incongruent` when its members do *not* form a single
       monophyletic clade in the species (lineage) tree — i.e.
       there exists a non-member lineage that descends from
       the cluster's MRCA. This is the gene-tree signature of
       horizontal gene transfer (Doolittle 1999): a gene
       variant present in distantly related cells with the
       intervening cells *not* carrying it.

  A cluster of size 1 is `:singleton`. A cluster whose members
  all live under a single MRCA whose descendants are entirely
  members is `:congruent`.

  ## v1 limits

  This is **not** a true gene-tree inference. The clustering
  step is greedy single-linkage on p-distance; the
  congruence test uses the resident lineage tree (no fossil
  internal nodes). Both are first-order signals: a real
  Phase-30 phylogenomics view would build a proper gene
  phylogeny (NJ or RAxML-style ML), reconcile it with the
  species tree, and infer per-edge gain / loss / transfer
  events with confidence. v1 surfaces the raw clustering and
  congruence flag — that is enough to *see* HGT in the
  population, which is what the phylogeny UI of 3.X needs.
  """

  alias Arkea.Ecology.Lineage
  alias Arkea.Genome.Gene

  @default_max_distance 0.05

  @type member :: %{
          lineage_id: String.t(),
          parent_id: String.t() | nil,
          gene_id: String.t(),
          p_distance: float()
        }

  @type topology :: :singleton | :congruent | :incongruent

  @type cluster :: %{
          cluster_id: non_neg_integer(),
          representative_codons: [integer()],
          representative_gene_id: String.t(),
          members: [member()],
          mrca_lineage_id: String.t() | nil,
          mrca_descendants_count: non_neg_integer(),
          topology: topology()
        }

  @type t :: %{
          cluster_count: non_neg_integer(),
          unmatched_lineages: [String.t()],
          max_distance: float(),
          clusters: [cluster()]
        }

  @doc """
  Build the gene-tree view across `lineages`.

  ## Options

    * `:max_distance` — clustering threshold (p-distance,
      default `#{@default_max_distance}`).
    * `:gene_extractor` — required `(Lineage.t() -> Gene.t() | nil)`
      function that picks the gene of interest. Lineages where
      the extractor returns `nil` are listed under
      `unmatched_lineages` and not clustered.
  """
  @spec build([Lineage.t()], keyword()) :: t()
  def build(lineages, opts) when is_list(lineages) and is_list(opts) do
    extractor = Keyword.fetch!(opts, :gene_extractor)
    max_distance = Keyword.get(opts, :max_distance, @default_max_distance)

    {extracted, unmatched} = extract_genes(lineages, extractor)
    clusters = cluster_genes(extracted, max_distance)
    by_id = Map.new(lineages, &{&1.id, &1})
    annotated_clusters = Enum.map(clusters, &annotate_topology(&1, by_id))

    %{
      cluster_count: length(annotated_clusters),
      unmatched_lineages: unmatched,
      max_distance: max_distance,
      clusters: annotated_clusters
    }
  end

  defp extract_genes(lineages, extractor) do
    Enum.reduce(lineages, {[], []}, fn lineage, {acc, unmatched} ->
      case safe_extract(extractor, lineage) do
        {%Gene{} = gene, true} -> {[{lineage, gene} | acc], unmatched}
        _ -> {acc, [lineage.id | unmatched]}
      end
    end)
    |> then(fn {acc, unmatched} -> {Enum.reverse(acc), Enum.reverse(unmatched)} end)
  end

  defp safe_extract(extractor, lineage) do
    case extractor.(lineage) do
      %Gene{} = g -> {g, true}
      _ -> {nil, false}
    end
  end

  defp cluster_genes(extracted, max_distance) do
    {clusters, _} =
      Enum.reduce(extracted, {[], 0}, fn {lineage, gene}, {clusters, next_id} ->
        case find_cluster(clusters, gene, max_distance) do
          nil ->
            new_cluster = %{
              cluster_id: next_id,
              representative_codons: gene.codons,
              representative_gene_id: gene.id,
              members: [member_entry(lineage, gene, 0.0)]
            }

            {clusters ++ [new_cluster], next_id + 1}

          {found, dist} ->
            {clusters
             |> Enum.map(fn c ->
               if c.cluster_id == found.cluster_id do
                 %{c | members: c.members ++ [member_entry(lineage, gene, dist)]}
               else
                 c
               end
             end), next_id}
        end
      end)

    clusters
  end

  defp find_cluster(clusters, gene, max_distance) do
    Enum.reduce_while(clusters, nil, fn c, _acc ->
      d = p_distance(c.representative_codons, gene.codons)

      if d <= max_distance do
        {:halt, {c, d}}
      else
        {:cont, nil}
      end
    end)
  end

  defp member_entry(%Lineage{} = lineage, %Gene{} = gene, dist) do
    %{
      lineage_id: lineage.id,
      parent_id: lineage.parent_id,
      gene_id: gene.id,
      p_distance: dist
    }
  end

  defp p_distance(codons_a, codons_b) do
    paired = Enum.zip(codons_a, codons_b)
    paired_total = length(paired)
    extra = abs(length(codons_a) - length(codons_b))

    paired_mm = Enum.count(paired, fn {a, b} -> a != b end)
    total = paired_total + extra

    if total == 0, do: 0.0, else: (paired_mm + extra) / total
  end

  defp annotate_topology(cluster, by_id) do
    member_ids = MapSet.new(cluster.members, & &1.lineage_id)

    if MapSet.size(member_ids) <= 1 do
      Map.merge(cluster, %{
        mrca_lineage_id: List.first(MapSet.to_list(member_ids)),
        mrca_descendants_count: 1,
        topology: :singleton
      })
    else
      mrca_id = compute_mrca(member_ids, by_id)
      descendants = subtree_descendants(mrca_id, by_id)
      intruders = MapSet.difference(descendants, member_ids)

      topology = if MapSet.size(intruders) == 0, do: :congruent, else: :incongruent

      Map.merge(cluster, %{
        mrca_lineage_id: mrca_id,
        mrca_descendants_count: MapSet.size(descendants),
        topology: topology
      })
    end
  end

  defp compute_mrca(member_ids, by_id) do
    paths = Enum.map(member_ids, fn id -> ancestor_path(id, by_id) end)

    case paths do
      [] ->
        nil

      [first | rest] ->
        first_set = MapSet.new(first)

        common =
          Enum.reduce(rest, first_set, fn path, acc ->
            MapSet.intersection(acc, MapSet.new(path))
          end)

        # Pick the deepest shared ancestor (the one closest to a member).
        Enum.find(first, fn id -> MapSet.member?(common, id) end)
    end
  end

  defp ancestor_path(id, by_id) do
    case Map.get(by_id, id) do
      nil ->
        []

      lineage ->
        [id | if(lineage.parent_id, do: ancestor_path(lineage.parent_id, by_id), else: [])]
    end
  end

  defp subtree_descendants(nil, _by_id), do: MapSet.new()

  defp subtree_descendants(root_id, by_id) do
    children_index =
      by_id
      |> Map.values()
      |> Enum.group_by(& &1.parent_id)

    walk_descendants(root_id, children_index, MapSet.new([root_id]))
  end

  defp walk_descendants(id, children_index, acc) do
    children = Map.get(children_index, id, [])

    Enum.reduce(children, acc, fn child, inner_acc ->
      walk_descendants(child.id, children_index, MapSet.put(inner_acc, child.id))
    end)
  end
end
