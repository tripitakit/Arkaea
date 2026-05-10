defmodule ArkeaWeb.Components.DomainLandscapePanelTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Arkea.Ecology.Lineage
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Views.DomainLandscape
  alias ArkeaWeb.Components.DomainLandscapePanel

  defp catalytic_genome do
    Genome.new([
      Gene.from_domains([
        Domain.new([0, 0, 1], List.duplicate(10, 20)),
        Domain.new([0, 0, 1], List.duplicate(15, 20))
      ])
    ])
  end

  defp founder(genome, abundances \\ %{phase_1: 100}),
    do: Lineage.new_founder(genome, abundances, 0)

  test "panel renders an svg + scatter points when the population has matching domains" do
    landscape = DomainLandscape.build([founder(catalytic_genome())], :catalytic_site)

    assigns = %{landscape: landscape, x_key: :kcat, y_key: :raw_sum}

    html =
      rendered_to_string(~H|<DomainLandscapePanel.domain_landscape_panel
  landscape={@landscape}
  x_key={@x_key}
  y_key={@y_key}
/>|)

    assert html =~ "arkea-landscape__svg"
    assert html =~ "arkea-landscape__point--chromosome"
    # Header surfaces the count + axes labels.
    assert html =~ "2 points"
    assert html =~ "X: kcat"
    assert html =~ "Y: raw_sum"
  end

  test "panel emits no-points placeholder when the chosen domain_type is empty" do
    landscape = DomainLandscape.build([founder(catalytic_genome())], :transmembrane_anchor)

    assigns = %{landscape: landscape, x_key: :hydrophobicity, y_key: :n_passes}

    html =
      rendered_to_string(~H|<DomainLandscapePanel.domain_landscape_panel
  landscape={@landscape}
  x_key={@x_key}
  y_key={@y_key}
/>|)

    assert html =~ "No domain instances"
    refute html =~ "arkea-landscape__point"
  end

  test "panel filters points whose params lack the requested keys" do
    # ligand_sensor exposes :threshold but not :kcat → asking for :kcat on
    # ligand_sensor points yields zero plotted circles even though the
    # landscape has points.
    sensor_genome =
      Genome.new([
        Gene.from_domains([Domain.new([0, 0, 7], List.duplicate(10, 20))])
      ])

    landscape = DomainLandscape.build([founder(sensor_genome)], :ligand_sensor)
    assigns = %{landscape: landscape, x_key: :kcat, y_key: :raw_sum}

    html =
      rendered_to_string(~H|<DomainLandscapePanel.domain_landscape_panel
  landscape={@landscape}
  x_key={@x_key}
  y_key={@y_key}
/>|)

    # Filtered down to nothing → empty placeholder.
    assert html =~ "No domain instances of"
  end

  test "tooltip surfaces lineage id + replicon + abundance" do
    lineage = founder(catalytic_genome(), %{surface: 250})
    landscape = DomainLandscape.build([lineage], :catalytic_site)
    assigns = %{landscape: landscape, x_key: :kcat, y_key: :raw_sum}

    html =
      rendered_to_string(~H|<DomainLandscapePanel.domain_landscape_panel
  landscape={@landscape}
  x_key={@x_key}
  y_key={@y_key}
/>|)

    assert html =~ "lineage #{String.slice(lineage.id, 0, 8)}"
    assert html =~ "abundance 250"
  end
end
