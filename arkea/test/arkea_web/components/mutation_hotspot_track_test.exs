defmodule ArkeaWeb.Components.MutationHotspotTrackTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Persistence.AuditLog
  alias Arkea.Views.MutationHotspot
  alias ArkeaWeb.Components.MutationHotspotTrack

  defp two_domain_gene do
    Gene.from_domains([
      Domain.new([0, 0, 1], List.duplicate(10, 20)),
      Domain.new([0, 0, 5], List.duplicate(15, 20))
    ])
  end

  test "mutation_hotspot_track/1 with empty audit produces a flat cold strip" do
    model = MutationHotspot.build(two_domain_gene(), [])
    assigns = %{model: model}

    html = rendered_to_string(~H|<MutationHotspotTrack.mutation_hotspot_track model={@model} />|)

    assert html =~ "arkea-hotspot-track"
    assert html =~ "0 events"
    assert html =~ "46 codons"
    # All 46 cells are cold.
    cold_count =
      html
      |> String.split("arkea-hotspot-track__cell--cold")
      |> length()
      |> Kernel.-(1)

    assert cold_count == 46
    refute html =~ "arkea-hotspot-track__cell--hot"
  end

  test "mutation_hotspot_track/1 with one domain_flip event highlights affected codons" do
    gene = two_domain_gene()

    audit = [
      %AuditLog{
        event_type: "domain_flip",
        occurred_at_tick: 5,
        target_lineage_id: "L-1",
        payload: %{"gene_id" => gene.id, "domain_index" => 0}
      }
    ]

    model = MutationHotspot.build(gene, audit)
    assigns = %{model: model}

    html = rendered_to_string(~H|<MutationHotspotTrack.mutation_hotspot_track model={@model} />|)

    assert html =~ "23 events"
    assert html =~ "arkea-hotspot-track__cell--hot"
    # Tooltip surfaces the contributor type for at least one hot cell.
    assert html =~ "domain_flip"
  end

  test "tooltip on cold cell surfaces 'no recorded events'" do
    model = MutationHotspot.build(two_domain_gene(), [])
    assigns = %{model: model}

    html = rendered_to_string(~H|<MutationHotspotTrack.mutation_hotspot_track model={@model} />|)
    assert html =~ "no recorded events"
  end
end
