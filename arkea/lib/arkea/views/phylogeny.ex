defmodule Arkea.Views.Phylogeny do
  @moduledoc """
  Pure phylogeny layout (UI Phase D).

  Given a list of `Arkea.Ecology.Lineage` structs (with `parent_id`
  pointers) plus a list of audit log entries, produces a tidy-tree
  layout (Reingold–Tilford-like) ready for SVG rendering.

  ## Output shape

  ```elixir
  %{
    nodes: [
      %{
        id: lineage_id,
        parent_id: parent_id | nil,
        depth: integer,        # 0 for founders
        x: float,              # horizontal (sibling-spread) coordinate
        y: float,              # vertical (depth) coordinate
        abundance: integer,    # current total abundance, 0 if extinct
        extinct?: boolean,
        gene_count: integer,
        phenotype: %{base_growth_rate: f, repair_efficiency: f, energy_cost: f}
      }
    ],
    edges: [
      %{
        from: parent_id,
        to: child_id,
        mutation_summary: map | nil,   # populated from :lineage_born audit payload
        kind: :vertical                # :vertical for parent-child, :hgt for HGT-borne
      }
    ],
    width: float,
    height: float,
    max_depth: integer
  }
  ```

  ## Behaviour

  - Lineages whose `parent_id` is unknown (nil or not in the input
    list) are treated as roots.
  - Extinct lineages (those mentioned in audit but absent from the
    current lineage list) can be supplied via the `:extinct_lineages`
    option to keep clades visible as ghost nodes.
  - Layout is deterministic: same input → same `(x, y)` per node.

  This module does not render — `ArkeaWeb.Components.Phylogeny` does.
  """

  alias Arkea.Ecology.Lineage
  alias Arkea.Genome.PDistance
  alias Arkea.Persistence.AuditLog
  alias Arkea.Sim.Phenotype

  # Vertical sibling spread (one column per leaf).
  @x_step 60.0

  # Px per unit p-distance. p-distance ranges 0..1 in theory but in
  # practice most parent→child branches sit between 0.0 and ~0.05
  # (one-codon mutation over a 200-codon genome ≈ 0.005). The chosen
  # scale gives a single mutation a visible 4 px branch while keeping
  # cumulative drift across deep clades inside the SVG viewport.
  @distance_scale 800.0

  # Minimum branch length so identical genomes (e.g. delta-encoded
  # descendants whose genome cache is `nil` — distance is reported as
  # 0 in that case) are still drawn as a small gap rather than
  # overlapping their parent.
  @min_branch_px 8.0

  @type node_record :: %{
          id: String.t(),
          parent_id: String.t() | nil,
          depth: non_neg_integer(),
          x: float(),
          y: float(),
          branch_length: float(),
          cumulative_distance: float(),
          leaf?: boolean(),
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

    {nodes_acc, _next_x} =
      Enum.reduce(roots, {[], 0.0}, fn root, {acc, cursor} ->
        {laid_out, next} =
          layout_subtree(root, 0, 0.0, cursor, nil, children_by_parent)

        {acc ++ laid_out, next}
      end)

    nodes = Enum.map(nodes_acc, &enrich_node(&1, lineages, children_by_parent))
    edges = build_edges(nodes_acc, born_payloads)

    width = nodes |> Enum.map(& &1.x) |> Enum.max(fn -> 0.0 end)
    height = nodes |> Enum.map(& &1.y) |> Enum.max(fn -> 0.0 end)
    max_depth = nodes |> Enum.map(& &1.depth) |> Enum.max(fn -> 0 end)

    %{
      nodes: nodes,
      edges: edges,
      width: width + @x_step,
      height: height + 80.0,
      max_depth: max_depth
    }
  end

  # -------------------------------------------------------------------------
  # Children adjacency map: %{parent_id => [child_lineage_struct, …]}.
  # We deduplicate children to keep the layout deterministic if the
  # caller supplied the same lineage twice.

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

  # Recursive layout — y is the cumulative p-distance from the root
  # (× scale, with a per-edge floor to keep zero-distance branches
  # visible). x is sibling spread — one column per leaf, parents
  # centred above their children.
  defp layout_subtree(node, depth, cumulative_distance, cursor, parent_node, children_by_parent) do
    branch_length = branch_length_for(parent_node, node)
    edge_px = max(branch_length * @distance_scale, @min_branch_px)
    next_cumulative = cumulative_distance + edge_px

    children = Map.get(children_by_parent, node.id, [])

    if children == [] do
      record = %{
        id: node.id,
        parent_id: node.parent_id,
        depth: depth,
        x: cursor,
        y: next_cumulative,
        branch_length: branch_length,
        cumulative_distance: next_cumulative,
        lineage: node
      }

      {[record], cursor + @x_step}
    else
      {child_records, next_cursor} =
        Enum.reduce(children, {[], cursor}, fn child, {acc, cur} ->
          {laid, next} =
            layout_subtree(child, depth + 1, next_cumulative, cur, node, children_by_parent)

          {acc ++ laid, next}
        end)

      mid_x =
        case Enum.filter(child_records, fn r -> r.parent_id == node.id end) do
          [] -> cursor
          direct -> avg(Enum.map(direct, & &1.x))
        end

      record = %{
        id: node.id,
        parent_id: node.parent_id,
        depth: depth,
        x: mid_x,
        y: next_cumulative,
        branch_length: branch_length,
        cumulative_distance: next_cumulative,
        lineage: node
      }

      {[record | child_records], next_cursor}
    end
  end

  defp avg([]), do: 0.0
  defp avg(list), do: Enum.sum(list) / length(list)

  # The lineage stored on the layout record is an `%Arkea.Ecology.Lineage{}`
  # struct; we fall back to its sibling map shape for tests/extinct
  # node injection. p-distance returns 0.0 if either genome is nil
  # (delta-encoded descendants).
  defp branch_length_for(nil, _child), do: 0.0

  defp branch_length_for(parent, child) do
    PDistance.distance(genome_of(parent), genome_of(child))
  end

  defp genome_of(%Lineage{genome: g}), do: g
  defp genome_of(_), do: nil

  # Enrich layout records with phenotype/abundance metadata; drops the
  # raw lineage struct so the result is JSON-encodable.
  defp enrich_node(%{lineage: %Lineage{} = lineage} = record, alive_lineages, children_by_parent) do
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
      leaf?: Map.get(children_by_parent, record.id, []) == [],
      abundance: abundance,
      extinct?: not MapSet.member?(alive_set, lineage.id),
      gene_count: gene_count(lineage),
      phenotype: phenotype
    }
  end

  defp gene_count(%Lineage{genome: nil}), do: 0
  defp gene_count(%Lineage{genome: %{gene_count: n}}), do: n
  defp gene_count(_), do: 0

  defp build_edges(nodes, born_payloads) do
    by_id = Map.new(nodes, fn n -> {n.id, n} end)

    Enum.flat_map(nodes, fn node ->
      case node.parent_id do
        nil ->
          []

        pid ->
          if Map.has_key?(by_id, pid) do
            [
              %{
                from: pid,
                to: node.id,
                mutation_summary: Map.get(born_payloads, node.id),
                kind: :vertical
              }
            ]
          else
            []
          end
      end
    end)
  end

  # Audit log entries with `event_type == "lineage_born"` carry the
  # phenotype delta (Phase B mutation_summary). We index by child id
  # so edges can label themselves with the delta.
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
end
