defmodule Arkea.Views.DomainLandscape do
  @moduledoc """
  Pure structure-function landscape view for a single domain
  category across a population of lineages (Phase 26 / 2.9).

  Given a list of `Lineage.t()` and a target domain type
  (e.g. `:catalytic_site`), surfaces every instance of that
  category present in the population's genomes (chromosome,
  plasmids, prophages — every domain anywhere) annotated with
  the lineage that carries it and its position in the gene.
  The output is ready to drive a 2D scatter:

      x = params[:kcat]   (or any params key the consumer picks)
      y = params[:km]
      size ∝ lineage abundance
      colour ∝ lineage_id hash (or trait, when the consumer
              decides)

  The biologically interesting plot is `kcat × Km` for every
  `:catalytic_site` in the biotope: it lets the user see which
  enzyme variants have actually evolved (clusters in
  parameter space) and which are convergent (two distant
  lineages landing on the same `(kcat, Km)` neighbourhood).

  The view is *generic* on parameter keys — `:catalytic_site`
  publishes `kcat` + `signal_key` + `reaction_class`,
  `:dna_binding` publishes `binding_affinity` +
  `promoter_specificity`, etc. The consumer asks for whichever
  pair makes sense for the chosen domain category.

  ## v1 simplifications

    * No clustering of variants (the consumer decides on its
      own thresholds when rendering).
    * No "convergence highlight" markers — surfacing those
      requires the gene-tree-vs-species-tree view of 3.8.
  """

  alias Arkea.Ecology.Lineage
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene

  @type point :: %{
          lineage_id: String.t(),
          abundance: non_neg_integer(),
          gene_id: String.t(),
          domain_index: non_neg_integer(),
          replicon: :chromosome | :plasmid | :prophage,
          replicon_index: non_neg_integer(),
          params: map()
        }

  @type t :: %{
          domain_type: atom(),
          point_count: non_neg_integer(),
          points: [point()]
        }

  @doc """
  Build the landscape view for `domain_type` across the
  population. Lineages with `genome: nil` (delta-encoded
  descendants without a materialised genome) are skipped.
  """
  @spec build([Lineage.t()], atom()) :: t()
  def build(lineages, domain_type) when is_list(lineages) and is_atom(domain_type) do
    points =
      lineages
      |> Enum.filter(&(&1.genome != nil))
      |> Enum.flat_map(&points_for_lineage(&1, domain_type))

    %{
      domain_type: domain_type,
      point_count: length(points),
      points: points
    }
  end

  defp points_for_lineage(%Lineage{} = lineage, domain_type) do
    abundance = Lineage.total_abundance(lineage)

    chromosome_points =
      points_in_replicon(
        lineage.genome.chromosome,
        domain_type,
        :chromosome,
        0,
        lineage,
        abundance
      )

    plasmid_points =
      lineage.genome.plasmids
      |> Enum.with_index()
      |> Enum.flat_map(fn {plasmid, idx} ->
        points_in_replicon(plasmid_genes(plasmid), domain_type, :plasmid, idx, lineage, abundance)
      end)

    prophage_points =
      lineage.genome.prophages
      |> Enum.with_index()
      |> Enum.flat_map(fn {prophage, idx} ->
        points_in_replicon(
          prophage_genes(prophage),
          domain_type,
          :prophage,
          idx,
          lineage,
          abundance
        )
      end)

    chromosome_points ++ plasmid_points ++ prophage_points
  end

  defp plasmid_genes(%{genes: genes}) when is_list(genes), do: genes
  defp plasmid_genes(_), do: []

  defp prophage_genes(%{genes: genes}) when is_list(genes), do: genes
  defp prophage_genes(_), do: []

  defp points_in_replicon(genes, domain_type, replicon, replicon_index, lineage, abundance)
       when is_list(genes) do
    genes
    |> Enum.flat_map(fn %Gene{} = gene ->
      gene.domains
      |> Enum.with_index()
      |> Enum.flat_map(fn {%Domain{} = d, dom_idx} ->
        if d.type == domain_type do
          [
            %{
              lineage_id: lineage.id,
              abundance: abundance,
              gene_id: gene.id,
              domain_index: dom_idx,
              replicon: replicon,
              replicon_index: replicon_index,
              params: d.params
            }
          ]
        else
          []
        end
      end)
    end)
  end
end
