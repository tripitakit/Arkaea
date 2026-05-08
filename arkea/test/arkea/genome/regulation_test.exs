defmodule Arkea.Genome.RegulationTest do
  use ExUnit.Case, async: true

  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Genome.Regulation

  defp base_gene(opts \\ []) do
    base = Gene.from_domains([Domain.new([0, 0, 1], List.duplicate(10, 20))])
    Map.merge(base, Map.new(opts))
  end

  describe "promoter_sites/1" do
    test "returns [] for nil block / nil gene" do
      assert Regulation.promoter_sites(nil) == []
      assert Regulation.promoter_sites(base_gene()) == []
      assert Regulation.promoter_sites(base_gene(promoter_block: nil)) == []
    end

    test "parses one binding site every 4 codons" do
      gene = base_gene(promoter_block: [3, 7, 11, 19])

      assert [site] = Regulation.promoter_sites(gene)
      assert site.signature == "3,7,11"
      # 19 / 19 = 1.0 (max strength)
      assert_in_delta site.strength, 1.0, 1.0e-9
    end

    test "drops the trailing partial stride (< 4 codons)" do
      # 6 codons → 1 full site + 2-codon trailing → 1 site total
      gene = base_gene(promoter_block: [1, 2, 3, 10, 99, 99])
      sites = Regulation.promoter_sites(gene)
      assert length(sites) == 1
      assert hd(sites).signature == "1,2,3"
    end

    test "supports multiple sites" do
      gene = base_gene(promoter_block: [1, 2, 3, 10, 4, 5, 6, 0])
      sites = Regulation.promoter_sites(gene)
      assert length(sites) == 2
      assert Enum.map(sites, & &1.signature) == ["1,2,3", "4,5,6"]
    end

    test "strength clamps to 0.0..1.0 for any int input" do
      gene = base_gene(promoter_block: [0, 0, 0, 0, 0, 0, 0, 19])
      [low, high] = Regulation.promoter_sites(gene)
      assert low.strength == 0.0
      assert_in_delta high.strength, 1.0, 1.0e-9
    end
  end

  describe "riboswitches/1" do
    test "returns [] for nil block / nil gene" do
      assert Regulation.riboswitches(nil) == []
      assert Regulation.riboswitches(base_gene()) == []
      assert Regulation.riboswitches(base_gene(regulatory_block: nil)) == []
    end

    test "parses one entry every 5 codons" do
      # metabolite=3, threshold=10/19, mode=0 → :activator, magnitude=19/19=1.0
      gene = base_gene(regulatory_block: [3, 10, 0, 0, 19])

      assert [r] = Regulation.riboswitches(gene)
      assert r.metabolite_id == 3
      assert_in_delta r.threshold, 10 / 19, 1.0e-9
      assert r.mode == :activator
      assert_in_delta r.magnitude, 1.0, 1.0e-9
    end

    test "metabolite_id wraps mod 13 to stay inside the canonical metabolite range" do
      gene = base_gene(regulatory_block: [16, 0, 0, 0, 0])
      [r] = Regulation.riboswitches(gene)
      assert r.metabolite_id == rem(16, 13)
      assert r.metabolite_id == 3
    end

    test "mode = repressor when mode codon is odd" do
      gene = base_gene(regulatory_block: [0, 0, 0, 1, 0])
      [r] = Regulation.riboswitches(gene)
      assert r.mode == :repressor
    end

    test "drops the trailing partial stride (< 5 codons)" do
      # 7 codons → 1 entry + 2-codon trailing
      gene = base_gene(regulatory_block: [1, 2, 3, 4, 5, 6, 7])
      assert [_] = Regulation.riboswitches(gene)
    end

    test "supports multiple entries" do
      gene =
        base_gene(regulatory_block: [0, 0, 0, 0, 19, 1, 19, 0, 1, 0])

      [a, b] = Regulation.riboswitches(gene)
      assert a.metabolite_id == 0
      assert a.mode == :activator
      assert b.metabolite_id == 1
      assert b.mode == :repressor
    end
  end
end
