defmodule ArkeaWeb.Components.GeneDiffPanel do
  @moduledoc """
  Codon-level gene diff panel (Phase 34 / UI consumer for
  `Arkea.Views.GeneDiff`).

  Renders the per-codon diff between two homologous gene
  variants as two parallel codon strips:

    * **Pinned (top)** — the `compare_lineage`'s gene at the same
      chromosome position.
    * **Selected (bottom)** — the focused lineage's gene.

  Substitutions are highlighted with an outline; type-tag flips
  get a stronger amber outline so they stand out from
  parameter-only drift. Length mismatches (the v1 alignment is
  positional, not edit-distance) surface as `:unaligned_a` /
  `:unaligned_b` tail cells with a striped pattern.

  Below the strips we surface the **per-domain summary** from
  `GeneDiff.domains` — type_a vs type_b, type_changed? flag,
  per-domain substitution counts split between tag and params —
  plus a header row with the totals.

  Pure markup component. The diff is computed upstream
  (`GeneDiff.build/2`) and passed in as the `:diff` attribute.
  """

  use Phoenix.Component

  alias Arkea.Genome.Codon

  attr :diff, :map, required: true
  attr :class, :string, default: nil

  def gene_diff_panel(assigns) do
    ~H"""
    <div class={["arkea-gene-diff", @class]}>
      <div class="arkea-gene-diff__totals">
        <span class="arkea-gene-diff__total-chip">
          {@diff.substitutions} subs
        </span>
        <span class="arkea-gene-diff__total-chip arkea-gene-diff__total-chip--tag">
          {@diff.type_tag_changes} tag
        </span>
        <span class="arkea-gene-diff__total-chip">
          {@diff.parameter_changes} param
        </span>
        <span class="arkea-gene-diff__counts">
          {@diff.codon_count_a} ↔ {@diff.codon_count_b} codons
        </span>
      </div>

      <div class="arkea-gene-diff__row">
        <span class="arkea-gene-diff__row-label">pinned</span>
        <div class="arkea-gene-diff__strip">
          <span
            :for={pos <- @diff.positions}
            class={diff_cell_class(pos, :a)}
            data-index={pos.index}
            data-change={pos.change}
            data-codon-value={pos.codon_a}
          >
            <title>{cell_tooltip(pos, :a)}</title>
            <span :if={not is_nil(pos.codon_a)} class="arkea-gene-diff__cell-value">
              {Codon.to_letter(pos.codon_a)}
            </span>
          </span>
        </div>
      </div>

      <div class="arkea-gene-diff__row">
        <span class="arkea-gene-diff__row-label">selected</span>
        <div class="arkea-gene-diff__strip">
          <span
            :for={pos <- @diff.positions}
            class={diff_cell_class(pos, :b)}
            data-index={pos.index}
            data-change={pos.change}
            data-codon-value={pos.codon_b}
          >
            <title>{cell_tooltip(pos, :b)}</title>
            <span :if={not is_nil(pos.codon_b)} class="arkea-gene-diff__cell-value">
              {Codon.to_letter(pos.codon_b)}
            </span>
          </span>
        </div>
      </div>

      <div :if={@diff.domains != []} class="arkea-gene-diff__domains">
        <table class="arkea-gene-diff__domains-table">
          <thead>
            <tr>
              <th>#</th>
              <th>pinned type</th>
              <th>selected type</th>
              <th>tag Δ</th>
              <th>param Δ</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={dom <- @diff.domains}
              class={domain_row_class(dom)}
            >
              <td>{dom.domain_index}</td>
              <td>{type_label(dom.type_a)}</td>
              <td>{type_label(dom.type_b)}</td>
              <td>{dom.substitutions_in_tag}</td>
              <td>{dom.substitutions_in_params}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp diff_cell_class(%{change: :match, role: role}, _side) do
    [
      "arkea-gene-diff__cell",
      "arkea-gene-diff__cell--match",
      "arkea-gene-diff__cell--role-#{role}"
    ]
  end

  defp diff_cell_class(%{change: :substitution, role: role}, _side) do
    role_class =
      case role do
        :type_tag -> "arkea-gene-diff__cell--sub-tag"
        _ -> "arkea-gene-diff__cell--sub-param"
      end

    ["arkea-gene-diff__cell", "arkea-gene-diff__cell--substitution", role_class]
  end

  defp diff_cell_class(%{change: :unaligned, role: :unaligned_a}, :a) do
    ["arkea-gene-diff__cell", "arkea-gene-diff__cell--unaligned"]
  end

  defp diff_cell_class(%{change: :unaligned, role: :unaligned_b}, :b) do
    ["arkea-gene-diff__cell", "arkea-gene-diff__cell--unaligned"]
  end

  # Tail mismatch positions only render on the side they belong to;
  # the other side gets a transparent placeholder so the columns
  # stay aligned.
  defp diff_cell_class(_pos, _side),
    do: ["arkea-gene-diff__cell", "arkea-gene-diff__cell--placeholder"]

  defp cell_tooltip(%{index: i, change: :match, role: role, codon_a: a, codon_b: b}, _side),
    do: "##{i} match (#{role}): #{Codon.to_letter(a)} = #{Codon.to_letter(b)}"

  defp cell_tooltip(
         %{index: i, change: :substitution, role: role, codon_a: a, codon_b: b},
         _side
       ),
       do:
         "##{i} substitution (#{role}): #{Codon.to_letter(a)} → #{Codon.to_letter(b)} (#{a}→#{b})"

  defp cell_tooltip(%{index: i, change: :unaligned, role: role, codon_a: a, codon_b: b}, _side),
    do: "##{i} unaligned (#{role}): a=#{inspect(a)} b=#{inspect(b)}"

  defp domain_row_class(%{type_changed?: true}),
    do: ["arkea-gene-diff__domain-row", "arkea-gene-diff__domain-row--flipped"]

  defp domain_row_class(_), do: ["arkea-gene-diff__domain-row"]

  defp type_label(nil), do: "—"
  defp type_label(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp type_label(other), do: to_string(other)
end
