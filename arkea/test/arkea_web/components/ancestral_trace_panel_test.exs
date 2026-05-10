defmodule ArkeaWeb.Components.AncestralTracePanelTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Arkea.Ecology.Lineage
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Views.AncestralReconstruction
  alias ArkeaWeb.Components.AncestralTracePanel

  defp gene(weight) do
    Gene.from_domains([Domain.new([0, 0, 1], List.duplicate(weight, 20))])
  end

  defp founder(genome, tick), do: Lineage.new_founder(genome, %{phase_1: 100}, tick)

  defp child_of(parent, genome, tick),
    do: Lineage.new_child(parent, genome, %{phase_1: 100}, tick)

  test "panel renders the ancestor chain table with one row per ancestor" do
    l0 = founder(Genome.new([gene(10)]), 0)
    l1 = child_of(l0, Genome.new([gene(11)]), 5)
    l2 = child_of(l1, Genome.new([gene(12)]), 10)

    trace = AncestralReconstruction.genome_trace([l0, l1, l2], l2.id)
    assigns = %{genome_trace: trace, gene_trace: nil}

    html =
      rendered_to_string(~H|<AncestralTracePanel.ancestral_trace_panel
  genome_trace={@genome_trace}
  gene_trace={@gene_trace}
/>|)

    assert html =~ "3 ancestors"
    assert html =~ "arkea-ancestral__row--target"
    # Three lineage_id chips rendered.
    short_l0 = String.slice(l0.id, 0, 8)
    short_l2 = String.slice(l2.id, 0, 8)
    assert html =~ short_l0
    assert html =~ short_l2
  end

  test "delta-only ancestors render as 'delta-only' instead of a numeric gene_count" do
    l0 = founder(Genome.new([gene(10)]), 0)
    l1 = child_of(l0, Genome.new([gene(11)]), 5)
    # Replace l0's genome with nil to mark it delta-only.
    l0_delta = %{l0 | genome: nil}

    trace = AncestralReconstruction.genome_trace([l0_delta, l1], l1.id)
    assigns = %{genome_trace: trace, gene_trace: nil}

    html =
      rendered_to_string(~H|<AncestralTracePanel.ancestral_trace_panel
  genome_trace={@genome_trace}
  gene_trace={@gene_trace}
/>|)

    assert html =~ "delta-only"
    assert html =~ "arkea-ancestral__row--delta-only"
  end

  test "gene_trace section renders codon strips for present positions and skips lost ones" do
    l0 = founder(Genome.new([gene(10)]), 0)
    l1 = child_of(l0, Genome.new([gene(11)]), 5)

    genome_trace = AncestralReconstruction.genome_trace([l0, l1], l1.id)
    gene_trace = AncestralReconstruction.gene_trace([l0, l1], l1.id, 0)

    assigns = %{genome_trace: genome_trace, gene_trace: gene_trace}

    html =
      rendered_to_string(~H|<AncestralTracePanel.ancestral_trace_panel
  genome_trace={@genome_trace}
  gene_trace={@gene_trace}
/>|)

    assert html =~ "Gene trace at chromosome"
    assert html =~ "arkea-ancestral__codon-cell"
    assert html =~ "arkea-ancestral__gene-row--present"
  end

  test "no gene_trace passed → only genome trace rendered" do
    l0 = founder(Genome.new([gene(10)]), 0)
    trace = AncestralReconstruction.genome_trace([l0], l0.id)
    assigns = %{genome_trace: trace, gene_trace: nil}

    html =
      rendered_to_string(~H|<AncestralTracePanel.ancestral_trace_panel
  genome_trace={@genome_trace}
  gene_trace={@gene_trace}
/>|)

    refute html =~ "Gene trace at chromosome"
    assert html =~ "1 ancestor"
  end
end
