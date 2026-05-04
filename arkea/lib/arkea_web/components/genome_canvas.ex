defmodule ArkeaWeb.Components.GenomeCanvas do
  @moduledoc """
  Circular chromosome SVG component (UI rewrite — phase U5).

  Reads an `Arkea.Views.GenomeCanvas.layout()` and renders the chromosome
  as a closed ring of gene-segments. Each gene occupies a contiguous arc
  of the ring; its domains are rendered as differently-colored angular
  sub-segments inside the gene's arc — radially full-thickness, side-by-
  side, no concentric crown. Click on a gene emits
  `phx-click="select_gene"` with the gene id; the inspector panel
  consumes that selection.
  """

  use Phoenix.Component

  alias Arkea.Views.GenomeCanvas, as: Layout

  attr :layout, :map, required: true
  attr :selected_gene_id, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global

  def genome_canvas(assigns) do
    ~H"""
    <div class={["arkea-genome-canvas", @class]} {@rest}>
      <svg
        class="arkea-genome-canvas__svg"
        viewBox={Layout.viewbox()}
        preserveAspectRatio="xMidYMid meet"
        role="img"
        aria-label="Circular chromosome"
      >
        <.replicon_group
          replicon={@layout.chromosome}
          selected_gene_id={@selected_gene_id}
          name="chromosome"
        />

        <.replicon_group
          :for={{plasmid, idx} <- Enum.with_index(@layout.plasmids)}
          replicon={plasmid}
          selected_gene_id={@selected_gene_id}
          name={"plasmid-#{idx}"}
        />
      </svg>
    </div>
    """
  end

  attr :replicon, :map, required: true
  attr :selected_gene_id, :string, default: nil
  attr :name, :string, required: true

  defp replicon_group(assigns) do
    ~H"""
    <g class="arkea-genome-canvas__replicon" data-name={@name}>
      <text
        :if={@replicon[:label]}
        class="arkea-genome-canvas__replicon-label"
        x={@replicon.cx}
        y={@replicon.cy}
        text-anchor="middle"
        dominant-baseline="middle"
      >
        {@replicon.label}
      </text>

      <g
        :for={gene <- @replicon.genes}
        class={[
          "arkea-genome-canvas__gene",
          @selected_gene_id == gene.id && "arkea-genome-canvas__gene--selected",
          gene.arc.editable? && "arkea-genome-canvas__gene--editable"
        ]}
        data-gene-id={gene.id}
        data-gene-index={gene.index}
        phx-click="select_gene"
        phx-value-id={gene.id}
        role="button"
        tabindex="0"
        aria-label={"Gene #{gene.label}"}
      >
        <%= if gene.domains == [] do %>
          <%!-- Gene with no parsed domains: fall back to a single solid wedge
                in the gene's own color so the ring stays closed. --%>
          <path
            class="arkea-genome-canvas__gene-fallback"
            d={gene.arc.path_d}
            fill={gene.arc.color}
          >
            <title>{gene.label}</title>
          </path>
        <% else %>
          <%!-- The gene's visual content IS its domain sub-arcs. Each domain
                fills the ring's full radial thickness over its angular slice. --%>
          <path
            :for={dom <- gene.domains}
            class="arkea-genome-canvas__domain"
            d={dom.path_d}
            fill={dom.color}
            data-domain-index={dom.index}
            data-domain-type={dom.type}
          >
            <title>{dom.tooltip}</title>
          </path>
        <% end %>

        <%!-- Transparent outline drawn on top of the gene segment; CSS
              uses it to render the selection halo without recomputing
              geometry per domain. --%>
        <path
          class="arkea-genome-canvas__gene-outline"
          d={gene.arc.path_d}
          fill="none"
        />

        <text
          class="arkea-genome-canvas__gene-label"
          x={gene.arc.label_x}
          y={gene.arc.label_y}
          text-anchor={gene.arc.label_anchor}
          dominant-baseline="middle"
        >
          {gene.label}
        </text>
      </g>
    </g>
    """
  end
end
