defmodule Arkea.Ecology.BiotopeTest do
  @moduledoc """
  Property tests for Arkea.Ecology.Biotope.

  Invariants covered:
  - default_phases/1 returns 2..3 phases for every valid archetype
  - Biotope.new/3 produces valid biotopes for all 8 archetypes
  - zone is a non-nil atom for every generated biotope
  - valid?/1 and validate/1 agree on all generated biotopes
  - wild?/1 is true iff owner_player_id is nil
  - all_lineage_ids is a MapSet (union of all phase lineage_ids)
  - update_phase modifies only the targeted phase
  - phase/2 returns the correct phase by name
  - Phase names are unique within any default-phases list
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Arkea.Ecology.Biotope
  alias Arkea.Ecology.Phase
  alias Arkea.Generators

  # ---------------------------------------------------------------------------
  # Plain unit tests

  test "archetypes/0 returns exactly 8 archetypes" do
    assert length(Biotope.archetypes()) == 8
  end

  test "valid_archetype?/1 accepts all 8 archetypes" do
    for arch <- Biotope.archetypes() do
      assert Biotope.valid_archetype?(arch)
    end
  end

  test "valid_archetype?/1 rejects non-archetypes" do
    refute Biotope.valid_archetype?(:coral_reef)
    refute Biotope.valid_archetype?(nil)
    refute Biotope.valid_archetype?(42)
  end

  test "Biotope.new/3 raises on unknown archetype" do
    assert_raise ArgumentError, fn ->
      Biotope.new(:alien_world, {0.0, 0.0})
    end
  end

  test "wild?/1 is true for biotopes without an owner" do
    biotope = Biotope.new(:mesophilic_soil, {0.0, 0.0})
    assert Biotope.wild?(biotope)
  end

  test "wild?/1 is false for owned biotopes" do
    owner_id = Arkea.UUID.v4()
    biotope = Biotope.new(:mesophilic_soil, {0.0, 0.0}, owner_player_id: owner_id)
    refute Biotope.wild?(biotope)
  end

  test "phase/2 returns nil for missing phase name" do
    biotope = Biotope.new(:oligotrophic_lake, {0.0, 0.0})
    assert Biotope.phase(biotope, :nonexistent) == nil
  end

  test "update_phase/3 raises when phase is absent" do
    biotope = Biotope.new(:oligotrophic_lake, {0.0, 0.0})

    assert_raise ArgumentError, fn ->
      Biotope.update_phase(biotope, :nonexistent, fn p -> p end)
    end
  end

  test "all_lineage_ids returns empty MapSet for fresh biotopes" do
    biotope = Biotope.new(:mesophilic_soil, {0.0, 0.0})
    assert MapSet.size(Biotope.all_lineage_ids(biotope)) == 0
  end

  # ---------------------------------------------------------------------------
  # Property: default_phases count

  property "default_phases/1 returns 2 or 3 phases for every archetype" do
    # Architectural invariant from Block 12: every biotope must have 2 or 3
    # distinct phases. A single-phase biotope has no gradient structure; more
    # than 3 phases is beyond the Phase 1 design envelope.
    check all(archetype <- StreamData.member_of(Biotope.archetypes()), max_runs: 50) do
      phases = Biotope.default_phases(archetype)
      count = length(phases)

      assert count in 2..3,
             "Archetype #{archetype} returned #{count} phases, expected 2..3"
    end
  end

  # ---------------------------------------------------------------------------
  # Property: phase names are unique within default_phases

  property "default_phases/1 returns phases with unique names" do
    # Each phase name within a biotope must be unique — phases are indexed by
    # name in the update_phase/3 and phase/2 accessors. Duplicate names would
    # make the lookup semantics ambiguous.
    check all(archetype <- StreamData.member_of(Biotope.archetypes()), max_runs: 50) do
      phases = Biotope.default_phases(archetype)
      names = Enum.map(phases, & &1.name)

      assert length(names) == length(Enum.uniq(names)),
             "Archetype #{archetype} has duplicate phase names: #{inspect(names)}"
    end
  end

  # ---------------------------------------------------------------------------
  # Property: Biotope.new for all archetypes

  property "Biotope.new/3 produces a valid biotope for every archetype" do
    check all(
            archetype <- StreamData.member_of(Biotope.archetypes()),
            x <- Generators.float_in(-1000.0, 1000.0),
            y <- Generators.float_in(-1000.0, 1000.0),
            max_runs: 100
          ) do
      biotope = Biotope.new(archetype, {x, y})
      assert Biotope.valid?(biotope)
    end
  end

  # ---------------------------------------------------------------------------
  # Property: zone is always a valid atom

  property "Biotope.new/3 always sets zone to a non-nil atom" do
    # Every archetype has a canonical ecological zone. The zone atom is used
    # for world-graph routing and display — it must never be nil or a non-atom.
    check all(biotope <- Generators.biotope(), max_runs: 100) do
      assert is_atom(biotope.zone)
      assert biotope.zone != nil
    end
  end

  # ---------------------------------------------------------------------------
  # Property: valid? / validate consistency

  property "Biotope.valid?/1 == (Biotope.validate/1 == :ok) for all generated biotopes" do
    check all(biotope <- Generators.biotope(), max_runs: 100) do
      assert Biotope.valid?(biotope) == (Biotope.validate(biotope) == :ok)
    end
  end

  # ---------------------------------------------------------------------------
  # Property: wild? consistency

  property "wild?/1 is true iff owner_player_id is nil" do
    check all(biotope <- Generators.biotope(), max_runs: 100) do
      assert Biotope.wild?(biotope) == (biotope.owner_player_id == nil)
    end
  end

  # ---------------------------------------------------------------------------
  # Property: all_lineage_ids is a MapSet

  property "all_lineage_ids/1 always returns a MapSet" do
    check all(biotope <- Generators.biotope(), max_runs: 100) do
      result = Biotope.all_lineage_ids(biotope)
      assert match?(%MapSet{}, result)
    end
  end

  property "all_lineage_ids is the union of per-phase lineage_ids" do
    # all_lineage_ids must be the exact union of all phase lineage_ids — no
    # lineage should be lost or invented when aggregating up to the biotope level.
    check all(biotope <- Generators.biotope(), max_runs: 100) do
      expected =
        Enum.reduce(biotope.phases, MapSet.new(), fn %Phase{lineage_ids: ids}, acc ->
          MapSet.union(acc, ids)
        end)

      assert Biotope.all_lineage_ids(biotope) == expected
    end
  end

  # ---------------------------------------------------------------------------
  # Property: update_phase modifies exactly one phase

  property "update_phase modifies only the targeted phase" do
    # The update_phase/3 accessor must be surgical: only the named phase changes,
    # all other phases remain identical.
    check all(biotope <- Generators.biotope(), max_runs: 100) do
      target_phase = hd(biotope.phases)
      target_name = target_phase.name
      other_phases = Enum.reject(biotope.phases, fn p -> p.name == target_name end)

      new_id = Arkea.UUID.v4()

      updated =
        Biotope.update_phase(biotope, target_name, fn p ->
          Phase.add_lineage(p, new_id)
        end)

      updated_target = Biotope.phase(updated, target_name)
      assert Phase.has_lineage?(updated_target, new_id)

      Enum.each(other_phases, fn orig_phase ->
        updated_other = Biotope.phase(updated, orig_phase.name)
        assert updated_other.lineage_ids == orig_phase.lineage_ids
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Property: phase/2 returns correct phase

  property "phase/2 returns a Phase with the requested name or nil" do
    check all(biotope <- Generators.biotope(), max_runs: 100) do
      Enum.each(biotope.phases, fn p ->
        found = Biotope.phase(biotope, p.name)
        assert found != nil
        assert found.name == p.name
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Property: default phases all pass Phase.valid?

  property "all phases in default_phases/1 pass Phase.valid?/1" do
    check all(archetype <- StreamData.member_of(Biotope.archetypes()), max_runs: 50) do
      phases = Biotope.default_phases(archetype)

      Enum.each(phases, fn phase ->
        assert Phase.valid?(phase),
               "Phase #{phase.name} in archetype #{archetype} is invalid"
      end)
    end
  end
end
