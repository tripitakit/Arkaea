defmodule Arkea.Views.GeneExpressionTest do
  use ExUnit.Case, async: true

  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Views.GeneExpression

  @param_codons List.duplicate(10, 20)

  defp catalytic_gene, do: Gene.from_domains([Domain.new([0, 0, 1], @param_codons)])

  defp activator_regulator_gene do
    Gene.from_domains([
      Domain.new([0, 0, 5], @param_codons),
      Domain.new([0, 0, 6], [0 | List.duplicate(10, 19)])
    ])
  end

  defp repressor_regulator_gene do
    Gene.from_domains([
      Domain.new([0, 0, 5], @param_codons),
      Domain.new([0, 0, 6], [1 | List.duplicate(10, 19)])
    ])
  end

  test "derive/1 returns one entry per chromosome gene" do
    g = Genome.new([catalytic_gene(), catalytic_gene()])
    entries = GeneExpression.derive(g)
    assert length(entries) == 2
  end

  test "structural-only gene has base_level 1.0 and zero modulation" do
    g = Genome.new([catalytic_gene()])
    [entry] = GeneExpression.derive(g)
    assert entry.base_level == 1.0
    assert entry.modulation == 0.0
    assert entry.expression == 1.0
  end

  test "activator regulator with co-located dna_binding pushes modulation positive" do
    g = Genome.new([activator_regulator_gene()])
    [entry] = GeneExpression.derive(g)
    assert entry.modulation > 0.0
    assert entry.expression > entry.base_level
  end

  test "repressor regulator with co-located dna_binding pushes modulation negative" do
    g = Genome.new([repressor_regulator_gene()])
    [entry] = GeneExpression.derive(g)
    assert entry.modulation < 0.0
    assert entry.expression < entry.base_level
  end

  test "modulation is gene-local — no cross-gene leakage" do
    activator = activator_regulator_gene()
    bystander = catalytic_gene()
    g = Genome.new([activator, bystander])

    entries = GeneExpression.derive(g)

    activator_entry = Enum.find(entries, &(&1.gene_id == activator.id))
    bystander_entry = Enum.find(entries, &(&1.gene_id == bystander.id))

    assert activator_entry.modulation > 0.0
    assert bystander_entry.modulation == 0.0
  end

  test "expression clamps at 2.0" do
    # Stack 2 activators in one gene with a strong dna_binding so
    # base + modulation overshoots; expression is capped.
    gene =
      Gene.from_domains([
        Domain.new([0, 0, 5], List.duplicate(19, 20)),
        Domain.new([0, 0, 6], [0 | List.duplicate(10, 19)]),
        Domain.new([0, 0, 6], [0 | List.duplicate(10, 19)])
      ])

    g = Genome.new([gene])
    [entry] = GeneExpression.derive(g)
    assert entry.expression == 2.0
  end

  test "derive/2 accepts a signal_pool argument (forward-compat for 7.2b)" do
    g = Genome.new([catalytic_gene()])
    # Should not crash; result is identical to the no-arg form in v1.
    assert GeneExpression.derive(g, %{}) == GeneExpression.derive(g)
  end
end
