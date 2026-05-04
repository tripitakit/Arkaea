defmodule ArkeaWeb.Components.ArkeonSchematic do
  @moduledoc """
  SVG schematic of an Arkeon cell driven by `Arkea.Views.ArkeonSchematic`.

  The component renders a small diagrammatic cell: envelope, transmembrane
  spans, cytoplasm, multi-loop nucleoid (with optional integrated prophage
  cassette), plasmids, storage granules, surface appendages, optional
  flagellum and stress halo. Geometry is computed by the pure layout
  module; this component is rendering only.
  """
  use Phoenix.Component

  alias Arkea.Views.ArkeonSchematic, as: Layout

  attr :layout, :map, required: true
  attr :class, :string, default: nil
  attr :rest, :global

  def arkeon_schematic(assigns) do
    ~H"""
    <div class={["arkea-arkeon-schematic", @class]} {@rest}>
      <svg
        class="arkea-arkeon-schematic__svg"
        viewBox={Layout.viewbox()}
        preserveAspectRatio="xMidYMid meet"
        role="img"
        aria-label="Schematic Arkeon cell"
      >
        <%!-- Stress halo (mutator) — drawn first so it sits behind the cell. --%>
        <ellipse
          :if={@layout.stress_halo}
          class="arkea-arkeon-schematic__stress-halo"
          cx={@layout.stress_halo.cx}
          cy={@layout.stress_halo.cy}
          rx={@layout.stress_halo.rx}
          ry={@layout.stress_halo.ry}
          fill="none"
          stroke-dasharray={@layout.stress_halo.stroke_dasharray}
          opacity={@layout.stress_halo.opacity}
        >
          <title>Mutator stress halo (low repair, hypermutation regime)</title>
        </ellipse>

        <%!-- Flagellum (motile) --%>
        <path
          :if={@layout.flagellum}
          class="arkea-arkeon-schematic__flagellum"
          d={@layout.flagellum.path}
          fill="none"
        >
          <title>Flagellum (motile cluster)</title>
        </path>

        <%!-- Cytoplasm fill + envelope, layered per membrane kind. --%>
        <.envelope_group layout={@layout} />

        <%!-- Transmembrane spans --%>
        <g class="arkea-arkeon-schematic__tm-spans">
          <line
            :for={span <- @layout.membrane_spans}
            x1={span.x1}
            y1={span.y1}
            x2={span.x2}
            y2={span.y2}
            class="arkea-arkeon-schematic__tm-span"
          >
            <title>Transmembrane span</title>
          </line>
        </g>

        <%!-- Storage granules (PHB / polyP / glycogen-like inclusions) --%>
        <g class="arkea-arkeon-schematic__granules">
          <%= for g <- @layout.granules do %>
            <circle
              cx={g.cx}
              cy={g.cy}
              r={g.r}
              class="arkea-arkeon-schematic__granule"
            >
              <title>Storage granule (PHB / polyP / glycogen-like inclusion)</title>
            </circle>
            <circle
              cx={g.highlight_cx}
              cy={g.highlight_cy}
              r={g.highlight_r}
              class="arkea-arkeon-schematic__granule-highlight"
            />
          <% end %>
        </g>

        <%!-- Plasmids --%>
        <g class="arkea-arkeon-schematic__plasmids">
          <ellipse
            :for={p <- @layout.plasmids}
            cx={p.cx}
            cy={p.cy}
            rx={p.rx}
            ry={p.ry}
            fill="none"
            class={[
              "arkea-arkeon-schematic__plasmid",
              p[:hinted?] && "arkea-arkeon-schematic__plasmid--hinted"
            ]}
          >
            <title>{plasmid_title(p)}</title>
          </ellipse>
        </g>

        <%!-- Nucleoid: three overlapping loops form the folded chromosome. --%>
        <g class="arkea-arkeon-schematic__nucleoid">
          <path
            :for={loop <- @layout.nucleoid.loops}
            d={loop.path}
            fill="none"
            class="arkea-arkeon-schematic__nucleoid-loop"
          />
          <title>Nucleoid (folded chromosome)</title>
        </g>

        <%!-- Integrated prophage cassette on the nucleoid --%>
        <g :if={@layout.prophage} class="arkea-arkeon-schematic__prophage">
          <path
            d={@layout.prophage.arc_path}
            class="arkea-arkeon-schematic__prophage-arc"
          />
          <text
            x={@layout.prophage.label_x}
            y={@layout.prophage.label_y}
            class="arkea-arkeon-schematic__prophage-label"
            text-anchor="middle"
            dominant-baseline="middle"
          >
            {@layout.prophage.label}
          </text>
          <title>Latent prophage integrated into the chromosome</title>
        </g>

        <%!-- Surface appendages (pili, adhesins, phage receptor) --%>
        <g class="arkea-arkeon-schematic__appendages">
          <%= for app <- @layout.surface_appendages do %>
            <%= case app.kind do %>
              <% :pilus -> %>
                <line
                  x1={app.x1}
                  y1={app.y1}
                  x2={app.x2}
                  y2={app.y2}
                  class="arkea-arkeon-schematic__pilus"
                >
                  <title>Pilus</title>
                </line>
              <% :adhesin -> %>
                <circle
                  cx={app.cx}
                  cy={app.cy}
                  r={app.r}
                  class="arkea-arkeon-schematic__adhesin"
                >
                  <title>Adhesin / biofilm matrix anchor</title>
                </circle>
              <% :phage_receptor -> %>
                <line
                  x1={app.base_x}
                  y1={app.base_y}
                  x2={app.tip_x}
                  y2={app.tip_y}
                  class="arkea-arkeon-schematic__receptor-stem"
                />
                <line
                  x1={app.bar_start_x}
                  y1={app.bar_start_y}
                  x2={app.bar_end_x}
                  y2={app.bar_end_y}
                  class="arkea-arkeon-schematic__receptor-bar"
                >
                  <title>Phage receptor</title>
                </line>
            <% end %>
          <% end %>
        </g>
      </svg>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Envelope group — one component per membrane kind so the structural
  # differences read at a glance.

  attr :layout, :map, required: true

  defp envelope_group(assigns) do
    ~H"""
    <%= case @layout.envelope.kind do %>
      <% :porous -> %>
        <ellipse
          class="arkea-arkeon-schematic__cytoplasm"
          cx={@layout.envelope.cx}
          cy={@layout.envelope.cy}
          rx={@layout.envelope.rx}
          ry={@layout.envelope.ry}
          fill-opacity={@layout.cytoplasm.fill_opacity}
        />
        <ellipse
          class="arkea-arkeon-schematic__envelope arkea-arkeon-schematic__envelope--porous"
          cx={@layout.envelope.cx}
          cy={@layout.envelope.cy}
          rx={@layout.envelope.rx}
          ry={@layout.envelope.ry}
          fill="none"
          stroke-width={@layout.envelope.stroke_width}
        >
          <title>Porous membrane (single thin bilayer with porin channels)</title>
        </ellipse>

        <circle
          :for={porin <- @layout.envelope.porins}
          cx={porin.cx}
          cy={porin.cy}
          r={porin.r}
          class="arkea-arkeon-schematic__porin"
        />
      <% :fortified -> %>
        <ellipse
          class="arkea-arkeon-schematic__cytoplasm"
          cx={@layout.envelope.cx}
          cy={@layout.envelope.cy}
          rx={@layout.envelope.rx}
          ry={@layout.envelope.ry}
          fill-opacity={@layout.cytoplasm.fill_opacity}
        />
        <%!-- Outer envelope --%>
        <ellipse
          class="arkea-arkeon-schematic__envelope arkea-arkeon-schematic__envelope--fortified"
          cx={@layout.envelope.cx}
          cy={@layout.envelope.cy}
          rx={@layout.envelope.rx}
          ry={@layout.envelope.ry}
          fill="none"
          stroke-width={@layout.envelope.stroke_width}
        >
          <title>Fortified envelope (outer membrane + periplasm + inner plasma membrane)</title>
        </ellipse>
        <%!-- Periplasmic ticks --%>
        <g class="arkea-arkeon-schematic__periplasm">
          <line
            :for={tick <- @layout.envelope.periplasm_ticks}
            x1={tick.x1}
            y1={tick.y1}
            x2={tick.x2}
            y2={tick.y2}
            class="arkea-arkeon-schematic__periplasm-tick"
          />
        </g>
        <%!-- Inner plasma membrane --%>
        <ellipse
          class="arkea-arkeon-schematic__envelope-inner"
          cx={@layout.envelope.cx}
          cy={@layout.envelope.cy}
          rx={@layout.envelope.rx - @layout.envelope.inner_offset}
          ry={@layout.envelope.ry - @layout.envelope.inner_offset}
          fill="none"
          stroke-width={@layout.envelope.inner_stroke_width}
        />
      <% :salinity_tuned -> %>
        <path
          class="arkea-arkeon-schematic__cytoplasm"
          d={@layout.envelope.path}
          fill-opacity={@layout.cytoplasm.fill_opacity}
        />
        <path
          class="arkea-arkeon-schematic__envelope arkea-arkeon-schematic__envelope--salinity"
          d={@layout.envelope.path}
          fill="none"
          stroke-width={@layout.envelope.stroke_width}
        >
          <title>Salinity-tuned envelope (deep scallops + ion-handling inner layer)</title>
        </path>
        <%!-- Inner ion-handling layer --%>
        <ellipse
          class="arkea-arkeon-schematic__envelope-inner arkea-arkeon-schematic__envelope-inner--salinity"
          cx={@layout.envelope.cx}
          cy={@layout.envelope.cy}
          rx={@layout.envelope.rx - @layout.envelope.inner_offset}
          ry={@layout.envelope.ry - @layout.envelope.inner_offset}
          fill="none"
          stroke-width={@layout.envelope.inner_stroke_width}
          stroke-dasharray={if @layout.envelope.inner_dashed?, do: "3 2", else: nil}
        />
    <% end %>
    """
  end

  defp plasmid_title(%{hinted?: true}),
    do: "Conjugative plasmid (will be provisioned with the seed)"

  defp plasmid_title(_), do: "Plasmid (extra-chromosomal DNA ring)"
end
