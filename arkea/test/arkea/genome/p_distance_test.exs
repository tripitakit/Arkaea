defmodule Arkea.Genome.PDistanceTest do
  use ExUnit.Case, async: true

  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Genome.PDistance

  test "distance is 0 for codon-identical genomes" do
    g = build_genome(List.duplicate(5, 20))
    assert PDistance.distance(g, g) == 0.0
  end

  test "distance is 0.0 when either argument is nil" do
    g = build_genome(List.duplicate(5, 20))
    assert PDistance.distance(nil, g) == 0.0
    assert PDistance.distance(g, nil) == 0.0
    assert PDistance.distance(nil, nil) == 0.0
  end

  test "single codon mismatch yields 1/N where N is total codons" do
    a = build_genome([5 | List.duplicate(7, 19)])
    b = build_genome([5, 5 | List.duplicate(7, 18)])

    # `from_domains` adds an extra leading codon (the gene id position)
    # but the deterministic builder appends the same regulatory and
    # promoter blocks so the total codon count is consistent.
    distance = PDistance.distance(a, b)

    assert distance > 0.0
    assert distance < 0.1
  end

  test "two completely different chromosomes yield distance close to 1" do
    a = build_genome(List.duplicate(0, 20))
    b = build_genome(List.duplicate(15, 20))

    assert PDistance.distance(a, b) > 0.5
  end

  test "extra plasmid on one side counts every codon as mismatch" do
    base = build_genome(List.duplicate(5, 20))

    plasmid_gene = Gene.from_domains([Domain.new([0, 0, 2], List.duplicate(7, 20))])
    with_plasmid = Genome.add_plasmid(base, [plasmid_gene])

    distance = PDistance.distance(base, with_plasmid)

    assert distance > 0.0
  end

  test "result is symmetric: distance(a, b) == distance(b, a)" do
    a = build_genome([1 | List.duplicate(2, 19)])
    b = build_genome([3 | List.duplicate(4, 19)])

    d1 = PDistance.distance(a, b)
    d2 = PDistance.distance(b, a)

    assert_in_delta d1, d2, 1.0e-9
  end

  defp build_genome(parameter_codons) do
    domain = Domain.new([0, 0, 0], parameter_codons)
    Genome.new([Gene.from_domains([domain])])
  end
end
