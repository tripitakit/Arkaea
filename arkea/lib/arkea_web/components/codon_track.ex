defmodule ArkeaWeb.Components.CodonTrack do
  @moduledoc """
  Linear codon-track inspector (Phase 34 / UI consumer for
  `Arkea.Views.CodonViewer`).

  Renders the per-codon role annotations of a single gene as a
  contiguous strip of cells. Each cell represents one codon and
  is colour-coded by `role`:

    * `:type_tag` — gold tone; the 3 codons that pick the
      domain category. A point mutation here flips the
      `Domain.type` (`:domain_flip` audit event).
    * `:parameter_codon` — domain-tone (the same colour family
      `GenomeCanvas.domain_color/1` uses for the SVG ring) so
      the strip reads as belonging to the parent domain.
    * `:promoter_codon` / `:regulatory_codon` — purple/teal
      tones; only present when the consuming gene exposes those
      blocks.

  The component is pure markup — it accepts the
  `Arkea.Views.CodonViewer.t()` shape and emits HTML. No
  server-side state or events. Hovering any cell shows a
  `<title>` tooltip with the codon's `index`,
  `domain_index`/`domain_type`, and the underlying integer codon
  value.

  ## Usage

      <.codon_track view={@codon_view} />
      <.codon_track view={@codon_view} compact />
  """

  use Phoenix.Component

  alias Arkea.Views.GenomeCanvas, as: CanvasLayout

  attr :view, :map, required: true
  attr :compact, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global

  def codon_track(assigns) do
    ~H"""
    <div class={["arkea-codon-track", @compact && "arkea-codon-track--compact", @class]} {@rest}>
      <div class="arkea-codon-track__header">
        <span class="arkea-codon-track__gene-id">{short_id(@view.gene_id)}</span>
        <span class="arkea-codon-track__counts">
          {@view.codon_count} codons · {@view.domain_count} domains
        </span>
      </div>

      <div class="arkea-codon-track__strip" role="img" aria-label="Codon role annotations">
        <span
          :for={entry <- @view.codons}
          class={[
            "arkea-codon-track__cell",
            "arkea-codon-track__cell--#{entry.role}"
          ]}
          style={cell_style(entry)}
          data-index={entry.index}
          data-role={entry.role}
          data-domain-index={entry.domain_index}
        >
          <title>{cell_tooltip(entry)}</title>
          <span :if={!@compact} class="arkea-codon-track__cell-value">{entry.codon}</span>
        </span>
      </div>

      <%= if @view.promoter_codons != [] do %>
        <div class="arkea-codon-track__sub-strip">
          <span class="arkea-codon-track__sub-label">promoter</span>
          <div class="arkea-codon-track__strip arkea-codon-track__strip--secondary">
            <span
              :for={entry <- @view.promoter_codons}
              class="arkea-codon-track__cell arkea-codon-track__cell--promoter_codon"
              data-index={entry.index}
            >
              <title>promoter codon {entry.index}: value {entry.codon}</title>
              <span :if={!@compact} class="arkea-codon-track__cell-value">{entry.codon}</span>
            </span>
          </div>
        </div>
      <% end %>

      <%= if @view.regulatory_codons != [] do %>
        <div class="arkea-codon-track__sub-strip">
          <span class="arkea-codon-track__sub-label">regulatory</span>
          <div class="arkea-codon-track__strip arkea-codon-track__strip--secondary">
            <span
              :for={entry <- @view.regulatory_codons}
              class="arkea-codon-track__cell arkea-codon-track__cell--regulatory_codon"
              data-index={entry.index}
            >
              <title>regulatory codon {entry.index}: value {entry.codon}</title>
              <span :if={!@compact} class="arkea-codon-track__cell-value">{entry.codon}</span>
            </span>
          </div>
        </div>
      <% end %>

      <div class="arkea-codon-track__legend">
        <span class="arkea-codon-track__legend-item">
          <span class="arkea-codon-track__legend-swatch arkea-codon-track__cell--type_tag" />type tag
        </span>
        <span class="arkea-codon-track__legend-item">
          <span class="arkea-codon-track__legend-swatch arkea-codon-track__cell--parameter_codon" />parameter
        </span>
        <span :if={@view.promoter_codons != []} class="arkea-codon-track__legend-item">
          <span class="arkea-codon-track__legend-swatch arkea-codon-track__cell--promoter_codon" />promoter
        </span>
        <span :if={@view.regulatory_codons != []} class="arkea-codon-track__legend-item">
          <span class="arkea-codon-track__legend-swatch arkea-codon-track__cell--regulatory_codon" />regulatory
        </span>
      </div>
    </div>
    """
  end

  # Per-cell inline styling. For `:parameter_codon` cells we
  # inherit the parent domain's canvas colour so the strip reads
  # as belonging to the same domain as the SVG arc above. The
  # `--fill` CSS variable encodes the codon value normalised to
  # `0..1`, letting CSS modulate brightness inside each domain.
  defp cell_style(%{role: :parameter_codon, domain_type: type, codon: c})
       when not is_nil(type) and is_integer(c) do
    fill = c / 19.0
    "background: #{CanvasLayout.domain_color(type)}; --fill: #{Float.round(fill, 3)};"
  end

  defp cell_style(%{role: :type_tag, codon: c}) when is_integer(c) do
    "--fill: #{Float.round(c / 19.0, 3)};"
  end

  defp cell_style(_), do: nil

  defp cell_tooltip(%{
         index: i,
         codon: c,
         role: role,
         domain_index: dom_idx,
         domain_type: dom_type,
         codon_in_domain: in_dom
       }) do
    domain_part =
      cond do
        is_nil(dom_type) -> ""
        is_nil(in_dom) -> " · domain #{dom_idx} (#{dom_type})"
        true -> " · domain #{dom_idx} (#{dom_type}) pos #{in_dom}"
      end

    "codon ##{i}: value #{c} · #{role}#{domain_part}"
  end

  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)
  defp short_id(_), do: "—"
end
