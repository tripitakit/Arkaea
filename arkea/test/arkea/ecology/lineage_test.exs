defmodule Arkea.Ecology.LineageTest do
  @moduledoc """
  Property tests for Arkea.Ecology.Lineage.

  Invariants covered:
  - Tree monotonicity: child.created_at_tick > parent.created_at_tick
  - new_child raises when tick <= parent tick
  - Abundance non-negativity: apply_growth always keeps all per-phase counts >= 0
  - total_abundance >= 0 after any sequence of growth deltas
  - valid?/1 and validate/1 agree on all generated lineages
  - Founder invariant: founder?.parent_id == nil and clade_ref_id == id
  - Child invariant: child.parent_id == parent.id
  - invalidate_fitness sets fitness_cache to nil
  - abundance_in returns 0 for absent phase names
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Arkea.Ecology.Lineage
  alias Arkea.Generators

  # ---------------------------------------------------------------------------
  # Plain unit tests

  test "new_founder creates a valid founder lineage" do
    genome = Generators.genome() |> Enum.take(1) |> hd()
    lineage = Lineage.new_founder(genome, %{surface: 100}, 0)

    assert lineage.parent_id == nil
    assert lineage.clade_ref_id == lineage.id
    assert lineage.created_at_tick == 0
    assert Lineage.founder?(lineage)
    assert Lineage.valid?(lineage)
  end

  test "new_child creates a valid child lineage" do
    genome = Generators.genome() |> Enum.take(1) |> hd()
    parent = Lineage.new_founder(genome, %{surface: 100}, 0)
    child_genome = Generators.genome() |> Enum.take(1) |> hd()
    child = Lineage.new_child(parent, child_genome, %{surface: 50}, 1)

    assert child.parent_id == parent.id
    assert child.created_at_tick == 1
    refute Lineage.founder?(child)
    assert Lineage.valid?(child)
  end

  test "new_child raises when tick == parent tick" do
    genome = Generators.genome() |> Enum.take(1) |> hd()
    parent = Lineage.new_founder(genome, %{surface: 100}, 5)
    child_genome = Generators.genome() |> Enum.take(1) |> hd()

    assert_raise ArgumentError, fn ->
      Lineage.new_child(parent, child_genome, %{surface: 50}, 5)
    end
  end

  test "new_child raises when tick < parent tick" do
    genome = Generators.genome() |> Enum.take(1) |> hd()
    parent = Lineage.new_founder(genome, %{surface: 100}, 10)
    child_genome = Generators.genome() |> Enum.take(1) |> hd()

    assert_raise ArgumentError, fn ->
      Lineage.new_child(parent, child_genome, %{surface: 50}, 9)
    end
  end

  test "abundance_in returns 0 for a phase not in the map" do
    genome = Generators.genome() |> Enum.take(1) |> hd()
    lineage = Lineage.new_founder(genome, %{surface: 100}, 0)
    assert Lineage.abundance_in(lineage, :nonexistent_phase) == 0
  end

  test "invalidate_fitness sets fitness_cache to nil" do
    genome = Generators.genome() |> Enum.take(1) |> hd()
    lineage = Lineage.new_founder(genome, %{surface: 100}, 0)
    lineage_with_fitness = %{lineage | fitness_cache: 0.9}
    invalidated = Lineage.invalidate_fitness(lineage_with_fitness)
    assert invalidated.fitness_cache == nil
  end

  test "total_abundance sums all phase abundances" do
    genome = Generators.genome() |> Enum.take(1) |> hd()
    lineage = Lineage.new_founder(genome, %{surface: 100, water_column: 50, sediment: 25}, 0)
    assert Lineage.total_abundance(lineage) == 175
  end

  # ---------------------------------------------------------------------------
  # Property: tree monotonicity

  property "child.created_at_tick > parent.created_at_tick for all generated pairs" do
    # Phylogenetic tree monotonicity: the directed parent->child relationship
    # must always flow forward in simulation time. A child cannot be born before
    # or at the same tick as its parent — this prevents cycles in the lineage
    # tree and ensures the forest is well-ordered.
    check all({parent, child} <- Generators.lineage_pair(), max_runs: 100) do
      assert child.created_at_tick > parent.created_at_tick
    end
  end

  property "child.parent_id == parent.id for all generated pairs" do
    check all({parent, child} <- Generators.lineage_pair(), max_runs: 100) do
      assert child.parent_id == parent.id
    end
  end

  # ---------------------------------------------------------------------------
  # Property: new_child raises on tick violation

  property "new_child raises when child_tick <= parent.created_at_tick" do
    # Monotonicity enforcement: the constructor must actively prevent invalid
    # parent-child tick relationships, not merely leave them as latent bugs.
    check all(
            parent <- Generators.lineage(),
            child_genome <- Generators.genome(),
            child_abunds <- Generators.abundances(),
            tick_offset <- StreamData.integer(-100..0),
            max_runs: 100
          ) do
      bad_tick = parent.created_at_tick + tick_offset

      if bad_tick >= 0 do
        assert_raise ArgumentError, fn ->
          Lineage.new_child(parent, child_genome, child_abunds, bad_tick)
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Property: abundance non-negativity after apply_growth

  property "total_abundance >= 0 after apply_growth with any delta" do
    # Population invariant: no lineage can have negative cell counts under any
    # growth scenario, even when negative deltas (mortality) exceed current
    # abundance. The apply_growth function must clamp at zero.
    check all(
            lineage <- Generators.lineage(),
            deltas <- Generators.growth_deltas(),
            max_runs: 200
          ) do
      updated = Lineage.apply_growth(lineage, deltas)
      assert Lineage.total_abundance(updated) >= 0
    end
  end

  property "all per-phase counts are >= 0 after apply_growth" do
    check all(
            lineage <- Generators.lineage(),
            deltas <- Generators.growth_deltas(),
            max_runs: 200
          ) do
      updated = Lineage.apply_growth(lineage, deltas)

      Enum.each(updated.abundance_by_phase, fn {_phase, count} ->
        assert count >= 0
      end)
    end
  end

  property "apply_growth with positive delta increases abundance for that phase" do
    check all(
            lineage <- Generators.lineage(),
            phase_name <- StreamData.member_of([:surface, :water_column, :sediment]),
            max_runs: 150
          ) do
      delta = %{phase_name => 100}
      before_count = Lineage.abundance_in(lineage, phase_name)
      updated = Lineage.apply_growth(lineage, delta)
      after_count = Lineage.abundance_in(updated, phase_name)

      assert after_count == before_count + 100
    end
  end

  property "apply_growth invalidates fitness_cache" do
    check all(
            lineage <- Generators.lineage(),
            deltas <- Generators.growth_deltas(),
            max_runs: 100
          ) do
      updated = Lineage.apply_growth(lineage, deltas)
      assert updated.fitness_cache == nil
    end
  end

  # ---------------------------------------------------------------------------
  # Property: valid? / validate consistency

  property "Lineage.valid?/1 == (Lineage.validate/1 == :ok) for generated lineages" do
    check all(lineage <- Generators.lineage(), max_runs: 100) do
      assert Lineage.valid?(lineage) == (Lineage.validate(lineage) == :ok)
    end
  end

  property "all generated founder lineages pass valid?/1" do
    check all(lineage <- Generators.lineage(), max_runs: 100) do
      assert Lineage.valid?(lineage)
    end
  end

  property "all generated child lineages pass valid?/1" do
    check all({_parent, child} <- Generators.lineage_pair(), max_runs: 100) do
      assert Lineage.valid?(child)
    end
  end

  # ---------------------------------------------------------------------------
  # Property: founder invariants

  property "founder.clade_ref_id == founder.id for all generated founders" do
    check all(lineage <- Generators.lineage(), max_runs: 100) do
      assert lineage.clade_ref_id == lineage.id
    end
  end

  property "founder.parent_id is nil for all generated founders" do
    check all(lineage <- Generators.lineage(), max_runs: 100) do
      assert lineage.parent_id == nil
    end
  end

  # ---------------------------------------------------------------------------
  # Property: abundance_in is consistent with the abundance_by_phase map

  property "abundance_in returns the exact value stored in the map" do
    check all(lineage <- Generators.lineage(), max_runs: 100) do
      Enum.each(lineage.abundance_by_phase, fn {phase_name, count} ->
        assert Lineage.abundance_in(lineage, phase_name) == count
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Property: apply_growth multiple times is safe

  property "apply_growth composed multiple times never produces negative counts" do
    check all(
            lineage <- Generators.lineage(),
            deltas1 <- Generators.growth_deltas(),
            deltas2 <- Generators.growth_deltas(),
            max_runs: 100
          ) do
      result =
        lineage
        |> Lineage.apply_growth(deltas1)
        |> Lineage.apply_growth(deltas2)

      Enum.each(result.abundance_by_phase, fn {_phase, count} ->
        assert count >= 0
      end)
    end
  end
end
