defmodule Arkea.Views.RestrictionInspectorTest do
  use ExUnit.Case, async: true

  alias Arkea.Ecology.Lineage
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Views.RestrictionInspector

  # Build R-M genes. Each gene has `:dna_binding` + `:catalytic_site`.
  # The catalytic_site reaction class derives from rem(sum_first_3, 6):
  #   first_3 sum 0  → :hydrolysis (restriction enzyme)
  #   first_3 sum 3  → :isomerization (methylase)
  defp dna_binding_domain do
    Domain.new([0, 0, 5], List.duplicate(10, 20))
  end

  # Restriction enzyme: prefix `[0, 0, 0]` → :hydrolysis.
  # `tail` is the remaining 17 parameter codons of the catalytic site.
  defp restriction_gene(tail) when length(tail) == 17 do
    catalytic = Domain.new([0, 0, 1], [0, 0, 0] ++ tail)
    Gene.from_domains([dna_binding_domain(), catalytic])
  end

  # Methylase: prefix `[3, 0, 0]` → :isomerization.
  defp methylase_gene(tail) when length(tail) == 17 do
    catalytic = Domain.new([0, 0, 1], [3, 0, 0] ++ tail)
    Gene.from_domains([dna_binding_domain(), catalytic])
  end

  defp founder(genome) do
    Lineage.new_founder(genome, %{phase_1: 100}, 0)
  end

  describe "from_genome/1 / build/1" do
    test "lineage with restriction-only → unprotected (would self-cleave)" do
      genome = Genome.new([restriction_gene(List.duplicate(10, 17))])

      view = RestrictionInspector.from_genome(genome)

      assert view.restriction_count == 1
      assert view.methylation_count == 0
      assert length(view.unprotected_signatures) == 1
      assert view.self_protected_signatures == []
    end

    test "lineage with methylase-only → no restriction sites" do
      genome = Genome.new([methylase_gene(List.duplicate(10, 17))])

      view = RestrictionInspector.from_genome(genome)

      assert view.restriction_count == 0
      assert view.methylation_count == 1
    end

    test "lineage with both: counts add up; signatures listed separately" do
      genome =
        Genome.new([
          restriction_gene(List.duplicate(10, 17)),
          methylase_gene(List.duplicate(10, 17))
        ])

      view = RestrictionInspector.from_genome(genome)

      assert view.restriction_count == 1
      assert view.methylation_count == 1
      assert length(view.sites) == 2
    end

    test "type classification: palindromic codon stream → Type II" do
      # Build a palindromic 17-codon tail; concatenated with [0,0,0]
      # prefix the full pattern is [0,0,0 | tail] which is NOT a
      # palindrome unless we mirror the tail too. Construct a palindrome
      # over the FULL 20-codon parameter stream.
      # Pattern: [0,0,0,3,17,9,5,11,11,7,7,11,11,5,9,17,3,0,0,0]
      # Reversed: [0,0,0,3,17,9,5,11,11,7,7,11,11,5,9,17,3,0,0,0]
      palindrome_full =
        [0, 0, 0, 3, 17, 9, 5, 11, 11, 7, 7, 11, 11, 5, 9, 17, 3, 0, 0, 0]

      tail = Enum.drop(palindrome_full, 3)
      genome = Genome.new([restriction_gene(tail)])

      view = RestrictionInspector.from_genome(genome)

      [site | _] = view.sites
      assert site.palindrome?, "Pattern should be a palindrome: #{inspect(site.pattern)}"
      assert site.type == :type_ii
      assert view.type_distribution.type_ii >= 1
    end

    test "type classification: bipartite asymmetric (zero-spacer middle) → Type I" do
      # First three codons [0,0,0] (forced by hydrolysis prefix). The
      # tail itself has zeros in its middle so the *whole* pattern's
      # middle 50% is zero-rich, marking the layout as bipartite.
      tail = [3, 17, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 11, 7, 14]
      genome = Genome.new([restriction_gene(tail)])

      view = RestrictionInspector.from_genome(genome)

      [site | _] = view.sites
      refute site.palindrome?
      assert site.type == :type_i
      assert view.type_distribution.type_i >= 1
    end

    test "type classification: asymmetric without bipartite gap → Type III" do
      tail = [3, 17, 9, 11, 5, 8, 12, 4, 7, 19, 2, 6, 13, 1, 10, 15, 18]
      genome = Genome.new([restriction_gene(tail)])

      view = RestrictionInspector.from_genome(genome)

      [site | _] = view.sites
      refute site.palindrome?
      assert site.type == :type_iii
    end

    test "site entries surface the FULL codon pattern (not just the 4-codon signature)" do
      tail = [3, 17, 9, 0, 5, 11, 7, 14, 2, 18, 6, 13, 1, 10, 15, 8, 12]
      genome = Genome.new([restriction_gene(tail)])

      view = RestrictionInspector.from_genome(genome)

      [site | _] = view.sites
      # Pattern is the FULL 20-codon parameter stream (3-codon
      # `:hydrolysis` prefix + 17-codon tail), NOT just the
      # 4-codon signature `"0,0,0,3"`.
      assert site.pattern == [0, 0, 0] ++ tail
      assert site.length_in_codons == 20
      assert site.signature == "0,0,0,3"
    end

    test "delta-only lineage (genome: nil) → empty view (no crash)" do
      l = founder(Genome.new([restriction_gene(List.duplicate(10, 17))]))
      delta_only = %{l | genome: nil}

      view = RestrictionInspector.build(delta_only)
      assert view.restriction_count == 0
      assert view.methylation_count == 0
      assert view.sites == []
      assert view.lineage_id == l.id
    end

    test "build/1 wires lineage_id; from_genome/1 leaves it nil" do
      genome = Genome.new([restriction_gene(List.duplicate(10, 17))])
      l = founder(genome)

      assert RestrictionInspector.build(l).lineage_id == l.id
      assert RestrictionInspector.from_genome(genome).lineage_id == nil
    end
  end
end
