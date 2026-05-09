defmodule Arkea.Sim.Phase29SmokeTest do
  @moduledoc """
  End-to-end smoke test for Phase 29 / 29.1 — closes L1.4 (`ribosome_like
  = 1.0` no longer hardcoded; translation efficiency now generative).

  Phase 29 makes the cell's translation machinery a *selectable trait*.
  Pre-Phase-29, every lineage translated at uniform efficiency
  regardless of genome composition — a Block-5 violation
  ("everything is genome"). Post-Phase-29, `Phenotype.translation_efficiency/1`
  derives a `0..1` scalar from the genome's `ribosome_like` proxy
  composition (`:structural_fold` with `multimerization_n >= 4` co-located
  with `:catalytic_site` `reaction_class :ligation`):

    * Per-gene quality = `(stability / 0.57) × (kcat / 10.0)`, clamped.
    * Cell-level efficiency = `max` across ribosome-like genes (best
      ribosome paces the cell).
    * Genomes without explicit ribosome_like genes → `1.0` fall-through
      preserves Phase 5/6/7 calibration (gate-with-fallback pattern,
      same as Phase 25.5 / 7.2b).

  `Tick.compute_growth_deltas_v5/5` multiplies the net growth term by
  `translation_efficiency`, so mutations that degrade the ribosome's
  fold stability or peptidyl-transferase kcat now visibly reduce
  growth — exactly the selection signal that L1.4 said was missing.

  Reproducible: pure `Tick.tick/1` calls (no BiotopeServer involvement)
  to keep the assertions deterministic.
  """

  use ExUnit.Case, async: true

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Mutator
  alias Arkea.Sim.Phenotype
  alias Arkea.Sim.Tick

  # type_tag [0,0,8] → :structural_fold; last_3 = [3,3,5] → mer = 4 ✓
  defp fold_param_codons(filler), do: List.duplicate(filler, 17) ++ [3, 3, 5]

  # type_tag [0,0,1] → :catalytic_site; first_3 = [4,0,0] sum 4 → :ligation
  defp ligation_param_codons(filler), do: [4, 0, 0] ++ List.duplicate(filler, 17)

  defp ribosome_gene(fold_filler, ligation_filler) do
    Gene.from_domains([
      Domain.new([0, 0, 8], fold_param_codons(fold_filler)),
      Domain.new([0, 0, 1], ligation_param_codons(ligation_filler))
    ])
  end

  defp catalytic_gene, do: Gene.from_domains([Domain.new([0, 0, 1], List.duplicate(19, 20))])

  # A metabolic gene that BOTH binds and catalyses glucose so the
  # genome can take up ATP (the translation_efficiency multiplier
  # only has effect on a non-zero `net` growth term).
  # type_tag [0,0,0] → :substrate_binding. The first parameter codon
  # determines `target_metabolite_id = rem(first_codon, 13)`, so we
  # set it to 0 → glucose.
  defp uptake_gene do
    Gene.from_domains([
      Domain.new([0, 0, 0], [0 | List.duplicate(19, 19)]),
      Domain.new([0, 0, 1], List.duplicate(19, 20))
    ])
  end

  defp metabolic_chromosome, do: [uptake_gene()]

  defp simple_phase do
    :surface
    |> Phase.new(temperature: 25.0, ph: 7.0, osmolarity: 300.0, dilution_rate: 0.0)
    |> Phase.update_metabolite(:glucose, 500.0)
    |> Phase.update_metabolite(:oxygen, 200.0)
  end

  defp build_state(genome, abundance) do
    lineage = Lineage.new_founder(genome, %{surface: abundance}, 0)

    BiotopeState.new_from_opts(
      id: Arkea.UUID.v4(),
      archetype: :eutrophic_pond,
      phases: [simple_phase()],
      dilution_rate: 0.0,
      lineages: [lineage],
      rng_seed: Mutator.init_seed("phase-29-smoke")
    )
  end

  defp surviving_lineage(state, original_id) do
    Enum.find(state.lineages, &(&1.id == original_id))
  end

  test "29.1 — legacy genome (no ribosome_like) → translation_efficiency = 1.0 (fall-through)" do
    legacy = Genome.new([catalytic_gene()])
    assert Phenotype.translation_efficiency(legacy) == 1.0
  end

  test "29.1 — strong ribosome → high translation_efficiency, weak ribosome → low" do
    strong = Genome.new(metabolic_chromosome() ++ [ribosome_gene(19, 19)])
    weak = Genome.new(metabolic_chromosome() ++ [ribosome_gene(0, 0)])

    strong_eff = Phenotype.translation_efficiency(strong)
    weak_eff = Phenotype.translation_efficiency(weak)

    assert strong_eff > 0.8
    assert weak_eff < 0.05
  end

  test "29.1 end-to-end — strong-ribosome lineage outgrows weak-ribosome lineage over 50 ticks" do
    strong_genome = Genome.new(metabolic_chromosome() ++ [ribosome_gene(19, 19)])
    weak_genome = Genome.new(metabolic_chromosome() ++ [ribosome_gene(0, 2)])

    strong_state = build_state(strong_genome, 100)
    weak_state = build_state(weak_genome, 100)

    [strong_lineage] = strong_state.lineages
    [weak_lineage] = weak_state.lineages

    {final_strong, _} =
      Enum.reduce(1..50, {strong_state, []}, fn _, {s, evts} ->
        {s2, ev} = Tick.tick(s)
        {s2, evts ++ ev}
      end)

    {final_weak, _} =
      Enum.reduce(1..50, {weak_state, []}, fn _, {s, evts} ->
        {s2, ev} = Tick.tick(s)
        {s2, evts ++ ev}
      end)

    strong_final =
      final_strong
      |> surviving_lineage(strong_lineage.id)
      |> case do
        %Lineage{} = l -> Lineage.total_abundance(l)
        nil -> 0
      end

    weak_final =
      final_weak
      |> surviving_lineage(weak_lineage.id)
      |> case do
        %Lineage{} = l -> Lineage.total_abundance(l)
        nil -> 0
      end

    # Translation efficiency multiplies net growth — the strong
    # ribosome lineage should grow at least 1.2× faster across 50
    # ticks of identical environmental conditions. (Both lineages
    # start at 100, so the ratio is `final_strong / final_weak`.)
    assert strong_final > weak_final,
           "Expected strong-ribosome lineage to outgrow weak; got #{strong_final} vs #{weak_final}"

    if weak_final > 0 do
      ratio = strong_final / weak_final

      assert ratio > 1.2,
             "Expected ≥ 1.2× growth advantage for strong ribosome; got #{ratio}"
    end
  end

  test "29.1 backward compatibility — legacy seed (no ribosome_like) preserves growth" do
    # The fall-through path must NOT regress the pre-Phase-29
    # behaviour for genomes that were calibrated under the old
    # uniform-translation-efficiency model.
    legacy_genome = Genome.new(metabolic_chromosome())
    state = build_state(legacy_genome, 100)
    [lineage_before] = state.lineages

    {final, _} =
      Enum.reduce(1..30, {state, []}, fn _, {s, evts} ->
        {s2, ev} = Tick.tick(s)
        {s2, evts ++ ev}
      end)

    lineage_after = surviving_lineage(final, lineage_before.id)
    assert lineage_after != nil, "Legacy lineage went extinct under translation_eff=1.0 fallback"

    final_abundance = Lineage.total_abundance(lineage_after)

    assert final_abundance >= 100,
           "Legacy lineage should grow under translation_eff=1.0 fallback; got #{final_abundance}"
  end
end
