defmodule ArkeaWeb.Components.GeneTreePanel do
  @moduledoc """
  Gene-tree clusters + species/gene-tree topology overlay
  (Phase 36 / priority 7 — UI consumer for `Arkea.Views.GeneTree`).

  Renders the lineages of the population grouped by gene
  similarity, surfacing the **HGT incongruence** signal: a
  cluster whose members do *not* form a monophyletic clade in
  the species (lineage) tree carries a `:type_incongruent`
  badge — i.e. distantly-related lineages share the same gene
  variant, the classical horizontal-gene-transfer fingerprint
  (Doolittle 1999).

  ## Output

    * Header chip row with cluster count, max p-distance
      threshold, and a count of `:incongruent` clusters.
    * Per-cluster card with:
        - cluster id + topology badge
        - representative gene id + member count
        - MRCA lineage id (when not a singleton)
        - subtree descendant count vs cluster size — the
          "intruder count" (descendants of the MRCA NOT in
          the cluster) is the visible HGT signal
        - chip row of member lineage ids with their
          p-distance to the representative

  Pure markup. The view is computed upstream
  (`Arkea.Views.GeneTree.build/2`) and passed in as the
  `:view` attribute.
  """

  use Phoenix.Component

  attr :view, :map, required: true
  attr :class, :string, default: nil

  def gene_tree_panel(assigns) do
    incongruent_count = Enum.count(assigns.view.clusters, &(&1.topology == :incongruent))
    assigns = assign(assigns, incongruent_count: incongruent_count)

    ~H"""
    <div class={["arkea-gene-tree", @class]}>
      <%= if @view.cluster_count == 0 do %>
        <p class="arkea-muted" style="margin: 0;">
          No lineages produced a gene at the chosen extractor — the
          gene tree has no clusters to display.
        </p>
      <% else %>
        <div class="arkea-gene-tree__totals">
          <span class="arkea-gene-tree__chip">
            {@view.cluster_count} cluster{if @view.cluster_count != 1, do: "s"}
          </span>
          <span class="arkea-gene-tree__chip">
            max p-distance {format_distance(@view.max_distance)}
          </span>
          <span
            :if={@incongruent_count > 0}
            class="arkea-gene-tree__chip arkea-gene-tree__chip--warn"
          >
            ⚠ {@incongruent_count} HGT-incongruent
          </span>
        </div>

        <div class="arkea-gene-tree__clusters">
          <article
            :for={cluster <- @view.clusters}
            class={cluster_card_class(cluster)}
          >
            <header class="arkea-gene-tree__cluster-header">
              <span class="arkea-gene-tree__cluster-id">cluster #{cluster.cluster_id}</span>
              <span class={topology_chip_class(cluster.topology)}>
                {topology_label(cluster.topology)}
              </span>
              <span class="arkea-gene-tree__member-count">
                {length(cluster.members)} member{if length(cluster.members) != 1, do: "s"}
              </span>
            </header>

            <div class="arkea-gene-tree__cluster-meta">
              representative gene
              <code class="arkea-gene-tree__inline-id">
                {short_id(cluster.representative_gene_id)}
              </code>
              <span :if={cluster.mrca_lineage_id}>
                · MRCA
                <code class="arkea-gene-tree__inline-id">
                  {short_id(cluster.mrca_lineage_id)}
                </code>
                ({cluster.mrca_descendants_count} subtree)
              </span>
            </div>

            <div :if={cluster.topology == :incongruent} class="arkea-gene-tree__incongruence">
              {intruder_count(cluster)} subtree descendant(s) NOT carrying this variant —
              cluster spans non-monophyletic clades, suggesting horizontal transfer
              (Doolittle 1999).
            </div>

            <div class="arkea-gene-tree__members">
              <span
                :for={member <- cluster.members}
                class="arkea-gene-tree__member-chip"
                title={member_tooltip(member)}
              >
                {short_id(member.lineage_id)}
                <span class="arkea-gene-tree__member-distance">
                  {format_distance(member.p_distance)}
                </span>
              </span>
            </div>
          </article>
        </div>

        <div :if={@view.unmatched_lineages != []} class="arkea-gene-tree__unmatched">
          <span class="arkea-gene-tree__chip arkea-gene-tree__chip--muted">
            {length(@view.unmatched_lineages)} unmatched lineage{if length(@view.unmatched_lineages) !=
                                                                      1,
                                                                    do: "s"}
          </span>
          <span class="arkea-gene-tree__unmatched-note">
            (gene extractor returned <code>nil</code> — typically delta-encoded descendants)
          </span>
        </div>
      <% end %>
    </div>
    """
  end

  defp cluster_card_class(%{topology: topology}) do
    [
      "arkea-gene-tree__cluster-card",
      "arkea-gene-tree__cluster-card--#{topology}"
    ]
  end

  defp topology_chip_class(topology) do
    [
      "arkea-gene-tree__topology-chip",
      "arkea-gene-tree__topology-chip--#{topology}"
    ]
  end

  defp topology_label(:singleton), do: "singleton"
  defp topology_label(:congruent), do: "congruent"
  defp topology_label(:incongruent), do: "incongruent"

  defp intruder_count(%{mrca_descendants_count: descendants, members: members}),
    do: max(descendants - length(members), 0)

  defp member_tooltip(%{lineage_id: lid, parent_id: pid, p_distance: d, gene_id: gid}) do
    pid_part = if pid, do: " · parent #{short_id(pid)}", else: " · founder"

    "lineage #{short_id(lid)}#{pid_part}\ngene #{short_id(gid)} · p-dist #{format_distance(d)}"
  end

  defp short_id(nil), do: "—"
  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)

  defp format_distance(nil), do: "—"
  defp format_distance(+0.0), do: "0.000"
  defp format_distance(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 3)
  defp format_distance(v) when is_integer(v), do: Integer.to_string(v)
end
