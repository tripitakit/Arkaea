defmodule ArkeaWeb.Components.CodonTrackTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Views.CodonViewer
  alias ArkeaWeb.Components.CodonTrack

  defp two_domain_gene do
    Gene.from_domains([
      Domain.new([0, 0, 1], List.duplicate(10, 20)),
      Domain.new([0, 0, 5], List.duplicate(15, 20))
    ])
  end

  test "codon_track/1 renders one cell per codon with correct role classes" do
    view = CodonViewer.build(two_domain_gene())
    assigns = %{view: view}

    html = rendered_to_string(~H|<CodonTrack.codon_track view={@view} />|)

    assert html =~ "arkea-codon-track"
    # Type-tag positions render with the type_tag role class.
    assert html =~ "arkea-codon-track__cell--type_tag"
    # Parameter positions render with the parameter_codon role class.
    assert html =~ "arkea-codon-track__cell--parameter_codon"
    # The header surfaces the codon + domain counts.
    assert html =~ "46 codons"
    assert html =~ "2 domains"
  end

  test "codon_track/1 surfaces promoter / regulatory blocks when populated" do
    base = Gene.from_domains([Domain.new([0, 0, 1], List.duplicate(10, 20))])
    gene = %{base | promoter_block: [1, 2, 3, 4], regulatory_block: [5, 6, 7]}

    view = CodonViewer.build(gene)
    assigns = %{view: view}

    html = rendered_to_string(~H|<CodonTrack.codon_track view={@view} />|)

    assert html =~ "arkea-codon-track__cell--promoter_codon"
    assert html =~ "arkea-codon-track__cell--regulatory_codon"
    assert html =~ ~r/<span[^>]*class="arkea-codon-track__sub-label"[^>]*>\s*promoter/
    assert html =~ ~r/<span[^>]*class="arkea-codon-track__sub-label"[^>]*>\s*regulatory/
  end

  test "compact mode hides per-cell value text" do
    view = CodonViewer.build(two_domain_gene())
    assigns = %{view: view}

    html = rendered_to_string(~H|<CodonTrack.codon_track view={@view} compact />|)

    assert html =~ "arkea-codon-track--compact"
    refute html =~ "arkea-codon-track__cell-value"
  end

  test "tooltip carries codon index + role + domain context" do
    view = CodonViewer.build(two_domain_gene())
    assigns = %{view: view}

    html = rendered_to_string(~H|<CodonTrack.codon_track view={@view} />|)

    assert html =~ "codon #0"
    assert html =~ "type_tag"
    assert html =~ "domain 0"
  end
end
