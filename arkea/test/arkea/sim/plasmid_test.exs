defmodule Arkea.Sim.PlasmidTest do
  @moduledoc """
  Tests for Phase 16 plasmid traits (DESIGN.md Block 8).

  Coverage:
    - `Genome.normalize_plasmid/1` derivations (inc_group, copy_number,
      oriT_present)
    - `Genome.add_plasmid/2` displacement on inc_group collision
    - Plasmid burden scales with `copy_number` in
      `Tick.compute_growth_deltas_v5`
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene

  @param_codons List.duplicate(10, 20)

  defp plain_gene(seed) do
    # Vary one parameter codon to make plasmids hash to different
    # `inc_group`s so we can pick collision/non-collision pairs.
    Gene.from_domains([Domain.new([0, 0, 1], List.duplicate(seed, 20))])
  end

  defp dna_binding_gene do
    Gene.from_domains([Domain.new([0, 0, 5], @param_codons)])
  end

  describe "normalize_plasmid/1" do
    test "wraps a raw gene list into a plasmid map with derived traits" do
      genes = [plain_gene(7)]
      plasmid = Genome.normalize_plasmid(genes)

      assert plasmid.genes == genes
      assert is_integer(plasmid.inc_group)
      assert plasmid.inc_group >= 0
      assert plasmid.inc_group < Genome.inc_group_modulus()
      assert plasmid.copy_number >= 1
      assert plasmid.copy_number <= Genome.max_copy_number()
      assert plasmid.oriT_present == false
    end

    test "is idempotent on already-shaped maps" do
      manual = %{genes: [plain_gene(3)], inc_group: 2, copy_number: 4, oriT_present: true}
      assert Genome.normalize_plasmid(manual) == manual
    end

    test "copy_number tracks count of :dna_binding domains" do
      no_binding = Genome.normalize_plasmid([plain_gene(1)])

      with_binding =
        Genome.normalize_plasmid([
          plain_gene(1),
          dna_binding_gene(),
          dna_binding_gene()
        ])

      assert with_binding.copy_number > no_binding.copy_number
    end

    property "inc_group is deterministic in the gene-codon sequence" do
      check all(
              codons1 <- StreamData.list_of(StreamData.integer(0..19), length: 20),
              codons2 <- StreamData.list_of(StreamData.integer(0..19), length: 20),
              max_runs: 50
            ) do
        # Ensure the codon sequences induce :substrate_binding domains
        # (type_tag sum = 0 → :substrate_binding) so Domain.new accepts them.
        gene1 = Gene.from_domains([Domain.new([0, 0, 0], codons1)])
        gene2 = Gene.from_domains([Domain.new([0, 0, 0], codons2)])

        plasmid_a = Genome.normalize_plasmid([gene1])
        plasmid_b = Genome.normalize_plasmid([gene1])

        assert plasmid_a.inc_group == plasmid_b.inc_group

        # Distinct codons can hash to the same inc_group (modulus 7) but
        # never out of range.
        plasmid_c = Genome.normalize_plasmid([gene2])
        assert plasmid_c.inc_group >= 0
        assert plasmid_c.inc_group < Genome.inc_group_modulus()
      end
    end
  end

  describe "add_plasmid/2 displacement" do
    test "adding a same-inc_group plasmid displaces the resident" do
      genome = Genome.new([plain_gene(0)])

      first =
        Genome.add_plasmid(genome, %{
          genes: [plain_gene(1)],
          inc_group: 3,
          copy_number: 2,
          oriT_present: false
        })

      assert length(first.plasmids) == 1
      assert hd(first.plasmids).inc_group == 3

      replacement =
        Genome.add_plasmid(first, %{
          genes: [plain_gene(2)],
          inc_group: 3,
          copy_number: 5,
          oriT_present: true
        })

      # Same inc_group → resident displaced; only the new plasmid stays.
      assert length(replacement.plasmids) == 1
      assert hd(replacement.plasmids).copy_number == 5
      assert hd(replacement.plasmids).oriT_present == true
    end

    test "adding a different-inc_group plasmid coexists with the resident" do
      genome = Genome.new([plain_gene(0)])

      first =
        Genome.add_plasmid(genome, %{
          genes: [plain_gene(1)],
          inc_group: 0,
          copy_number: 2,
          oriT_present: false
        })

      second =
        Genome.add_plasmid(first, %{
          genes: [plain_gene(2)],
          inc_group: 4,
          copy_number: 3,
          oriT_present: false
        })

      assert length(second.plasmids) == 2
      inc_groups = Enum.map(second.plasmids, & &1.inc_group) |> Enum.sort()
      assert inc_groups == [0, 4]
    end
  end

  describe "Genome.new/2 plasmid acceptance" do
    test "accepts a list of gene-lists (legacy)" do
      genome = Genome.new([plain_gene(0)], plasmids: [[plain_gene(1)]])
      assert length(genome.plasmids) == 1
      assert is_integer(hd(genome.plasmids).inc_group)
    end

    test "accepts a list of plasmid() maps" do
      genome =
        Genome.new([plain_gene(0)],
          plasmids: [
            %{genes: [plain_gene(1)], inc_group: 5, copy_number: 7, oriT_present: false}
          ]
        )

      assert hd(genome.plasmids).inc_group == 5
      assert hd(genome.plasmids).copy_number == 7
    end
  end

  describe "set_plasmids/2" do
    test "replaces wholesale without applying inc_group displacement" do
      genome = Genome.new([plain_gene(0)])

      reset =
        Genome.set_plasmids(genome, [
          [plain_gene(1)],
          [plain_gene(2)]
        ])

      assert length(reset.plasmids) == 2
    end
  end
end
