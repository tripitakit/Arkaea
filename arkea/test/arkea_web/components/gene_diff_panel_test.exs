defmodule ArkeaWeb.Components.GeneDiffPanelTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Views.GeneDiff
  alias ArkeaWeb.Components.GeneDiffPanel

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

  test "gene_diff_panel/1 renders two strips (pinned + selected) with totals" do
    a = gene_a()
    # Mutate one parameter codon to flag as substitution.
    b = %{a | codons: List.replace_at(a.codons, 5, 19)} |> reparse!()
    diff = GeneDiff.build(a, b)
    assigns = %{diff: diff}

    html = rendered_to_string(~H|<GeneDiffPanel.gene_diff_panel diff={@diff} />|)

    assert html =~ "arkea-gene-diff"
    assert html =~ ~r/<span[^>]*class="arkea-gene-diff__row-label">\s*pinned/
    assert html =~ ~r/<span[^>]*class="arkea-gene-diff__row-label">\s*selected/
    assert html =~ "1 subs"
    assert html =~ "0 tag"
    assert html =~ "1 param"
  end

  test "type-tag substitution renders with sub-tag class (amber outline)" do
    a = gene_a()
    # Flip codon 23 (start of domain 1's type_tag).
    b = %{a | codons: List.replace_at(a.codons, 23, 7)} |> reparse!()
    diff = GeneDiff.build(a, b)
    assigns = %{diff: diff}

    html = rendered_to_string(~H|<GeneDiffPanel.gene_diff_panel diff={@diff} />|)

    assert html =~ "arkea-gene-diff__cell--sub-tag"
    assert html =~ "1 tag"
  end

  test "domain summary table flags type-changed rows" do
    a = gene_a()
    # Flip codon 2 → type_tag of domain 0 changes from [0,0,1] (catalytic_site)
    # to [0,0,4] (sum 4 mod 11 = 4 → :energy_coupling).
    b = %{a | codons: List.replace_at(a.codons, 2, 4)} |> reparse!()
    diff = GeneDiff.build(a, b)
    assigns = %{diff: diff}

    html = rendered_to_string(~H|<GeneDiffPanel.gene_diff_panel diff={@diff} />|)

    assert html =~ "arkea-gene-diff__domain-row--flipped"
    assert html =~ "catalytic_site"
    assert html =~ "energy_coupling"
  end

  test "length mismatch produces unaligned cells with striped pattern" do
    a = gene_a()
    b = Gene.from_domains([Domain.new([0, 0, 1], List.duplicate(10, 20))])
    diff = GeneDiff.build(a, b)
    assigns = %{diff: diff}

    html = rendered_to_string(~H|<GeneDiffPanel.gene_diff_panel diff={@diff} />|)

    assert html =~ "arkea-gene-diff__cell--unaligned"
  end
end
