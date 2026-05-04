defmodule ArkeaWeb.Components.GenomeCanvas do
  @moduledoc """
  Circular chromosome SVG component (UI rewrite — phase U5).

  Reads an `Arkea.Views.GenomeCanvas.layout()` and renders the chromosome
  with a domain crown, plus plasmids. Click on a gene arc emits
  `phx-click="select_gene"` with the gene id. Domain reorder controls live
  in a sibling editor panel — this component is purely the visual canvas.
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
      <circle
        class="arkea-genome-canvas__replicon-ring"
        cx={@replicon.cx}
        cy={@replicon.cy}
        r={(@replicon.r_outer + @replicon.r_inner) / 2}
      />

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
      >
        <path
          class="arkea-genome-canvas__gene-arc"
          d={gene.arc.path_d}
          fill={gene.arc.color}
          phx-click="select_gene"
          phx-value-id={gene.id}
          tabindex="0"
          role="button"
          aria-label={"Gene #{gene.label}"}
        >
          <title>{gene.label}</title>
        </path>

        <text
          class="arkea-genome-canvas__gene-label"
          x={gene.arc.label_x}
          y={gene.arc.label_y}
          text-anchor={gene.arc.label_anchor}
          dominant-baseline="middle"
        >
          {gene.label}
        </text>

        <g class="arkea-genome-canvas__domains">
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
        </g>
      </g>
    </g>
    """
  end
end
