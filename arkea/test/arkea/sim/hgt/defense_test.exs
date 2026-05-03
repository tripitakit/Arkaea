defmodule Arkea.Sim.HGT.DefenseTest do
  @moduledoc """
  Property and unit tests for Phase 12 R-M defence (DESIGN.md Block 8).
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Arkea.Sim.HGT.Defense
  alias Arkea.Sim.Mutator

  describe "restriction_check/3" do
    test "passes through when the recipient has no restriction enzymes" do
      rng = Mutator.init_seed("rm-empty-recipient")
      assert {:passed, _rng_out} = Defense.restriction_check([], ["10,10,10,10"], rng)
    end

    test "passes through when payload is fully methylated at the same site" do
      rng = Mutator.init_seed("rm-methyl-bypass")
      sites = ["10,10,10,10"]

      # The donor's methylase covers exactly the recipient's recognition
      # site, so the payload should slip through deterministically (no
      # vulnerable_sites).
      assert {:passed, _rng_out} = Defense.restriction_check(sites, sites, rng)
    end

    test "vulnerable site without methylation is digested with high probability" do
      sites = ["1,2,3,4"]

      digestions =
        Enum.reduce(1..400, {0, Mutator.init_seed("rm-no-methyl")}, fn _i, {count, rng} ->
          case Defense.restriction_check(sites, [], rng) do
            {:digested, _vulnerable, rng1} -> {count + 1, rng1}
            {:passed, rng1} -> {count, rng1}
          end
        end)
        |> elem(0)

      # With @cleave_p = 0.7, we expect ~280/400 digestions.
      # The 99% confidence band around 280 is ~248..312.
      assert digestions >= 220
      assert digestions <= 340
    end

    property "no recipient restriction sites ⇒ always passed" do
      check all(
              donor_methyl <-
                StreamData.list_of(StreamData.binary(min_length: 1, max_length: 10),
                  max_length: 5
                ),
              seed_token <- StreamData.binary(min_length: 4, max_length: 16),
              max_runs: 100
            ) do
        rng = Mutator.init_seed("rm-passed-" <> Base.url_encode64(seed_token, padding: false))
        assert {:passed, _rng_out} = Defense.restriction_check([], donor_methyl, rng)
      end
    end

    property "every restriction site covered by methylation ⇒ always passed" do
      check all(
              raw_sites <-
                StreamData.list_of(StreamData.binary(min_length: 1, max_length: 10),
                  min_length: 1,
                  max_length: 5
                ),
              seed_token <- StreamData.binary(min_length: 4, max_length: 16),
              max_runs: 100
            ) do
        sites = Enum.uniq(raw_sites)

        rng =
          Mutator.init_seed("rm-methyl-full-" <> Base.url_encode64(seed_token, padding: false))

        # Methylation set is a superset of restriction sites: the entire
        # recognition repertoire is "host-modified".
        methyl = sites ++ ["extra-methyl"]
        assert {:passed, _rng_out} = Defense.restriction_check(sites, methyl, rng)
      end
    end
  end
end
