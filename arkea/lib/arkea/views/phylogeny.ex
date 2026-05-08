defmodule Arkea.Views.Phylogeny do
  @moduledoc """
  Pure phylogeny layout (UI Phase D, post-Review-2 canonical refactor).

  Given a list of `Arkea.Ecology.Lineage` structs (with `parent_id`
  pointers) plus a list of audit log entries, produces a *canonical*
  phylogenetic dendrogram where:

  - **Every observed lineage is a tip** (leaf), labelled and coloured by
    abundance band — regardless of whether it has descendants.
  - **Speciation events are explicit synthetic split nodes** ("Y
    junctions") that have no abundance, no label and no associated
    lineage record. Each synthetic split corresponds to one observed
    lineage L: it is the point where L's lineage branched, with L
    itself attached as one tip among its descendants.

  This matches the convention used in molecular phylogenetics
  (Newick/Nexus output, FigTree, iTOL): tips are extant taxa, internal
  nodes are inferred speciation points.

  ## Output shape

  ```elixir
  %{
    nodes: [
      %{
        id: lineage_id | "split:" <> lineage_id,
        parent_id: rendered_parent_id | nil,
        depth: integer,
        x: float,
        y: float,
        branch_length: float,
        cumulative_distance: float,
        leaf?: boolean,        # true for observed lineage tips
        synthetic?: boolean,   # true for speciation-event splits
        abundance: integer,    # 0 for synthetic splits and extinct
        extinct?: boolean,
        gene_count: integer,
        phenotype: %{base_growth_rate: f, repair_efficiency: f, energy_cost: f}
      }
    ],
    edges: [
      %{
        from: rendered_parent_id,
        to: child_id,
        mutation_summary: map | nil,
        kind: :vertical
      }
    ],
    width: float,
    height: float,
    max_depth: integer
  }
  ```

  ## Edge labelling

  `mutation_summary` is attached to the edge whose `to` is either:

  - an observed lineage tip whose biological parent is *not* the same
    lineage (i.e. the speciation edge that gave birth to it), OR
  - a synthetic split that *represents* an observed lineage's
    speciation event (in that case the summary describes the
    cumulative phenotype delta of the speciating lineage relative to
    its own biological parent).

  The edge `S_X → X_tip` (the "X continued to exist after speciating"
  zero-distance branch) deliberately carries no mutation_summary.

  ## Behaviour

  - Lineages whose `parent_id` is unknown (nil or not in the input
    list) are treated as roots.
  - Extinct lineages (those mentioned in audit but absent from the
    current lineage list) can be supplied via the `:extinct_lineages`
    option to keep clades visible as ghost tips.
  - Layout is deterministic: same input → same `(x, y)` per node.

  This module does not render — `ArkeaWeb.Components.Phylogeny` does.
  """

  alias Arkea.Ecology.Lineage
  alias Arkea.Genome.PDistance
  alias Arkea.Persistence.AuditLog
  alias Arkea.Sim.Phenotype

  @sibling_step 48.0

  @distance_scale 800.0

  @min_branch_px 12.0

  @type node_record :: %{
          id: String.t(),
          parent_id: String.t() | nil,
          depth: non_neg_integer(),
          x: float(),
          y: float(),
          branch_length: float(),
          cumulative_distance: float(),
          leaf?: boolean(),
          synthetic?: boolean(),
          abundance: non_neg_integer(),
          extinct?: boolean(),
          gene_count: non_neg_integer(),
          phenotype: %{
            base_growth_rate: float(),
            repair_efficiency: float(),
            energy_cost: float()
          }
        }

  @type edge_record :: %{
          from: String.t(),
          to: String.t(),
          mutation_summary: map() | nil,
          kind: :vertical
        }

  @type t :: %{
          nodes: [node_record()],
          edges: [edge_record()],
          width: float(),
          height: float(),
          max_depth: non_neg_integer()
        }

  @spec build([Lineage.t()], [AuditLog.t()], keyword()) :: t()
  def build(lineages, audit \\ [], opts \\ []) when is_list(lineages) and is_list(audit) do
    extinct = Keyword.get(opts, :extinct_lineages, []) |> Enum.uniq_by(& &1.id)
    all_lineages = Enum.uniq_by(lineages ++ extinct, & &1.id)

    by_id = Map.new(all_lineages, fn l -> {l.id, l} end)
    children_by_parent = build_children_map(all_lineages, by_id)
    born_payloads = born_payloads_by_lineage(audit)

    roots = roots_for(all_lineages, by_id)

    {raw_nodes, _next_y} =
      Enum.reduce(roots, {[], 0.0}, fn root, {acc, cursor} ->
        {laid_out, next} =
          layout_subtree(root, 0, 0.0, cursor, nil, nil, children_by_parent)

        {acc ++ laid_out, next}
      end)

    nodes = Enum.map(raw_nodes, &enrich_node(&1, lineages))
    edges = build_edges(raw_nodes, born_payloads)

    width = nodes |> Enum.map(& &1.x) |> Enum.max(fn -> 0.0 end)
    height = nodes |> Enum.map(& &1.y) |> Enum.max(fn -> 0.0 end)
    max_depth = nodes |> Enum.map(& &1.depth) |> Enum.max(fn -> 0 end)

    %{
      nodes: nodes,
      edges: edges,
      width: width + 80.0,
      height: height + @sibling_step,
      max_depth: max_depth
    }
  end

  # -------------------------------------------------------------------------
  # Layout

  defp build_children_map(lineages, by_id) do
    lineages
    |> Enum.group_by(fn l ->
      case l.parent_id do
        nil -> nil
        pid -> if Map.has_key?(by_id, pid), do: pid, else: nil
      end
    end)
    |> Map.new(fn {parent_id, children} ->
      {parent_id, Enum.sort_by(children, & &1.id)}
    end)
  end

  defp roots_for(lineages, by_id) do
    lineages
    |> Enum.filter(fn l ->
      l.parent_id == nil or not Map.has_key?(by_id, l.parent_id)
    end)
    |> Enum.sort_by(& &1.id)
  end

  # Recursive layout. Every observed lineage becomes a tip; lineages
  # with descendants are wrapped in a synthetic split (Y-junction) so
  # the tree is canonical (every taxon is a leaf).
  #
  # Arguments:
  #   - `node`            : the lineage struct currently being laid out
  #   - `depth`           : nesting depth in the *rendered* tree
  #   - `cumulative_distance` : x-coordinate of the lineage's branch
  #                             entry-point (== parent's split x, if any)
  #   - `cursor`          : next available y-row for a tip
  #   - `rendered_parent_id` : the id of the rendered parent — either a
  #                            synthetic split or `nil` for absolute roots
  #   - `parent_node`     : the lineage struct of `node`'s biological
  #                         parent (nil for absolute roots), used only
  #                         to compute branch_length via PDistance
  #   - `children_by_parent` : adjacency map
  defp layout_subtree(
         node,
         depth,
         cumulative_distance,
         cursor,
         rendered_parent_id,
         parent_node,
         children_by_parent
       ) do
    branch_length = branch_length_for(parent_node, node)
    edge_px = max(branch_length * @distance_scale, @min_branch_px)
    next_cumulative = cumulative_distance + edge_px

    children = Map.get(children_by_parent, node.id, [])

    if children == [] do
      record =
        tip_record(node, rendered_parent_id, depth, next_cumulative, cursor, branch_length)

      {[record], cursor + @sibling_step}
    else
      # Lineage with descendants: emit a synthetic split + the lineage
      # itself as one tip + every child subtree, all parented under
      # the split.
      split_id = synthetic_split_id(node.id)

      # Place the lineage's own tip first (top row of the split's
      # children) so dominant lineages stay near the top of their clade.
      own_tip = tip_record(node, split_id, depth + 1, next_cumulative, cursor, 0.0)
      cursor1 = cursor + @sibling_step

      {child_records, cursor2} =
        Enum.reduce(children, {[], cursor1}, fn child, {acc, cur} ->
          {laid, next} =
            layout_subtree(
              child,
              depth + 1,
              next_cumulative,
              cur,
              split_id,
              node,
              children_by_parent
            )

          {acc ++ laid, next}
        end)

      # Anchor the synthetic split at the y-midpoint of all its direct
      # rendered children (own tip + each child subtree's root).
      direct = Enum.filter([own_tip | child_records], &(&1.parent_id == split_id))
      split_y = avg(Enum.map(direct, & &1.y))

      split_record = %{
        id: split_id,
        parent_id: rendered_parent_id,
        # The lineage that "speciates" at this split. Used to fetch
        # mutation_summary for the edge that *enters* this split.
        lineage_id: node.id,
        depth: depth,
        x: next_cumulative,
        y: split_y,
        branch_length: branch_length,
        cumulative_distance: next_cumulative,
        lineage: nil,
        synthetic?: true
      }

      {[split_record, own_tip | child_records], cursor2}
    end
  end

  defp tip_record(node, rendered_parent_id, depth, x, y, branch_length) do
    %{
      id: node.id,
      parent_id: rendered_parent_id,
      lineage_id: node.id,
      depth: depth,
      x: x,
      y: y,
      branch_length: branch_length,
      cumulative_distance: x,
      lineage: node,
      synthetic?: false
    }
  end

  defp synthetic_split_id(lineage_id), do: "split:" <> lineage_id

  defp avg([]), do: 0.0
  defp avg(list), do: Enum.sum(list) / length(list)

  defp branch_length_for(nil, _child), do: 0.0

  defp branch_length_for(parent, child) do
    PDistance.distance(genome_of(parent), genome_of(child))
  end

  defp genome_of(%Lineage{genome: g}), do: g
  defp genome_of(_), do: nil

  # -------------------------------------------------------------------------
  # Enrichment: turn raw layout records into JSON-encodable node rows.

  defp enrich_node(%{synthetic?: true} = record, _alive_lineages) do
    %{
      id: record.id,
      parent_id: record.parent_id,
      depth: record.depth,
      x: record.x,
      y: record.y,
      branch_length: Map.get(record, :branch_length, 0.0),
      cumulative_distance: Map.get(record, :cumulative_distance, 0.0),
      leaf?: false,
      synthetic?: true,
      abundance: 0,
      extinct?: false,
      gene_count: 0,
      phenotype: %{base_growth_rate: 0.0, repair_efficiency: 0.0, energy_cost: 0.0}
    }
  end

  defp enrich_node(%{lineage: %Lineage{} = lineage} = record, alive_lineages) do
    alive_set = MapSet.new(alive_lineages, & &1.id)

    abundance =
      if MapSet.member?(alive_set, lineage.id), do: Lineage.total_abundance(lineage), else: 0

    phenotype =
      case lineage.genome do
        nil ->
          %{base_growth_rate: 0.0, repair_efficiency: 0.0, energy_cost: 0.0}

        genome ->
          ph = Phenotype.from_genome(genome)

          %{
            base_growth_rate: ph.base_growth_rate,
            repair_efficiency: ph.repair_efficiency,
            energy_cost: ph.energy_cost
          }
      end

    %{
      id: record.id,
      parent_id: record.parent_id,
      depth: record.depth,
      x: record.x,
      y: record.y,
      branch_length: Map.get(record, :branch_length, 0.0),
      cumulative_distance: Map.get(record, :cumulative_distance, 0.0),
      leaf?: true,
      synthetic?: false,
      abundance: abundance,
      extinct?: not MapSet.member?(alive_set, lineage.id),
      gene_count: gene_count(lineage),
      phenotype: phenotype
    }
  end

  defp gene_count(%Lineage{genome: nil}), do: 0
  defp gene_count(%Lineage{genome: %{gene_count: n}}), do: n
  defp gene_count(_), do: 0

  # -------------------------------------------------------------------------
  # Edges: connect rendered parent → record. mutation_summary attaches
  # to the edge that "represents" a lineage's birth from its parent.

  defp build_edges(records, born_payloads) do
    Enum.flat_map(records, fn record ->
      case record.parent_id do
        nil ->
          []

        pid ->
          summary =
            cond do
              # The S_X → X_tip self-continuation edge: same lineage,
              # no birth event.
              not record.synthetic? and pid == synthetic_split_id(record.id) ->
                nil

              # Synthetic split S_L: the entering edge represents L's
              # birth from its biological parent.
              record.synthetic? ->
                Map.get(born_payloads, record.lineage_id)

              # Observed lineage tip whose biological parent has no
              # children (so no synthetic split was emitted) — direct
              # parent_id → child edge with the standard mutation_summary.
              true ->
                Map.get(born_payloads, record.id)
            end

          [
            %{
              from: pid,
              to: record.id,
              mutation_summary: summary,
              kind: :vertical
            }
          ]
      end
    end)
  end

  defp born_payloads_by_lineage(audit) do
    audit
    |> Enum.filter(fn
      %AuditLog{event_type: "lineage_born", payload: %{} = payload} ->
        Map.get(payload, "mutation_summary") != nil

      _ ->
        false
    end)
    |> Map.new(fn %AuditLog{target_lineage_id: id, payload: payload} ->
      {id, Map.get(payload, "mutation_summary")}
    end)
  end

  # ---------------------------------------------------------------------------
  # Phase 25 / 3.X — branch-metric enrichment + trait colouring.

  @doc """
  Augment a phylogeny model in place with two per-node metrics
  (Phase 25 / 3.4 + 3.5):

    * `:phenotype_displacement` — `|Δgrowth| + |Δrepair| +
      |Δenergy_cost|` aggregated from the node's incoming
      edge's `mutation_summary` (already produced by
      `Tick.derive_events/2` / `:lineage_born`). This is a
      branch-length-independent proxy for *how much* the
      phenotype shifted in the speciation event that produced
      the node — divided by `branch_length`, the consumer gets
      a "mutator-style" intensity diagnostic.
    * `:hgt_received` — number of `hgt_transfer` audit events
      whose `target_lineage_id` is this node's id. Counts the
      conjugation / transformation / transduction acquisitions
      received by the lineage over the audit window.

  Synthetic split nodes carry the displacement of the speciating
  lineage (the edge `split:X → X` self-edge is empty, but
  `split:X → Y` carries the summary for sibling Y; we use the
  speciation edge by walking the model's edges).
  """
  @spec enrich_with_branch_metrics(t(), [AuditLog.t()]) :: t()
  def enrich_with_branch_metrics(%{nodes: nodes, edges: edges} = model, audit)
      when is_list(audit) do
    hgt_counts = hgt_received_counts(audit)
    summary_by_to = Map.new(edges, fn e -> {e.to, e.mutation_summary} end)

    enriched =
      Enum.map(nodes, fn node ->
        node
        |> Map.put(:phenotype_displacement, displacement_from(summary_by_to[node.id]))
        |> Map.put(:hgt_received, Map.get(hgt_counts, node.id, 0))
      end)

    %{model | nodes: enriched}
  end

  defp displacement_from(nil), do: 0.0

  defp displacement_from(summary) when is_map(summary) do
    abs_or_zero(Map.get(summary, "d_growth_rate", 0)) +
      abs_or_zero(Map.get(summary, "d_repair", 0)) +
      abs_or_zero(Map.get(summary, "d_energy_cost", 0))
  end

  defp abs_or_zero(v) when is_number(v), do: abs(v * 1.0)
  defp abs_or_zero(_), do: 0.0

  defp hgt_received_counts(audit) do
    audit
    |> Enum.filter(fn
      %AuditLog{event_type: "hgt_transfer", target_lineage_id: id} when not is_nil(id) -> true
      _ -> false
    end)
    |> Enum.frequencies_by(& &1.target_lineage_id)
  end

  @doc """
  Annotate every non-synthetic node with `:colour_value`, the
  numeric value of `trait` from the node's existing `phenotype`
  map (Phase 25 / 3.1). When `trait` is not a known field the
  function returns the model unchanged (no-op rather than crash).

  Synthetic split nodes (`synthetic? == true`) and extinct
  ghost tips (`extinct? == true`) get `colour_value: nil` so
  the renderer can keep its current fallback colours for them.
  """
  @spec colour_by_trait(t(), atom()) :: t()
  def colour_by_trait(%{nodes: nodes} = model, trait) when is_atom(trait) do
    if trait in [:base_growth_rate, :repair_efficiency, :energy_cost] do
      enriched =
        Enum.map(nodes, fn node ->
          value =
            cond do
              Map.get(node, :synthetic?, false) -> nil
              Map.get(node, :extinct?, false) -> nil
              true -> get_in(node, [:phenotype, trait])
            end

          Map.put(node, :colour_value, value)
        end)

      %{model | nodes: enriched}
    else
      model
    end
  end
end
