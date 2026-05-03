defmodule Arkea.Game.SeedLibraryTest do
  @moduledoc """
  Tests for Phase 19 Community Mode SeedLibrary (DESIGN.md Block 8 /
  Community Mode).
  """
  use ExUnit.Case, async: true

  alias Arkea.Game.SeedLibrary
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene

  @param_codons List.duplicate(10, 20)

  defp simple_genome do
    Genome.new([Gene.from_domains([Domain.new([0, 0, 1], @param_codons)])])
  end

  describe "new/0" do
    test "starts empty" do
      assert SeedLibrary.new() == %{}
    end
  end

  describe "save/3" do
    test "accepts a valid genome and assigns an id" do
      genome = simple_genome()

      {:ok, lib, entry} =
        SeedLibrary.new()
        |> SeedLibrary.save(genome, name: "alpha")

      assert is_binary(entry.id)
      assert entry.name == "alpha"
      assert entry.genome == genome
      assert Map.has_key?(lib, entry.id)
    end

    test "rejects duplicate names" do
      lib = SeedLibrary.new()
      {:ok, lib1, _e1} = SeedLibrary.save(lib, simple_genome(), name: "alpha")

      assert {:error, :duplicate_name} =
               SeedLibrary.save(lib1, simple_genome(), name: "alpha")
    end

    test "rejects entries when the library is full" do
      base = SeedLibrary.new()

      lib =
        Enum.reduce(1..SeedLibrary.max_size(), base, fn i, acc ->
          {:ok, next, _} = SeedLibrary.save(acc, simple_genome(), name: "seed-#{i}")
          next
        end)

      assert {:error, :library_full} =
               SeedLibrary.save(lib, simple_genome(), name: "overflow")
    end

    test "preserves description and timestamps when supplied" do
      {:ok, _lib, entry} =
        SeedLibrary.save(SeedLibrary.new(), simple_genome(),
          name: "alpha",
          description: "fast grower",
          created_at: 12_345
        )

      assert entry.description == "fast grower"
      assert entry.created_at == 12_345
    end
  end

  describe "delete/2 and fetch/2" do
    test "delete is idempotent on missing ids" do
      lib = SeedLibrary.new()
      assert SeedLibrary.delete(lib, "no-such-id") == lib
    end

    test "delete removes an existing entry" do
      {:ok, lib, entry} = SeedLibrary.save(SeedLibrary.new(), simple_genome(), name: "alpha")
      assert SeedLibrary.fetch(lib, entry.id) == entry

      lib2 = SeedLibrary.delete(lib, entry.id)
      assert SeedLibrary.fetch(lib2, entry.id) == nil
    end
  end

  describe "entries/1" do
    test "returns entries in arbitrary order" do
      {:ok, lib, _} = SeedLibrary.save(SeedLibrary.new(), simple_genome(), name: "a")
      {:ok, lib, _} = SeedLibrary.save(lib, simple_genome(), name: "b")
      {:ok, lib, _} = SeedLibrary.save(lib, simple_genome(), name: "c")

      names = lib |> SeedLibrary.entries() |> Enum.map(& &1.name)
      assert Enum.sort(names) == ["a", "b", "c"]
    end
  end
end
