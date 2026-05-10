defmodule ArkeaWeb.Components.RestrictionInspectorPanelTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Views.RestrictionInspector
  alias ArkeaWeb.Components.RestrictionInspectorPanel

  defp dna_binding_domain, do: Domain.new([0, 0, 5], List.duplicate(10, 20))

  defp restriction_gene(tail) when length(tail) == 17 do
    Gene.from_domains([
      dna_binding_domain(),
      Domain.new([0, 0, 1], [0, 0, 0] ++ tail)
    ])
  end

  defp methylase_gene(tail) when length(tail) == 17 do
    Gene.from_domains([
      dna_binding_domain(),
      Domain.new([0, 0, 1], [3, 0, 0] ++ tail)
    ])
  end

  test "empty profile renders the no-activity placeholder" do
    catalytic_only = Gene.from_domains([Domain.new([0, 0, 1], List.duplicate(10, 20))])
    view = RestrictionInspector.from_genome(Genome.new([catalytic_only]))
    assigns = %{view: view}

    html =
      rendered_to_string(
        ~H|<RestrictionInspectorPanel.restriction_inspector_panel view={@view} />|
      )

    assert html =~ "No restriction-modification activity"
  end

  test "restriction-only genome surfaces unprotected warning" do
    genome = Genome.new([restriction_gene(List.duplicate(10, 17))])
    view = RestrictionInspector.from_genome(genome)
    assigns = %{view: view}

    html =
      rendered_to_string(
        ~H|<RestrictionInspectorPanel.restriction_inspector_panel view={@view} />|
      )

    assert html =~ "1 restriction"
    assert html =~ "0 methylase"
    assert html =~ "arkea-rm-inspector__warning"
    assert html =~ "unprotected"
    assert html =~ "arkea-rm-inspector__site-card--restriction"
  end

  test "methylase-only genome shows methylase role tag + no warning" do
    genome = Genome.new([methylase_gene(List.duplicate(10, 17))])
    view = RestrictionInspector.from_genome(genome)
    assigns = %{view: view}

    html =
      rendered_to_string(
        ~H|<RestrictionInspectorPanel.restriction_inspector_panel view={@view} />|
      )

    assert html =~ "1 methylase"
    assert html =~ "arkea-rm-inspector__site-card--methylation"
    refute html =~ "arkea-rm-inspector__warning"
  end

  test "both restriction + methylase: each site card rendered with role tag" do
    genome =
      Genome.new([
        restriction_gene(List.duplicate(10, 17)),
        methylase_gene(List.duplicate(10, 17))
      ])

    view = RestrictionInspector.from_genome(genome)
    assigns = %{view: view}

    html =
      rendered_to_string(
        ~H|<RestrictionInspectorPanel.restriction_inspector_panel view={@view} />|
      )

    assert html =~ "1 restriction"
    assert html =~ "1 methylase"
    assert html =~ "arkea-rm-inspector__role-tag--restriction"
    assert html =~ "arkea-rm-inspector__role-tag--methylation"
  end

  test "Type II palindrome surfaces the palindrome tag" do
    palindrome_full =
      [0, 0, 0, 5, 17, 9, 3, 11, 11, 7, 7, 11, 11, 3, 9, 17, 5, 0, 0, 0]

    tail = Enum.drop(palindrome_full, 3)
    genome = Genome.new([restriction_gene(tail)])
    view = RestrictionInspector.from_genome(genome)
    assigns = %{view: view}

    html =
      rendered_to_string(
        ~H|<RestrictionInspectorPanel.restriction_inspector_panel view={@view} />|
      )

    [site | _] = view.sites
    assert site.palindrome?
    assert html =~ "Type II"
    assert html =~ "palindrome"
  end
end
