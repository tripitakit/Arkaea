defmodule Arkea.Ecology.PhaseTest do
  @moduledoc """
  Property tests for Arkea.Ecology.Phase.

  Invariants covered:
  - dilute/1 monotonicity: every concentration after dilute is <= before
  - add_lineage / remove_lineage round-trip restores the count
  - has_lineage? is consistent with the MapSet after add/remove
  - valid?/1 and validate/1 agree on all generated phases
  - update_metabolite / update_signal store the correct value
  - dilution_rate 0.0 leaves pool values unchanged
  - dilution_rate 1.0 reduces all concentrations to 0
  - Phase.new raises on out-of-range parameters
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Arkea.Ecology.Phase
  alias Arkea.Generators

  # ---------------------------------------------------------------------------
  # Plain unit tests

  test "Phase.new/2 creates a valid phase with defaults" do
    phase = Phase.new(:surface)
    assert Phase.valid?(phase)
    assert phase.temperature == 25.0
    assert phase.ph == 7.0
    assert phase.osmolarity == 300.0
    assert phase.dilution_rate == 0.05
  end

  test "Phase.new/2 raises when temperature is out of range" do
    assert_raise ArgumentError, fn ->
      Phase.new(:surface, temperature: 200.0)
    end

    assert_raise ArgumentError, fn ->
      Phase.new(:surface, temperature: -100.0)
    end
  end

  test "Phase.new/2 raises when ph is out of range" do
    assert_raise ArgumentError, fn ->
      Phase.new(:surface, ph: 15.0)
    end

    assert_raise ArgumentError, fn ->
      Phase.new(:surface, ph: -1.0)
    end
  end

  test "Phase.new/2 raises when osmolarity is out of range" do
    assert_raise ArgumentError, fn ->
      Phase.new(:surface, osmolarity: 6000.0)
    end
  end

  test "lineage_count starts at 0" do
    phase = Phase.new(:surface)
    assert Phase.lineage_count(phase) == 0
  end

  test "add_lineage then has_lineage? returns true" do
    phase = Phase.new(:surface)
    id = Arkea.UUID.v4()
    updated = Phase.add_lineage(phase, id)
    assert Phase.has_lineage?(updated, id)
  end

  test "remove_lineage on absent id is a no-op" do
    phase = Phase.new(:surface)
    id = Arkea.UUID.v4()
    updated = Phase.remove_lineage(phase, id)
    assert Phase.lineage_count(updated) == 0
  end

  test "dilution with rate 0.0 leaves pool unchanged" do
    phase =
      Phase.new(:surface, dilution_rate: 0.0)
      |> Phase.update_metabolite(:glucose, 100.0)
      |> Phase.update_signal("c4_hsl", 50.0)

    diluted = Phase.dilute(phase)
    assert diluted.metabolite_pool[:glucose] == 100.0
    assert diluted.signal_pool["c4_hsl"] == 50.0
  end

  test "dilution with rate 1.0 reduces all concentrations to 0.0" do
    phase =
      Phase.new(:surface, dilution_rate: 1.0)
      |> Phase.update_metabolite(:glucose, 100.0)
      |> Phase.update_signal("c4_hsl", 50.0)

    diluted = Phase.dilute(phase)
    assert diluted.metabolite_pool[:glucose] == 0.0
    assert diluted.signal_pool["c4_hsl"] == 0.0
  end

  # ---------------------------------------------------------------------------
  # Property: dilute monotonicity

  property "dilute/1 never increases any metabolite concentration" do
    # Physical invariant: dilution removes material from the phase (outflow
    # exceeds inflow in the dilution step). Every metabolite concentration
    # must be <= its pre-dilution value after calling dilute/1.
    check all(phase <- Generators.phase_with_pools(), max_runs: 150) do
      before_pool = phase.metabolite_pool
      diluted = Phase.dilute(phase)
      after_pool = diluted.metabolite_pool

      Enum.each(before_pool, fn {metabolite, before_conc} ->
        after_conc = Map.get(after_pool, metabolite, 0.0)

        assert after_conc <= before_conc,
               "Metabolite #{metabolite} increased from #{before_conc} to #{after_conc} after dilution"
      end)
    end
  end

  property "dilute/1 never increases any signal concentration" do
    check all(phase <- Generators.phase_with_pools(), max_runs: 150) do
      before_pool = phase.signal_pool
      diluted = Phase.dilute(phase)
      after_pool = diluted.signal_pool

      Enum.each(before_pool, fn {signal, before_conc} ->
        after_conc = Map.get(after_pool, signal, 0.0)

        assert after_conc <= before_conc,
               "Signal #{signal} increased from #{before_conc} to #{after_conc} after dilution"
      end)
    end
  end

  property "dilute/1 applied twice: concentrations decrease or stay same both times" do
    # Monotonicity must hold for iterated dilution steps — each tick the pool
    # concentrations can only decrease or stay equal (if dilution_rate is 0).
    check all(phase <- Generators.phase_with_pools(), max_runs: 100) do
      diluted1 = Phase.dilute(phase)
      diluted2 = Phase.dilute(diluted1)

      Enum.each(phase.metabolite_pool, fn {metabolite, conc0} ->
        conc1 = Map.get(diluted1.metabolite_pool, metabolite, 0.0)
        conc2 = Map.get(diluted2.metabolite_pool, metabolite, 0.0)
        assert conc1 <= conc0
        assert conc2 <= conc1
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Property: add/remove lineage round-trip

  property "add_lineage then remove_lineage restores the original lineage_count" do
    # Set membership invariant: the MapSet of lineage UUIDs must be consistent
    # under sequential add and remove operations.
    check all(phase <- Generators.phase(), max_runs: 150) do
      id = Arkea.UUID.v4()
      before_count = Phase.lineage_count(phase)

      restored =
        phase
        |> Phase.add_lineage(id)
        |> Phase.remove_lineage(id)

      assert Phase.lineage_count(restored) == before_count
    end
  end

  property "has_lineage? is false after add then remove" do
    check all(phase <- Generators.phase(), max_runs: 150) do
      id = Arkea.UUID.v4()

      result =
        phase
        |> Phase.add_lineage(id)
        |> Phase.remove_lineage(id)

      refute Phase.has_lineage?(result, id)
    end
  end

  property "has_lineage? is true immediately after add_lineage" do
    check all(phase <- Generators.phase(), max_runs: 150) do
      id = Arkea.UUID.v4()
      updated = Phase.add_lineage(phase, id)
      assert Phase.has_lineage?(updated, id)
    end
  end

  property "adding the same lineage id twice does not increase count by 2" do
    # MapSet deduplication invariant: the lineage_ids MapSet must not allow
    # duplicates. Adding the same lineage_id twice must not increase the count.
    check all(phase <- Generators.phase(), max_runs: 150) do
      id = Arkea.UUID.v4()
      once = Phase.add_lineage(phase, id)
      twice = Phase.add_lineage(once, id)
      assert Phase.lineage_count(once) == Phase.lineage_count(twice)
    end
  end

  # ---------------------------------------------------------------------------
  # Property: valid? / validate consistency

  property "Phase.valid?/1 == (Phase.validate/1 == :ok) for all generated phases" do
    check all(phase <- Generators.phase(), max_runs: 150) do
      assert Phase.valid?(phase) == (Phase.validate(phase) == :ok)
    end
  end

  property "all generated phases pass valid?/1" do
    check all(phase <- Generators.phase(), max_runs: 150) do
      assert Phase.valid?(phase)
    end
  end

  # ---------------------------------------------------------------------------
  # Property: update_metabolite stores correct value

  property "update_metabolite stores the exact concentration" do
    metabolite_names = [:glucose, :acetate, :lactate, :atp, :oxygen]

    check all(
            phase <- Generators.phase(),
            met <- StreamData.member_of(metabolite_names),
            conc <- Generators.float_in(0.0, 1000.0),
            max_runs: 100
          ) do
      updated = Phase.update_metabolite(phase, met, conc)
      assert updated.metabolite_pool[met] == conc
    end
  end

  property "update_signal stores the exact concentration" do
    signal_names = ["c4_hsl", "c12_hsl", "ai2"]

    check all(
            phase <- Generators.phase(),
            sig <- StreamData.member_of(signal_names),
            conc <- Generators.float_in(0.0, 100.0),
            max_runs: 100
          ) do
      updated = Phase.update_signal(phase, sig, conc)
      assert updated.signal_pool[sig] == conc
    end
  end

  # ---------------------------------------------------------------------------
  # Property: dilute preserves all pool keys

  property "dilute/1 preserves all metabolite pool keys" do
    check all(phase <- Generators.phase_with_pools(), max_runs: 100) do
      diluted = Phase.dilute(phase)

      assert Enum.sort(Map.keys(phase.metabolite_pool)) ==
               Enum.sort(Map.keys(diluted.metabolite_pool))
    end
  end

  property "dilute/1 preserves all signal pool keys" do
    check all(phase <- Generators.phase_with_pools(), max_runs: 100) do
      diluted = Phase.dilute(phase)

      assert Enum.sort(Map.keys(phase.signal_pool)) ==
               Enum.sort(Map.keys(diluted.signal_pool))
    end
  end
end
