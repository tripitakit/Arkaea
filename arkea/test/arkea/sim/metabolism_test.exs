defmodule Arkea.Sim.MetabolismTest do
  @moduledoc """
  Tests for `Arkea.Sim.Metabolism` — Michaelis-Menten kinetics and ATP yield
  (Phase 5, IMPLEMENTATION-PLAN.md §5).

  Coverage:
  - Unit tests for `uptake_rate/3` boundary conditions and the MM definition.
  - Unit tests for `atp_yield/1` with known uptake maps.
  - Property tests: `uptake_rate` bounded in [0, kcat] for any non-negative S.
  - Property tests: `compute_uptake` never consumes more than is in the pool.
  - Metabolite catalogue: `metabolite_atom/1` maps 0..12 to canonical atoms.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Arkea.Sim.Metabolism

  # ---------------------------------------------------------------------------
  # Unit: uptake_rate/3 boundary conditions

  test "uptake_rate is 0.0 when concentration == 0.0" do
    assert Metabolism.uptake_rate(1.0, 1.0, 0.0) == 0.0
    assert Metabolism.uptake_rate(10.0, 0.5, 0.0) == 0.0
  end

  test "uptake_rate satisfies MM definition: uptake_rate(1.0, 1.0, 1.0) == 0.5" do
    # v = kcat * S / (Km + S) = 1.0 * 1.0 / (1.0 + 1.0) = 0.5
    assert_in_delta Metabolism.uptake_rate(1.0, 1.0, 1.0), 0.5, 1.0e-9
  end

  test "uptake_rate approaches kcat at saturation (S >> Km)" do
    # S = 100.0, Km = 0.1 → v ≈ kcat * 100/100.1 ≈ kcat (within 0.2%)
    kcat = 1.0
    km = 0.1
    concentration = 100.0
    rate = Metabolism.uptake_rate(kcat, km, concentration)
    # Should be within 1% of kcat
    assert_in_delta rate, kcat, 0.01
  end

  test "uptake_rate is approximately linear when S << Km" do
    # v ≈ kcat * S / Km when S << Km (error = O(S²/Km²))
    kcat = 2.0
    km = 100.0
    concentration = 0.1
    # linear approx: v_lin = kcat * S / Km = 0.002
    # exact MM:      v_mm  = kcat * S / (Km + S) = 2.0 * 0.1 / 100.1 ≈ 0.001998
    # relative error ≈ S/Km = 0.001 = 0.1% — within 1e-4 absolute tolerance
    expected_linear = kcat * concentration / km
    rate = Metabolism.uptake_rate(kcat, km, concentration)
    assert_in_delta rate, expected_linear, 1.0e-4
  end

  # ---------------------------------------------------------------------------
  # Unit: atp_yield/1

  test "atp_yield for glucose-only uptake: 10.0 glucose × 2.0 coeff = 20.0" do
    assert_in_delta Metabolism.atp_yield(%{glucose: 10.0}), 20.0, 1.0e-9
  end

  test "atp_yield for oxygen-only uptake is 0.0 (oxygen is electron acceptor)" do
    assert Metabolism.atp_yield(%{oxygen: 50.0}) == 0.0
  end

  test "atp_yield for no3-only uptake is 0.0 (no3 is electron acceptor)" do
    assert Metabolism.atp_yield(%{no3: 30.0}) == 0.0
  end

  test "atp_yield for mixed uptake sums correctly" do
    # glucose: 10.0 × 2.0 = 20.0
    # acetate: 5.0  × 1.0 = 5.0
    # h2s:     2.0  × 0.6 = 1.2
    # total = 26.2
    result = Metabolism.atp_yield(%{glucose: 10.0, acetate: 5.0, h2s: 2.0})
    assert_in_delta result, 26.2, 1.0e-9
  end

  test "atp_yield for empty uptake map is 0.0" do
    assert Metabolism.atp_yield(%{}) == 0.0
  end

  test "atp_yield for unknown metabolite keys contributes 0.0" do
    # metabolites not in @atp_coefficients are ignored (coeff = 0.0)
    assert Metabolism.atp_yield(%{unknown_thing: 99.9}) == 0.0
  end

  # ---------------------------------------------------------------------------
  # Unit: metabolite_atom/1 catalogue

  test "metabolite_atom maps 0..12 to the canonical atom list" do
    expected = [
      :glucose,
      :acetate,
      :lactate,
      :co2,
      :ch4,
      :h2,
      :oxygen,
      :nh3,
      :no3,
      :h2s,
      :so4,
      :iron,
      :po4
    ]

    for {id, atom} <- Enum.with_index(expected, fn el, idx -> {idx, el} end) do
      assert Metabolism.metabolite_atom(id) == atom,
             "metabolite_atom(#{id}) should be #{atom}"
    end
  end

  test "canonical_metabolites/0 returns all 13 metabolites in order" do
    mets = Metabolism.canonical_metabolites()
    assert length(mets) == 13
    assert hd(mets) == :glucose
    assert List.last(mets) == :po4
  end

  # ---------------------------------------------------------------------------
  # Property: uptake_rate is bounded in [0.0, kcat]

  property "uptake_rate is in [0.0, kcat] for any non-negative concentration" do
    check all(
            kcat <- StreamData.float(min: 0.0, max: 100.0),
            km <- StreamData.float(min: 0.001, max: 100.0),
            concentration <- StreamData.float(min: 0.0, max: 10_000.0),
            max_runs: 300
          ) do
      rate = Metabolism.uptake_rate(kcat, km, concentration)

      assert rate >= 0.0,
             "uptake_rate returned negative value #{rate} (kcat=#{kcat}, km=#{km}, S=#{concentration})"

      assert rate <= kcat + 1.0e-9,
             "uptake_rate #{rate} exceeded kcat #{kcat} (km=#{km}, S=#{concentration})"
    end
  end

  # ---------------------------------------------------------------------------
  # Property: uptake_rate is monotonically non-decreasing in concentration

  property "uptake_rate is monotonically non-decreasing in concentration" do
    check all(
            kcat <- StreamData.float(min: 0.01, max: 10.0),
            km <- StreamData.float(min: 0.01, max: 10.0),
            s1 <- StreamData.float(min: 0.0, max: 1000.0),
            delta <- StreamData.float(min: 0.0, max: 100.0),
            max_runs: 200
          ) do
      s2 = s1 + delta
      r1 = Metabolism.uptake_rate(kcat, km, s1)
      r2 = Metabolism.uptake_rate(kcat, km, s2)

      assert r2 >= r1 - 1.0e-9,
             "uptake_rate not monotone: S=#{s1} → r=#{r1}, S=#{s2} → r=#{r2}"
    end
  end

  # ---------------------------------------------------------------------------
  # Property: compute_uptake never consumes more than available in pool

  property "compute_uptake does not consume more than the pool concentration" do
    check all(
            pool_glucose <- StreamData.float(min: 0.0, max: 1000.0),
            pool_oxygen <- StreamData.float(min: 0.0, max: 500.0),
            km <- StreamData.float(min: 0.01, max: 50.0),
            kcat <- StreamData.float(min: 0.0, max: 10.0),
            abundance <- StreamData.integer(0..10_000),
            max_runs: 200
          ) do
      affinities = %{
        glucose: %{km: km, kcat: kcat},
        oxygen: %{km: km * 2.0, kcat: kcat * 0.5}
      }

      pool = %{glucose: pool_glucose, oxygen: pool_oxygen}
      uptake = Metabolism.compute_uptake(affinities, pool, abundance)

      for {metabolite, consumed} <- uptake do
        available = Map.get(pool, metabolite, 0.0)

        assert consumed <= available + 1.0e-9,
               "compute_uptake consumed #{consumed} of #{metabolite} " <>
                 "but only #{available} was available"

        assert consumed >= 0.0,
               "compute_uptake returned negative uptake #{consumed} for #{metabolite}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Property: atp_yield is non-negative for any uptake map with canonical atoms

  property "atp_yield is non-negative for any non-negative uptake map" do
    # Build a map by generating pairs and converting with Map.new (avoids the
    # StreamData.map_of uniqueness constraint on small key sets).
    metabolites = Metabolism.canonical_metabolites()

    check all(
            pairs <-
              StreamData.list_of(
                StreamData.bind(StreamData.member_of(metabolites), fn met ->
                  StreamData.bind(StreamData.float(min: 0.0, max: 1000.0), fn amount ->
                    StreamData.constant({met, amount})
                  end)
                end),
                max_length: 13
              ),
            max_runs: 200
          ) do
      amounts = Map.new(pairs)
      result = Metabolism.atp_yield(amounts)

      assert result >= 0.0,
             "atp_yield returned negative value #{result} for uptake #{inspect(amounts)}"
    end
  end
end
