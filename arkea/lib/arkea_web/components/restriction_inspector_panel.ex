defmodule ArkeaWeb.Components.RestrictionInspectorPanel do
  @moduledoc """
  R-M restriction-modification arsenal panel (Phase 35 / priority 4 —
  UI consumer for `Arkea.Views.RestrictionInspector`).

  Renders the lineage's R-M sites at sequence resolution: the
  full codon pattern of every recognition site, its Type-I /
  Type-II / Type-III classification, palindrome flag, the
  per-position methylation coverage, and whether the site is
  self-protected (the cell's own methylase covers the same
  recognition pattern, classical Arber-Dussoix host modification).

  ## Layout

    * **Header strip** with restriction count, methylation count,
      and a Type-I/II/III distribution chip row.
    * **Per-site cards** — one card per site, role-coded
      (restriction = cyan, methylation = purple), with:
        - signature (legacy 4-codon CSV)
        - palindrome shape (`:exact / :complement / :none`) +
          type tag
        - full pattern strip (each codon as a coloured cell;
          methylated positions outlined for methylase sites)
        - self-protection flag for restriction sites

    * Empty profile → terse "no R-M activity encoded" placeholder.

  Pure markup. The view is computed upstream
  (`Arkea.Views.RestrictionInspector.build/1`) and passed in as
  the `:view` attribute.
  """

  use Phoenix.Component

  attr :view, :map, required: true
  attr :class, :string, default: nil

  def restriction_inspector_panel(assigns) do
    ~H"""
    <div class={["arkea-rm-inspector", @class]}>
      <%= if @view.restriction_count == 0 and @view.methylation_count == 0 do %>
        <p class="arkea-muted" style="margin: 0;">
          No restriction-modification activity encoded by this lineage.
        </p>
      <% else %>
        <div class="arkea-rm-inspector__totals">
          <span class="arkea-rm-inspector__total-chip arkea-rm-inspector__total-chip--restriction">
            {@view.restriction_count} restriction
          </span>
          <span class="arkea-rm-inspector__total-chip arkea-rm-inspector__total-chip--methylation">
            {@view.methylation_count} methylase
          </span>
          <span :if={@view.type_distribution.type_i > 0} class="arkea-rm-inspector__type-chip">
            {@view.type_distribution.type_i} Type I
          </span>
          <span :if={@view.type_distribution.type_ii > 0} class="arkea-rm-inspector__type-chip">
            {@view.type_distribution.type_ii} Type II
          </span>
          <span :if={@view.type_distribution.type_iii > 0} class="arkea-rm-inspector__type-chip">
            {@view.type_distribution.type_iii} Type III
          </span>
        </div>

        <div :if={@view.unprotected_signatures != []} class="arkea-rm-inspector__warning">
          ⚠ {length(@view.unprotected_signatures)} restriction site(s) lack matching
          methylation — the cell would self-cleave at those positions if foreign
          DNA carrying the same signature is not recognised first.
        </div>

        <div class="arkea-rm-inspector__sites">
          <div
            :for={site <- @view.sites}
            class={site_card_class(site)}
          >
            <div class="arkea-rm-inspector__site-header">
              <span class={[
                "arkea-rm-inspector__role-tag",
                "arkea-rm-inspector__role-tag--#{site.role}"
              ]}>
                {role_label(site.role)}
              </span>
              <span class="arkea-rm-inspector__type-tag">{type_label(site.type)}</span>
              <span :if={site.palindrome?} class="arkea-rm-inspector__palindrome-tag">
                palindrome
              </span>
              <span
                :if={site.role == :restriction and site.self_protected?}
                class="arkea-rm-inspector__protect-tag arkea-rm-inspector__protect-tag--ok"
              >
                ✓ self-protected
              </span>
              <span
                :if={site.role == :restriction and not site.self_protected?}
                class="arkea-rm-inspector__protect-tag arkea-rm-inspector__protect-tag--warn"
              >
                ⚠ unprotected
              </span>
            </div>

            <div class="arkea-rm-inspector__site-meta">
              <code class="arkea-rm-inspector__signature">{site.signature}</code>
              <span class="arkea-rm-inspector__site-meta-sep">·</span>
              <span>{site.length_in_codons} codons</span>
            </div>

            <div class="arkea-rm-inspector__pattern">
              <span
                :for={{codon, idx} <- Enum.with_index(site.pattern)}
                class={pattern_cell_class(site, idx)}
                style={"--cell-fill: #{Float.round(codon / 19.0, 3)};"}
              >
                <title>{cell_tooltip(site, idx, codon)}</title>
                <span class="arkea-rm-inspector__pattern-value">{codon}</span>
              </span>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp site_card_class(%{role: role}) do
    [
      "arkea-rm-inspector__site-card",
      "arkea-rm-inspector__site-card--#{role}"
    ]
  end

  defp pattern_cell_class(%{role: :methylation} = site, idx) do
    methylated? = methylated_position?(site, idx)

    [
      "arkea-rm-inspector__pattern-cell",
      "arkea-rm-inspector__pattern-cell--methylation",
      methylated? && "arkea-rm-inspector__pattern-cell--methylated"
    ]
  end

  defp pattern_cell_class(%{role: :restriction}, _idx) do
    [
      "arkea-rm-inspector__pattern-cell",
      "arkea-rm-inspector__pattern-cell--restriction"
    ]
  end

  # Look up the methylated_positions field on the underlying
  # `RecognitionSite` data when the inspector view exposes the
  # struct; gracefully degrade when the field is missing (legacy
  # consumers that pre-date Phase 31's per-position tracking).
  defp methylated_position?(%{methylated_positions: %MapSet{} = set}, idx),
    do: MapSet.member?(set, idx)

  defp methylated_position?(_site, _idx), do: false

  defp cell_tooltip(%{role: role, length_in_codons: n} = site, idx, codon) do
    methylation_part =
      cond do
        role != :methylation -> ""
        methylated_position?(site, idx) -> " · methylated"
        true -> " · unmethylated"
      end

    "pos #{idx}/#{n - 1}: codon #{codon}#{methylation_part}"
  end

  defp role_label(:restriction), do: "restriction"
  defp role_label(:methylation), do: "methylase"

  defp type_label(:type_i), do: "Type I"
  defp type_label(:type_ii), do: "Type II"
  defp type_label(:type_iii), do: "Type III"
end
