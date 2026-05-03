defmodule Arkea.Game.CommunityLabTest do
  @moduledoc """
  Tests for Phase 19 Community Mode multi-seed provisioning
  (DESIGN.md Block 8 / Community Mode).
  """
  use ExUnit.Case, async: true

  alias Arkea.Ecology.Lineage
  alias Arkea.Game.CommunityLab
  alias Arkea.Game.SeedLibrary
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene

  @param_codons List.duplicate(10, 20)

  defp build_seed_entry(name) do
    {:ok, _lib, entry} =
      SeedLibrary.save(
        SeedLibrary.new(),
        Genome.new([Gene.from_domains([Domain.new([0, 0, 1], @param_codons)])]),
        name: name
      )

    entry
  end

  describe "build_founder/3" do
    test "tags the founder lineage with the seed entry id" do
      entry = build_seed_entry("alpha")

      founder =
        CommunityLab.build_founder(entry, :surface, per_founder_abundance: 200, tick: 0)

      assert founder.original_seed_id == entry.id
      assert founder.parent_id == nil
      assert Lineage.abundance_in(founder, :surface) == 200
    end
  end

  describe "provision_community/3" do
    test "rejects an empty list" do
      assert {:error, :empty_seeds} = CommunityLab.provision_community([], :surface)
    end

    test "rejects a list above the cap" do
      seeds =
        for i <- 1..(CommunityLab.max_community_seeds() + 1) do
          build_seed_entry("seed-#{i}")
        end

      assert {:error, :too_many_seeds} =
               CommunityLab.provision_community(seeds, :surface)
    end

    test "rejects duplicate seed ids" do
      entry = build_seed_entry("alpha")

      assert {:error, :duplicate_seed_id} =
               CommunityLab.provision_community([entry, entry], :surface)
    end

    test "produces N founders each with the matching original_seed_id" do
      e1 = build_seed_entry("alpha")
      e2 = build_seed_entry("beta")

      {:ok, %{founders: [f1, f2], event: event}} =
        CommunityLab.provision_community([e1, e2], :surface,
          per_founder_abundance: 100,
          tick: 0,
          biotope_id: "test-biotope"
        )

      assert f1.original_seed_id == e1.id
      assert f2.original_seed_id == e2.id

      assert event.type == :community_provisioned
      assert event.payload.seed_ids == [e1.id, e2.id]
      assert event.payload.seed_names == ["alpha", "beta"]
      assert event.payload.founder_lineage_ids == [f1.id, f2.id]
      assert event.payload.phase_name == "surface"
      assert event.payload.biotope_id == "test-biotope"
    end

    test "founders have distinct clade_ref_ids (independent clades)" do
      e1 = build_seed_entry("alpha")
      e2 = build_seed_entry("beta")
      e3 = build_seed_entry("gamma")

      {:ok, %{founders: founders}} =
        CommunityLab.provision_community([e1, e2, e3], :surface)

      clade_refs = Enum.map(founders, & &1.clade_ref_id)
      assert length(Enum.uniq(clade_refs)) == 3
    end
  end

  describe "Lineage.original_seed_id propagation" do
    test "child lineages inherit the parent's original_seed_id automatically" do
      entry = build_seed_entry("alpha")
      founder = CommunityLab.build_founder(entry, :surface)

      child_genome =
        Genome.new([Gene.from_domains([Domain.new([0, 0, 1], @param_codons)])])

      child = Lineage.new_child(founder, child_genome, %{surface: 5}, 1)
      assert child.original_seed_id == entry.id

      grandchild = Lineage.new_child(child, child_genome, %{surface: 1}, 2)
      assert grandchild.original_seed_id == entry.id
    end

    test "founders without a seed tag stay nil" do
      genome = Genome.new([Gene.from_domains([Domain.new([0, 0, 1], @param_codons)])])
      founder = Lineage.new_founder(genome, %{surface: 100}, 0)

      assert founder.original_seed_id == nil
    end
  end
end
