defmodule ArkeaWeb.Components.MutationHotspotTrack do
  @moduledoc """
  Per-codon mutation hotspot track (Phase 35 / priority 3 — UI
  consumer for `Arkea.Views.MutationHotspot`).

  Renders one heatmap cell per codon, intensity proportional to
  the number of mutational events that touched that position.
  Sits naturally below `ArkeaWeb.Components.CodonTrack` in the
  drawer so the player reads codon role + mutation pressure on
  the same horizontal axis.

  ## Visual encoding

    * Cell intensity (`opacity` + `outline-color`) scales with
      `count` relative to the maximum bin count across the
      gene. A gene with no events renders as a flat low-opacity
      strip (visible but unmarked).
    * Hovering a cell shows a `<title>` tooltip with the
      absolute count + the contributing event types
      (`:domain_flip` / `:gene_chimera_birth`).
    * Header row surfaces the gene id + total events for a
      quick "is anything happening here?" glance.

  Pure markup. The hotspot model is computed upstream
  (`Arkea.Views.MutationHotspot.build/2`) and passed in as the
  `:model` attribute.
  """

  use Phoenix.Component

  attr :model, :map, required: true
  attr :class, :string, default: nil

  def mutation_hotspot_track(assigns) do
    max_count = max_count_for(assigns.model)
    assigns = assign(assigns, max_count: max_count)

    ~H"""
    <div class={["arkea-hotspot-track", @class]}>
      <div class="arkea-hotspot-track__header">
        <span class="arkea-hotspot-track__label">mutation hotspots</span>
        <span class="arkea-hotspot-track__counts">
          {@model.total_events} events · {@model.codon_count} codons
        </span>
      </div>

      <div class="arkea-hotspot-track__strip" role="img" aria-label="Mutation hotspot heatmap">
        <span
          :for={bin <- @model.bins}
          class={[
            "arkea-hotspot-track__cell",
            bin.count == 0 && "arkea-hotspot-track__cell--cold",
            bin.count > 0 && "arkea-hotspot-track__cell--hot"
          ]}
          style={cell_style(bin, @max_count)}
          data-codon-index={bin.codon_index}
          data-count={bin.count}
        >
          <title>{cell_tooltip(bin)}</title>
        </span>
      </div>
    </div>
    """
  end

  defp max_count_for(%{bins: bins}) do
    bins
    |> Enum.map(& &1.count)
    |> Enum.max(fn -> 0 end)
  end

  defp cell_style(%{count: 0}, _max), do: nil

  defp cell_style(%{count: count}, max_count) when max_count > 0 do
    intensity = Float.round(count / max_count, 3)
    "--hot-intensity: #{intensity};"
  end

  defp cell_style(_, _), do: nil

  defp cell_tooltip(%{codon_index: idx, count: 0}),
    do: "codon ##{idx}: no recorded events"

  defp cell_tooltip(%{codon_index: idx, count: count, contributors: contribs}) do
    types =
      contribs
      |> Enum.uniq()
      |> Enum.join(", ")

    "codon ##{idx}: #{count} events · #{types}"
  end
end
