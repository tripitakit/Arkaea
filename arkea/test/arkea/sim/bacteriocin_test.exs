defmodule Arkea.Sim.BacteriocinTest do
  @moduledoc """
  Tests for Phase 17 bacteriocin warfare (DESIGN.md Block 8).
  """
  use ExUnit.Case, async: true

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Sim.Bacteriocin

  @param_codons List.duplicate(10, 20)

  # Codons for `:catalytic_site(:hydrolysis)` — type_tag sum=0, but we
  # want sum%11 == 1 so the type is `:catalytic_site`. Use [0,0,1].
  # The `reaction_class` is rem(sum_first_3, 6); we need rem == 0 →
  # first 3 codons sum to 0 (use 0, 0, 0).
  defp catalytic_hydrolysis, do: Domain.new([0, 0, 1], [0, 0, 0 | List.duplicate(10, 17)])

  defp substrate_binding, do: Domain.new([0, 0, 0], @param_codons)
  defp transmembrane, do: Domain.new([0, 0, 2], @param_codons)
  defp surface_tag, do: Domain.new([0, 0, 9], @param_codons)
  defp catalytic_generic, do: Domain.new([0, 0, 1], @param_codons)

  defp toxin_gene do
    Gene.from_domains([substrate_binding(), transmembrane(), catalytic_hydrolysis()])
  end

  defp surface_gene, do: Gene.from_domains([surface_tag()])

  defp viable_producer_genome do
    Genome.new([toxin_gene(), surface_gene()])
  end

  defp suicide_genome do
    # Toxin gene without immunity — Phase 17 disqualifies as a producer.
    Genome.new([toxin_gene()])
  end

  defp inert_genome, do: Genome.new([Gene.from_domains([catalytic_generic()])])

  defp surface_only_genome, do: Genome.new([surface_gene()])

  describe "Bacteriocin.producer?/1" do
    test "viable producer (toxin + immunity) is recognised" do
      assert Bacteriocin.producer?(viable_producer_genome())
    end

    test "suicide producer (toxin without immunity) is rejected" do
      refute Bacteriocin.producer?(suicide_genome())
    end

    test "inert genome (no toxin) is not a producer" do
      refute Bacteriocin.producer?(inert_genome())
    end

    test "surface-only genome (no toxin) is not a producer" do
      refute Bacteriocin.producer?(surface_only_genome())
    end
  end

  describe "Bacteriocin.profile/1" do
    test "non-producer has zero secretion rate" do
      profile = Bacteriocin.profile(inert_genome())
      assert profile.producer? == false
      assert profile.secretion_rate == 0.0
    end

    test "producer has secretion rate equal to constant" do
      profile = Bacteriocin.profile(viable_producer_genome())
      assert profile.producer?
      assert profile.secretion_rate == Bacteriocin.secretion_per_cell()
    end

    test "immunity_tags reflects genome surface tags" do
      profile = Bacteriocin.profile(viable_producer_genome())
      assert MapSet.size(profile.immunity_tags) >= 1
    end
  end

  describe "Bacteriocin.step/2" do
    setup do
      phase =
        Phase.new(:surface,
          temperature: 25.0,
          ph: 7.0,
          osmolarity: 300.0,
          dilution_rate: 0.0
        )

      producer =
        Lineage.new_founder(viable_producer_genome(), %{surface: 5_000}, 0)

      target = Lineage.new_founder(inert_genome(), %{surface: 5_000}, 0)
      shared_immunity = Lineage.new_founder(surface_only_genome(), %{surface: 5_000}, 0)

      %{
        phase: phase,
        producer: producer,
        target: target,
        shared_immunity: shared_immunity
      }
    end

    test "no producers leaves the toxin pool empty and biomass intact", %{
      phase: phase,
      target: target
    } do
      {[lineage], updated_phase} = Bacteriocin.step([target], phase)

      assert updated_phase.toxin_pool == %{}
      assert lineage.biomass.wall == 1.0
    end

    test "a producer alone keeps its own wall intact (self-immunity)", %{
      phase: phase,
      producer: producer
    } do
      {[lineage], updated_phase} = Bacteriocin.step([producer], phase)

      # Producer secretes — pool gets populated — but is immune to its
      # own toxin (self-skip).
      assert Map.get(updated_phase.toxin_pool, producer.id, 0.0) > 0.0
      assert lineage.biomass.wall == 1.0
    end

    test "non-immune target loses wall integrity over many ticks", %{
      phase: phase,
      producer: producer,
      target: target
    } do
      lineages = [producer, target]

      {final_lineages, _phase} =
        Enum.reduce(1..200, {lineages, phase}, fn _i, {ls, ph} ->
          # Inject a fixed non-zero toxin concentration each tick to
          # bypass the per-tick dilution-recovery balance and force a
          # cumulative damage trace.
          ph = %{ph | toxin_pool: %{producer.id => 5.0}}
          Bacteriocin.step(ls, ph)
        end)

      target_after = Enum.find(final_lineages, fn l -> l.id == target.id end)
      assert target_after.biomass.wall < 0.5
    end

    test "lineage sharing a surface tag is shielded from the producer's toxin", %{
      phase: phase,
      producer: producer,
      shared_immunity: shielded
    } do
      lineages = [producer, shielded]

      {final_lineages, _phase} =
        Enum.reduce(1..200, {lineages, phase}, fn _i, {ls, ph} ->
          ph = %{ph | toxin_pool: %{producer.id => 5.0}}
          Bacteriocin.step(ls, ph)
        end)

      shielded_after = Enum.find(final_lineages, fn l -> l.id == shielded.id end)
      assert shielded_after.biomass.wall == 1.0
    end
  end
end
