defmodule Arkea.Views.GeneDiffTest do
  use ExUnit.Case, async: true

  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Views.GeneDiff

  defp reparse!(gene) do
    {:ok, g} = Gene.reparse(gene)
    g
  end

  defp gene_a do
    Gene.from_domains([
      Domain.new([0, 0, 1], List.duplicate(10, 20)),
      Domain.new([0, 0, 5], List.duplicate(15, 20))
    ])
  end

  test "two identical genes produce zero substitutions on every aligned codon" do
    g = gene_a()
    diff = GeneDiff.build(g, g)

    assert diff.substitutions == 0
    assert diff.type_tag_changes == 0
    assert diff.parameter_changes == 0
    assert diff.codon_count_a == 46
    assert diff.codon_count_b == 46
    assert length(diff.positions) == 46
    assert Enum.all?(diff.positions, &(&1.change == :match))
  end

  test "single parameter-codon flip is reported only as parameter change" do
    a = gene_a()
    b = %{a | codons: List.replace_at(a.codons, 5, 19)} |> reparse!()

    diff = GeneDiff.build(a, b)

    assert diff.substitutions == 1
    assert diff.parameter_changes == 1
    assert diff.type_tag_changes == 0

    pos5 = Enum.find(diff.positions, &(&1.index == 5))
    assert pos5.change == :substitution
    assert pos5.role == :parameter_codon
    assert pos5.domain_index == 0
    assert pos5.codon_a == 10
    assert pos5.codon_b == 19
  end

  test "type_tag substitution is counted in type_tag_changes" do
    a = gene_a()
    # Flip codon 0 of domain 1 (type_tag of second domain → index 23).
    b = %{a | codons: List.replace_at(a.codons, 23, 7)} |> reparse!()

    diff = GeneDiff.build(a, b)

    assert diff.substitutions == 1
    assert diff.type_tag_changes == 1
    assert diff.parameter_changes == 0

    pos = Enum.find(diff.positions, &(&1.index == 23))
    assert pos.role == :type_tag
    assert pos.domain_index == 1
  end

  test "domain summary flags the domain whose type changed" do
    a = gene_a()
    # type_tag of domain 0 was [0,0,1] → :catalytic_site.
    # Replacing position 2 with 4 makes [0,0,4] → rem(4,11) = 4 → :energy_coupling.
    b = %{a | codons: List.replace_at(a.codons, 2, 4)} |> reparse!()

    diff = GeneDiff.build(a, b)
    [d0, d1] = diff.domains

    assert d0.domain_index == 0
    assert d0.type_a == :catalytic_site
    assert d0.type_b == :energy_coupling
    assert d0.type_changed?
    assert d0.substitutions_in_tag == 1
    assert d0.substitutions_in_params == 0
    assert is_map(d0.params_a) and is_map(d0.params_b)

    assert d1.type_changed? == false
    assert d1.substitutions_in_tag == 0
    assert d1.substitutions_in_params == 0
  end

  test "per-domain substitution counts split between tag and params" do
    a = gene_a()
    # Flip type_tag codon at idx 0, parameter codons at idx 5 and idx 10
    # (all within domain 0), and a parameter codon at idx 30 (domain 1).
    new_codons =
      a.codons
      |> List.replace_at(0, 3)
      |> List.replace_at(5, 19)
      |> List.replace_at(10, 18)
      |> List.replace_at(30, 17)

    b = %{a | codons: new_codons} |> reparse!()

    diff = GeneDiff.build(a, b)
    assert diff.substitutions == 4
    assert diff.type_tag_changes == 1
    assert diff.parameter_changes == 3

    [d0, d1] = diff.domains
    assert d0.substitutions_in_tag == 1
    assert d0.substitutions_in_params == 2
    assert d1.substitutions_in_tag == 0
    assert d1.substitutions_in_params == 1
  end

  test "length mismatch surfaces tail positions as :unaligned with the right side" do
    a = gene_a()
    # Drop the last domain from b (so b is 23 codons, a is 46).
    b =
      Gene.from_domains([
        Domain.new([0, 0, 1], List.duplicate(10, 20))
      ])

    diff = GeneDiff.build(a, b)

    assert diff.codon_count_a == 46
    assert diff.codon_count_b == 23

    aligned = Enum.filter(diff.positions, &(&1.change in [:match, :substitution]))
    assert length(aligned) == 23

    unaligned = Enum.filter(diff.positions, &(&1.change == :unaligned))
    assert length(unaligned) == 23
    assert Enum.all?(unaligned, &(&1.role == :unaligned_a))
    assert Enum.all?(unaligned, &(&1.codon_b == nil))
  end

  test "domain summary handles different domain counts (one side missing)" do
    a = gene_a()
    b = Gene.from_domains([Domain.new([0, 0, 1], List.duplicate(10, 20))])

    diff = GeneDiff.build(a, b)
    [_d0, d1] = diff.domains

    assert d1.type_a == :dna_binding
    assert d1.type_b == nil
    refute d1.type_changed?
    assert d1.params_a |> is_map()
    assert d1.params_b == nil
  end
end
