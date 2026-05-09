defmodule Arkea.Sim.HGT.RecognitionSiteTest do
  use ExUnit.Case, async: true

  alias Arkea.Sim.HGT.RecognitionSite

  describe "palindrome?/1" do
    test "exact palindrome → true" do
      assert RecognitionSite.palindrome?([3, 17, 9, 9, 17, 3])
    end

    test "single asymmetric position → false (zero tolerance)" do
      refute RecognitionSite.palindrome?([3, 17, 9, 9, 17, 4])
    end

    test "empty list is trivially palindromic" do
      assert RecognitionSite.palindrome?([])
    end

    test "single codon is trivially palindromic" do
      assert RecognitionSite.palindrome?([7])
    end
  end

  describe "classify_type/2" do
    test "palindrome → :type_ii (Type II — EcoRI-like)" do
      pattern = [3, 17, 9, 9, 17, 3]
      assert RecognitionSite.classify_type(pattern, true) == :type_ii
    end

    test "asymmetric short site → :type_iii (Type III)" do
      pattern = [3, 17, 9, 0, 1]
      assert RecognitionSite.classify_type(pattern, false) == :type_iii
    end

    test "bipartite layout (clusters separated by 0-spacer) → :type_i" do
      # Two specific clusters at the ends, zero-rich middle (≥ 50 % zeros).
      pattern = [3, 17, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 11, 7, 14]
      refute RecognitionSite.palindrome?(pattern)
      assert RecognitionSite.classify_type(pattern, false) == :type_i
    end

    test "asymmetric long site without bipartite gap → :type_iii" do
      pattern = [3, 17, 9, 11, 5, 8, 12, 4, 7, 19, 2, 6, 13, 1, 10, 15, 5, 11, 7, 14]
      refute RecognitionSite.palindrome?(pattern)
      assert RecognitionSite.classify_type(pattern, false) == :type_iii
    end
  end

  describe "new/3" do
    test "carries signature, pattern, type, role" do
      site = RecognitionSite.new("3,17,9,0", [3, 17, 9, 0, 0, 0, 0, 12], :restriction)

      assert site.signature == "3,17,9,0"
      assert site.pattern == [3, 17, 9, 0, 0, 0, 0, 12]
      assert site.length_in_codons == 8
      assert site.role == :restriction
      assert site.palindrome? == false
      assert site.type in [:type_i, :type_iii]
    end

    test "palindromic pattern produces type_ii" do
      site = RecognitionSite.new("3,17,9,0", [3, 17, 9, 9, 17, 3], :methylation)
      assert site.type == :type_ii
      assert site.palindrome?
      assert site.role == :methylation
    end
  end

  describe "Phase 32 / L1.7 refinement — complement palindromes" do
    test "complement palindrome (c → 19 - c) is detected as a palindrome" do
      # 19 - 3 = 16; pattern reverse-complement = [3, 16] when reversed.
      # Build: [3, 16] → reverse [16, 3] → complement [3, 16] → equals
      # original → complement palindrome.
      pattern = [3, 16]
      assert RecognitionSite.palindrome?(pattern)
      assert RecognitionSite.palindrome_kind(pattern) == :complement
    end

    test "exact palindrome takes priority over complement classification" do
      pattern = [5, 9, 9, 5]
      assert RecognitionSite.palindrome_kind(pattern) == :exact
    end

    test "Type II classification picks up complement palindromes (textbook EcoRI shape)" do
      # 6-codon complement palindrome: [3, 17, 9, 10, 2, 16]
      # reverse: [16, 2, 10, 9, 17, 3]
      # complement: [3, 17, 9, 10, 2, 16] — equals original ⇒ complement palindrome.
      pattern = [3, 17, 9, 10, 2, 16]
      assert RecognitionSite.palindrome_kind(pattern) == :complement
      site = RecognitionSite.new("3,17,9,10", pattern, :restriction)
      assert site.type == :type_ii
    end

    test "neither exact nor complement palindrome → :none" do
      pattern = [3, 17, 9, 0, 5, 11]
      assert RecognitionSite.palindrome_kind(pattern) == :none
      refute RecognitionSite.palindrome?(pattern)
    end
  end

  describe "Phase 32 / L1.7 refinement — kcat-modulated methylation" do
    test "high kcat (≈ 10) → full coverage" do
      pattern = List.duplicate(10, 20)
      base = RecognitionSite.new("10,10,10,10", pattern, :methylation)
      scaled = RecognitionSite.scale_methylation_to_kcat(base, 10.0)

      assert MapSet.size(scaled.methylated_positions) == length(pattern)
    end

    test "low kcat (≈ 2) → ~20 % coverage" do
      pattern = List.duplicate(10, 20)
      base = RecognitionSite.new("10,10,10,10", pattern, :methylation)
      scaled = RecognitionSite.scale_methylation_to_kcat(base, 2.0)

      assert MapSet.size(scaled.methylated_positions) == 4
      # Coverage runs from the 5' end (positions 0..n-1).
      assert MapSet.equal?(scaled.methylated_positions, MapSet.new([0, 1, 2, 3]))
    end

    test "kcat = 0 → zero coverage (no methylation marks)" do
      pattern = List.duplicate(10, 20)
      base = RecognitionSite.new("10,10,10,10", pattern, :methylation)
      scaled = RecognitionSite.scale_methylation_to_kcat(base, 0.0)

      assert MapSet.size(scaled.methylated_positions) == 0
    end

    test "kcat above 10 (or nil) saturates at full coverage" do
      pattern = List.duplicate(10, 20)
      base = RecognitionSite.new("10,10,10,10", pattern, :methylation)

      assert MapSet.size(
               RecognitionSite.scale_methylation_to_kcat(base, 25.0).methylated_positions
             ) ==
               length(pattern)

      assert MapSet.size(
               RecognitionSite.scale_methylation_to_kcat(base, nil).methylated_positions
             ) ==
               length(pattern)
    end

    test "restriction sites are unaffected by kcat scaling" do
      pattern = List.duplicate(10, 20)
      base = RecognitionSite.new("10,10,10,10", pattern, :restriction)
      scaled = RecognitionSite.scale_methylation_to_kcat(base, 5.0)

      # Restriction sites carry no methylation marks regardless of kcat.
      assert MapSet.size(scaled.methylated_positions) == 0
      assert scaled.role == :restriction
    end
  end

  describe "Phase 31 / L1.7 full closure — methylated_positions + protected_by?" do
    test "methylase site is fully methylated by default (covers every codon position)" do
      pattern = [3, 17, 9, 0, 5, 11]
      methylase = RecognitionSite.new("3,17,9,0", pattern, :methylation)

      assert MapSet.equal?(
               methylase.methylated_positions,
               MapSet.new(0..(length(pattern) - 1)//1)
             )
    end

    test "restriction site has empty methylated_positions" do
      restriction = RecognitionSite.new("3,17,9,0", [3, 17, 9, 0, 5, 11], :restriction)
      assert MapSet.size(restriction.methylated_positions) == 0
    end

    test "with_methylated_positions/2 narrows the methylation coverage" do
      pattern = [3, 17, 9, 0, 5, 11]
      methylase = RecognitionSite.new("3,17,9,0", pattern, :methylation)

      partial = RecognitionSite.with_methylated_positions(methylase, [0, 2, 4])
      assert MapSet.equal?(partial.methylated_positions, MapSet.new([0, 2, 4]))

      # Out-of-range positions are silently dropped.
      out_of_range =
        RecognitionSite.with_methylated_positions(methylase, [-1, 0, 99, length(pattern)])

      assert MapSet.equal?(out_of_range.methylated_positions, MapSet.new([0]))
    end

    test "protected_by?/2 — full-coverage methylase protects matching restriction site" do
      pattern = [3, 17, 9, 0, 5, 11]
      restriction = RecognitionSite.new("3,17,9,0", pattern, :restriction)
      methylase = RecognitionSite.new("3,17,9,0", pattern, :methylation)

      assert RecognitionSite.protected_by?(restriction, [methylase])
    end

    test "protected_by?/2 — partial-coverage methylase does NOT protect (one position uncovered)" do
      pattern = [3, 17, 9, 0, 5, 11]
      restriction = RecognitionSite.new("3,17,9,0", pattern, :restriction)

      methylase =
        RecognitionSite.new("3,17,9,0", pattern, :methylation)
        |> RecognitionSite.with_methylated_positions([0, 1, 2, 3, 4])

      # Position 5 is uncovered.
      refute RecognitionSite.protected_by?(restriction, [methylase])
    end

    test "protected_by?/2 — methylase with same signature but DIFFERENT pattern does not protect" do
      restriction = RecognitionSite.new("3,17,9,0", [3, 17, 9, 0, 5, 11], :restriction)
      # Same 4-codon signature `"3,17,9,0"` but different downstream codons.
      methylase = RecognitionSite.new("3,17,9,0", [3, 17, 9, 0, 7, 13], :methylation)

      refute RecognitionSite.protected_by?(restriction, [methylase])
    end

    test "protected_by?/2 — multiple partial methylases collectively cover the pattern" do
      pattern = [3, 17, 9, 0, 5, 11]
      restriction = RecognitionSite.new("3,17,9,0", pattern, :restriction)

      base = RecognitionSite.new("3,17,9,0", pattern, :methylation)
      first_half = RecognitionSite.with_methylated_positions(base, [0, 1, 2])
      second_half = RecognitionSite.with_methylated_positions(base, [3, 4, 5])

      assert RecognitionSite.protected_by?(restriction, [first_half, second_half])
    end
  end
end
