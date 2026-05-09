defmodule Arkea.Sim.Phase30SmokeTest do
  @moduledoc """
  End-to-end smoke test for Phase 30 (R-M recognition site
  inspector — partial closure of L1.7).

  L1.7 says the *specificity* of restriction enzymes is *not
  inspectable at sequence level* (the legacy 4-codon signal_key
  exposes only a tiny fraction of the underlying parameter codon
  stream) and *methylation is not visualisable as a pattern*.

  Phase 30 partially closes this honesty marker by exposing the
  underlying full codon pattern + Type-I/II/III classification
  via two new surfaces:

    * `Arkea.Sim.HGT.RecognitionSite` (struct) — carries the full
      pattern, palindrome flag, type tag, role.
    * `Arkea.Sim.Phenotype.rm_profiles_detailed/1` — same scan
      as `rm_profiles/1` but returns rich `RecognitionSite.t()`
      entries.
    * `Arkea.Views.RestrictionInspector.build/1` — view-model
      that bundles the cell's restriction + methylation arsenal,
      computes self-protection vs unprotected signatures, and
      surfaces a Type-I/II/III distribution summary.

  Runtime defense (`Arkea.Sim.HGT.Defense.restriction_check/3`)
  is **unchanged** — it still keys on the legacy 4-codon
  signature, so Phase-12 R-M calibration is preserved. This is
  a strict view-layer extension.

  The remaining piece of L1.7 — *per-position methylation*
  patterns and a true sequence-level matching mechanism — is
  out of scope for this partial closure (would require
  redesigning `signal_key` semantics across the whole HGT
  stack). The rich view-layer is enough to give the player
  inspectable R-M chemistry, which is what the honesty marker
  asked for.
  """

  use ExUnit.Case, async: true

  alias Arkea.Ecology.Lineage
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Sim.HGT.RecognitionSite
  alias Arkea.Sim.Phenotype
  alias Arkea.Views.RestrictionInspector

  defp dna_binding_domain do
    Domain.new([0, 0, 5], List.duplicate(10, 20))
  end

  # `:hydrolysis` reaction class requires `rem(sum_first_3, 6) == 0`.
  defp restriction_gene(tail) when length(tail) == 17 do
    Gene.from_domains([
      dna_binding_domain(),
      Domain.new([0, 0, 1], [0, 0, 0] ++ tail)
    ])
  end

  # `:isomerization` reaction class requires `rem(sum_first_3, 6) == 3`.
  defp methylase_gene(tail) when length(tail) == 17 do
    Gene.from_domains([
      dna_binding_domain(),
      Domain.new([0, 0, 1], [3, 0, 0] ++ tail)
    ])
  end

  test "30.1 RecognitionSite — palindrome detection + Type-II classification" do
    palindrome_pattern = [3, 17, 9, 9, 17, 3]
    asymmetric_pattern = [3, 17, 9, 0, 1, 4]

    palindrome_site = RecognitionSite.new("3,17,9,9", palindrome_pattern, :restriction)
    asymmetric_site = RecognitionSite.new("3,17,9,0", asymmetric_pattern, :restriction)

    assert palindrome_site.palindrome?
    assert palindrome_site.type == :type_ii

    refute asymmetric_site.palindrome?
    assert asymmetric_site.type in [:type_i, :type_iii]
  end

  test "30.2 Phenotype.rm_profiles_detailed/1 — restriction + methylation surfaces with full patterns" do
    genome =
      Genome.new([
        restriction_gene(List.duplicate(7, 17)),
        methylase_gene(List.duplicate(11, 17))
      ])

    %{restriction_sites: rest, methylation_sites: methyl} =
      Phenotype.rm_profiles_detailed(genome)

    assert length(rest) == 1
    assert length(methyl) == 1

    [rest_site] = rest
    [methyl_site] = methyl

    assert rest_site.role == :restriction
    assert rest_site.length_in_codons == 20
    assert rest_site.pattern == [0, 0, 0] ++ List.duplicate(7, 17)

    assert methyl_site.role == :methylation
    assert methyl_site.length_in_codons == 20
    assert methyl_site.pattern == [3, 0, 0] ++ List.duplicate(11, 17)
  end

  test "30.3 RestrictionInspector — surfaces full sequence + type distribution + self-protection check" do
    # Palindrome over the FULL 20-codon stream. Prefix is forced to
    # `[0,0,0]` (hydrolysis), so the suffix must end with `[0,0,0]`
    # too to land a palindrome. Different first-tail-codon vs the
    # bipartite seed → different 4-codon signatures.
    palindrome_full = [0, 0, 0, 5, 17, 9, 3, 11, 11, 7, 7, 11, 11, 3, 9, 17, 5, 0, 0, 0]
    palindrome_tail = Enum.drop(palindrome_full, 3)

    bipartite_tail = [3, 17, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 11, 7, 14]

    genome =
      Genome.new([
        restriction_gene(palindrome_tail),
        restriction_gene(bipartite_tail)
      ])

    lineage = Lineage.new_founder(genome, %{phase_1: 100}, 0)
    view = RestrictionInspector.build(lineage)

    assert view.lineage_id == lineage.id
    assert view.restriction_count == 2
    assert view.methylation_count == 0

    # Both restriction sites are unprotected (no methylase to mirror them).
    assert length(view.unprotected_signatures) == 2
    assert view.self_protected_signatures == []

    types = Enum.map(view.sites, & &1.type) |> Enum.sort()
    assert :type_i in types
    assert :type_ii in types

    # Each site exposes the full 20-codon pattern (not just the
    # 4-codon signature).
    Enum.each(view.sites, fn site ->
      assert site.length_in_codons == 20
      assert length(site.pattern) == 20
    end)
  end

  test "Defense calibration preserved — legacy `restriction_profile` (4-codon signatures) unchanged" do
    # The runtime gate keys on the 4-codon signature only; the
    # detailed profile is a strict superset that does NOT alter
    # what defense.ex sees.
    genome = Genome.new([restriction_gene(List.duplicate(13, 17))])
    legacy = Phenotype.rm_profiles(genome)
    detailed = Phenotype.rm_profiles_detailed(genome)

    legacy_signatures = legacy.restriction_profile |> Enum.sort()
    detailed_signatures = detailed.restriction_sites |> Enum.map(& &1.signature) |> Enum.sort()

    assert legacy_signatures == detailed_signatures
  end
end
