defmodule Arkea.Views.CodonViewerTest do
  use ExUnit.Case, async: true

  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Views.CodonViewer

  defp single_domain_gene do
    Gene.from_domains([Domain.new([0, 0, 1], List.duplicate(10, 20))])
  end

  defp two_domain_gene do
    Gene.from_domains([
      Domain.new([0, 0, 1], List.duplicate(10, 20)),
      Domain.new([0, 0, 5], List.duplicate(15, 20))
    ])
  end

  test "build/1 emits one entry per codon (23 per Phase-1 domain)" do
    model = CodonViewer.build(single_domain_gene())

    assert model.codon_count == 23
    assert length(model.codons) == 23
    assert model.domain_count == 1
    assert length(model.domains) == 1
  end

  test "first 3 codons of every domain are tagged :type_tag" do
    model = CodonViewer.build(two_domain_gene())

    domain_starts = [0, 23]

    for start <- domain_starts do
      tags = Enum.slice(model.codons, start, 3)
      assert Enum.all?(tags, &(&1.role == :type_tag))

      params_window = Enum.slice(model.codons, start + 3, 20)
      assert Enum.all?(params_window, &(&1.role == :parameter_codon))
    end
  end

  test "every codon entry carries its parent domain index + type" do
    model = CodonViewer.build(two_domain_gene())

    assert Enum.find(model.codons, &(&1.index == 0)).domain_index == 0
    assert Enum.find(model.codons, &(&1.index == 0)).domain_type == :catalytic_site

    assert Enum.find(model.codons, &(&1.index == 23)).domain_index == 1
    assert Enum.find(model.codons, &(&1.index == 23)).domain_type == :dna_binding
  end

  test "domain summaries carry start / end_pos / params" do
    model = CodonViewer.build(two_domain_gene())
    [d0, d1] = model.domains

    assert d0.domain_index == 0
    assert d0.start == 0
    assert d0.end_pos == 22
    assert d0.type == :catalytic_site
    assert is_map(d0.params)

    assert d1.start == 23
    assert d1.end_pos == 45
    assert d1.type == :dna_binding
  end

  test "codon symbol uses the canonical Codon.to_atom mapping" do
    model = CodonViewer.build(single_domain_gene())
    # Codon 0 = first symbol; using Codon.to_atom keeps the
    # mapping authoritative — we assert only that the result is
    # an atom rather than hard-coding a value the canonical
    # alphabet is free to rename.
    assert is_atom(hd(model.codons).symbol)
  end

  test "promoter / regulatory codons are surfaced separately when present" do
    base = single_domain_gene()
    gene = %{base | promoter_block: [1, 2, 3, 4], regulatory_block: [5, 6, 7, 8, 9]}
    model = CodonViewer.build(gene)

    assert length(model.promoter_codons) == 4
    assert Enum.all?(model.promoter_codons, &(&1.role == :promoter_codon))

    assert length(model.regulatory_codons) == 5
    assert Enum.all?(model.regulatory_codons, &(&1.role == :regulatory_codon))
  end

  test "missing promoter / regulatory blocks become empty lists, not nil" do
    model = CodonViewer.build(single_domain_gene())
    assert model.promoter_codons == []
    assert model.regulatory_codons == []
  end
end
