defmodule Arkea.Views.PhylogenyTest do
  use ExUnit.Case, async: true

  alias Arkea.Ecology.Lineage
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Persistence.AuditLog
  alias Arkea.Views.Phylogeny

  test "build/3 with empty input returns degenerate model" do
    assert %{nodes: [], edges: [], width: w, height: h, max_depth: 0} =
             Phylogeny.build([], [])

    assert is_float(w)
    assert is_float(h)
  end

  test "founder + two children produces a canonical tree with synthetic split" do
    founder = lineage("a", nil)
    child1 = lineage("b", "a")
    child2 = lineage("c", "a")

    model = Phylogeny.build([founder, child1, child2], [])

    # Canonical phylogeny: 3 observed lineages → 3 tips + 1 synthetic
    # speciation split (the founder branched twice into b and c).
    assert length(model.nodes) == 4

    # Edges: synthetic split → a (self-continuation), split → b, split → c.
    assert length(model.edges) == 3

    by_id = Map.new(model.nodes, fn n -> {n.id, n} end)
    assert by_id["split:a"].synthetic? == true
    assert by_id["a"].leaf? == true
    assert by_id["b"].leaf? == true
    assert by_id["c"].leaf? == true

    # The synthetic split is at depth 0 (it sits where `a` "spoke");
    # all observed lineages are tips at depth 1 below it.
    assert by_id["split:a"].depth == 0
    assert by_id["a"].depth == 1
    assert by_id["b"].depth == 1
    assert by_id["c"].depth == 1
    assert model.max_depth == 1
  end

  test "every observed lineage is a tip in the canonical view" do
    a = lineage("a", nil)
    b = lineage("b", "a")
    c = lineage("c", "b")

    model = Phylogeny.build([a, b, c], [])
    by_id = Map.new(model.nodes, fn n -> {n.id, n} end)

    assert by_id["a"].leaf? == true
    assert by_id["b"].leaf? == true
    assert by_id["c"].leaf? == true

    # `a` and `b` both have descendants → each spawns a synthetic
    # split. `c` is terminal in the lineage tree, no split for it.
    assert by_id["split:a"].synthetic? == true
    assert by_id["split:b"].synthetic? == true
    refute Map.has_key?(by_id, "split:c")
  end

  test "lineages with unknown parent_id are treated as roots" do
    orphan = lineage("orphan", "missing-parent-id")
    model = Phylogeny.build([orphan], [])

    [node] = model.nodes
    assert node.id == "orphan"
    assert node.depth == 0
    assert model.edges == []
  end

  test "extinct lineages provided via :extinct_lineages are rendered as ghost nodes" do
    founder = lineage("alive", nil)
    extinct = lineage("dead", nil)

    model =
      Phylogeny.build(
        [founder],
        [],
        extinct_lineages: [extinct]
      )

    by_id = Map.new(model.nodes, fn n -> {n.id, n} end)
    assert by_id["dead"].extinct? == true
    assert by_id["alive"].extinct? == false
  end

  test "edges carry the mutation_summary from the matching lineage_born audit entry" do
    founder = lineage("a", nil)
    child = lineage("b", "a")

    audit = [
      %AuditLog{
        event_type: "lineage_born",
        target_lineage_id: "b",
        payload: %{
          "mutation_summary" => %{
            "d_growth_rate" => 0.3,
            "d_repair" => -0.05,
            "d_energy_cost" => 0.02,
            "child_gene_count" => 5,
            "parent_gene_count" => 5
          }
        }
      }
    ]

    model = Phylogeny.build([founder, child], audit)

    # The speciation edge in the canonical tree is split:a → b (the
    # synthetic split represents `a`'s speciation event).
    speciation_edge = Enum.find(model.edges, &(&1.to == "b"))
    assert speciation_edge.from == "split:a"
    assert speciation_edge.mutation_summary["d_growth_rate"] == 0.3

    # The self-continuation edge split:a → a carries no mutation
    # summary (no birth event happened on that edge).
    self_edge = Enum.find(model.edges, &(&1.to == "a"))
    assert self_edge.from == "split:a"
    assert self_edge.mutation_summary == nil
  end

  defp lineage(id, parent_id) do
    %Lineage{
      id: id,
      parent_id: parent_id,
      original_seed_id: nil,
      clade_ref_id: nil,
      created_at_tick: 0,
      abundance_by_phase: %{water_column: 100},
      genome: nil,
      delta: [],
      biomass: %{wall: 1.0, membrane: 1.0, dna: 1.0},
      dna_damage: 0.0
    }
  end

  describe "p-distance branch lengths" do
    test "branch_length on a child edge equals PDistance(parent.genome, child.genome)" do
      parent_genome =
        Genome.new([Gene.from_domains([Domain.new([0, 0, 0], List.duplicate(5, 20))])])

      child_genome =
        Genome.new([Gene.from_domains([Domain.new([0, 0, 0], [9 | List.duplicate(5, 19)])])])

      parent = %{lineage("parent", nil) | genome: parent_genome}
      child = %{lineage("child", "parent") | genome: child_genome}

      model = Phylogeny.build([parent, child], [])

      child_node = Enum.find(model.nodes, &(&1.id == "child"))
      parent_node = Enum.find(model.nodes, &(&1.id == "parent"))

      expected = Arkea.Genome.PDistance.distance(parent_genome, child_genome)

      assert child_node.branch_length > 0.0
      assert_in_delta child_node.branch_length, expected, 1.0e-9

      # The cumulative distance is monotone: the child sits further
      # from the root than the parent by at least the (px-scaled)
      # branch length.
      assert child_node.cumulative_distance > parent_node.cumulative_distance
    end

    test "every observed lineage is a leaf, only synthetic splits are internal" do
      a = lineage("a", nil)
      b = lineage("b", "a")
      c = lineage("c", "a")

      model = Phylogeny.build([a, b, c], [])

      by_id = Map.new(model.nodes, &{&1.id, &1})
      assert by_id["a"].leaf?
      assert by_id["b"].leaf?
      assert by_id["c"].leaf?
      refute by_id["split:a"].leaf?
      assert by_id["split:a"].synthetic?
    end
  end
end
