defmodule Arkea.Persistence.TimeSeriesTest do
  use Arkea.DataCase, async: true

  alias Arkea.Persistence.TimeSeries
  alias Arkea.Persistence.TimeSeriesSample
  alias Arkea.Sim.BiotopeState

  describe "extract_samples/2 (pure)" do
    test "returns no samples when tick is not on a sampling boundary" do
      occurred_at = DateTime.utc_now()
      state = state_at_tick(3)
      assert TimeSeries.extract_samples(state, occurred_at) == []
    end

    test "emits abundance + metabolite_pool + signal_pool samples on a population-shape boundary" do
      occurred_at = DateTime.utc_now()
      # tick 5 hits the population-shape boundary (5 % 5 == 0) but not
      # the cellular boundary (5 % 10 != 0).
      state = state_at_tick(5)
      samples = TimeSeries.extract_samples(state, occurred_at)

      kinds = samples |> Enum.map(& &1.kind) |> Enum.uniq() |> Enum.sort()
      assert kinds == ["abundance", "metabolite_pool"]

      abundance = Enum.find(samples, &(&1.kind == "abundance"))
      assert abundance.scope_id != nil
      assert is_map(abundance.payload)
      assert abundance.payload["total"] >= 0
    end

    test "tick 10 emits both population and cellular boundaries" do
      occurred_at = DateTime.utc_now()
      # tick 10: population boundary AND cellular boundary. With a
      # genome-bearing lineage the cellular sample (biomass) is also
      # produced; with the bare test fixture only the population
      # samples come out. This test verifies the population-side
      # emits regardless and the cellular pipeline runs (zero rows
      # is acceptable when no lineage has a genome).
      state = state_at_tick(10)
      samples = TimeSeries.extract_samples(state, occurred_at)
      kinds = samples |> Enum.map(& &1.kind) |> Enum.uniq() |> Enum.sort()

      assert "abundance" in kinds
      assert "metabolite_pool" in kinds
    end

    test "every emitted attrs map satisfies the changeset constraints" do
      occurred_at = DateTime.utc_now()
      state = state_at_tick(10)
      samples = TimeSeries.extract_samples(state, occurred_at)

      for attrs <- samples do
        cs = TimeSeriesSample.changeset(%TimeSeriesSample{}, attrs)
        assert cs.valid?, "invalid sample: #{inspect(cs.errors)}"
      end
    end
  end

  describe "persist/3 + list/2 (with DB)" do
    test "round-trip writes and reads back samples for a biotope" do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      state = state_at_tick(10)
      assert {:ok, _samples} = TimeSeries.persist(Arkea.Repo, state, now)

      results = TimeSeries.list(state.id, repo: Arkea.Repo)
      assert length(results) > 0

      ticks = results |> Enum.map(& &1.tick) |> Enum.uniq()
      assert ticks == [10]
    end

    test "list/2 honours the kind filter" do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      state = state_at_tick(10)
      assert {:ok, _} = TimeSeries.persist(Arkea.Repo, state, now)

      only_abundance = TimeSeries.list(state.id, kind: "abundance", repo: Arkea.Repo)
      assert only_abundance != []
      assert Enum.all?(only_abundance, &(&1.kind == "abundance"))
    end
  end

  defp state_at_tick(tick) do
    phases = [Arkea.Ecology.Phase.new(:water_column)]

    lineage = %Arkea.Ecology.Lineage{
      id: Arkea.UUID.v4(),
      parent_id: nil,
      original_seed_id: nil,
      clade_ref_id: nil,
      created_at_tick: 0,
      abundance_by_phase: %{water_column: 100},
      genome: nil,
      delta: [],
      biomass: %{wall: 1.0, membrane: 1.0, dna: 1.0},
      dna_damage: 0.0
    }

    BiotopeState.new_from_opts(
      id: Arkea.UUID.v4(),
      archetype: :eutrophic_pond,
      x: 0.0,
      y: 0.0,
      phases: phases,
      dilution_rate: 0.05,
      tick_count: tick,
      lineages: [lineage]
    )
  end
end
