defmodule ArkeaWeb.Components.AncestralTracePanel do
  @moduledoc """
  Ancestor genome + sequence trace panel (Phase 36 / priority 6 — UI
  consumer for `Arkea.Views.AncestralReconstruction`).

  Surfaces the ancestor chain (target → root) of a focused
  lineage as two stacked tables:

    * **Genome trace** (3.6) — one row per ancestor with
      `lineage_id`, `tick`, `generation`, gene/plasmid/prophage
      counts, and a `delta_only?` flag for delta-encoded
      ancestors that don't carry a materialised genome.
    * **Gene trace** (3.7, optional) — when a chromosome
      position is supplied, renders the codon sequence at that
      position across the same chain. Each row shows the
      ancestor's tick, the gene's domain type at that
      position, and the codon stream (compact strip).

  ## Limits documented in-place

  Both traces are *positional*: gene tracking uses
  `chromosome[index]` at every node; a transposition / gene
  loss upstream surfaces as a `:lost` marker rather than an
  inferred reconstruction. This is the same v1 caveat
  documented in the upstream view module.

  Pure markup. The trace structures are computed upstream
  (`AncestralReconstruction.genome_trace/2` +
  `AncestralReconstruction.gene_trace/3`) and passed in as the
  `:genome_trace` + (optional) `:gene_trace` attrs.
  """

  use Phoenix.Component

  attr :genome_trace, :map, required: true
  attr :gene_trace, :map, default: nil
  attr :class, :string, default: nil

  def ancestral_trace_panel(assigns) do
    ~H"""
    <div class={["arkea-ancestral", @class]}>
      <div class="arkea-ancestral__header">
        <span class="arkea-ancestral__chip">
          {@genome_trace.depth} ancestor{if @genome_trace.depth != 1, do: "s"}
        </span>
        <span class="arkea-ancestral__chip arkea-ancestral__chip--muted">
          target → root order
        </span>
      </div>

      <table class="arkea-ancestral__table">
        <thead>
          <tr>
            <th>gen</th>
            <th>tick</th>
            <th>lineage</th>
            <th>genes</th>
            <th>plasmids</th>
            <th>prophages</th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={entry <- @genome_trace.ancestors}
            class={genome_row_class(entry)}
          >
            <td>{entry.generation}</td>
            <td>{entry.tick}</td>
            <td>
              <code class="arkea-ancestral__inline-id">{short_id(entry.lineage_id)}</code>
            </td>
            <td>
              <%= cond do %>
                <% is_nil(entry.gene_count) -> %>
                  <span class="arkea-ancestral__delta">delta-only</span>
                <% true -> %>
                  {entry.gene_count}
              <% end %>
            </td>
            <td>{entry.plasmid_count}</td>
            <td>{entry.prophage_count}</td>
          </tr>
        </tbody>
      </table>

      <div :if={@gene_trace} class="arkea-ancestral__gene-trace">
        <div class="arkea-ancestral__section-title">
          Gene trace at chromosome[<code>{@gene_trace.gene_chromosome_index}</code>]
        </div>

        <div class="arkea-ancestral__gene-rows">
          <div
            :for={entry <- @gene_trace.trace}
            class={gene_row_class(entry)}
          >
            <div class="arkea-ancestral__gene-row-meta">
              <span class="arkea-ancestral__gene-row-gen">gen {entry.generation}</span>
              <span class="arkea-ancestral__gene-row-tick">tick {entry.tick}</span>
              <span :if={entry.type} class="arkea-ancestral__gene-row-type">
                {entry.type}
              </span>
              <span :if={entry.status != :present} class="arkea-ancestral__gene-row-status">
                {status_label(entry.status)}
              </span>
            </div>
            <div :if={entry.codons} class="arkea-ancestral__gene-row-strip">
              <span
                :for={{codon, idx} <- Enum.with_index(entry.codons)}
                class="arkea-ancestral__codon-cell"
                style={"--cell-fill: #{Float.round(codon / 19.0, 3)};"}
              >
                <title>pos #{idx}: codon {codon}</title>
              </span>
            </div>
          </div>
        </div>
      </div>

      <p class="arkea-ancestral__note">
        v1: positional trace — a transposition or gene-loss upstream
        surfaces as a <code>:lost</code> marker rather than an inferred
        reconstruction. Felsenstein-style ancestral-state inference is
        deferred to a Phase-30+ phylogenomics tranche.
      </p>
    </div>
    """
  end

  defp genome_row_class(%{generation: 0}),
    do: ["arkea-ancestral__row", "arkea-ancestral__row--target"]

  defp genome_row_class(%{genome_present?: false}),
    do: ["arkea-ancestral__row", "arkea-ancestral__row--delta-only"]

  defp genome_row_class(_), do: ["arkea-ancestral__row"]

  defp gene_row_class(%{status: :present}),
    do: ["arkea-ancestral__gene-row", "arkea-ancestral__gene-row--present"]

  defp gene_row_class(%{status: status}),
    do: ["arkea-ancestral__gene-row", "arkea-ancestral__gene-row--#{status}"]

  defp status_label(:present), do: "present"
  defp status_label(:lost), do: "lost"
  defp status_label(:delta_only), do: "delta-only"

  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)
  defp short_id(_), do: "—"
end
