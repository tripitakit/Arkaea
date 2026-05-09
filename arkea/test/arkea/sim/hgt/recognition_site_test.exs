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
end
