defmodule ArkeaWeb.Components.ArkeonSchematic do
  @moduledoc """
  SVG schematic of an Arkeon cell driven by `Arkea.Views.ArkeonSchematic`.

  The component renders a small diagrammatic cell: envelope, transmembrane
  spans, cytoplasm, nucleoid, plasmids, prophage mark, granules, surface
  appendages, optional flagellum and stress halo. Geometry is computed by
  the pure layout module; this component is rendering only.
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
        <%!-- Stress halo (mutator) --%>
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
        />

        <%!-- Flagellum (motile) --%>
        <path
          :if={@layout.flagellum}
          class="arkea-arkeon-schematic__flagellum"
          d={@layout.flagellum.path}
          fill="none"
        />

        <%!-- Cytoplasm + envelope (drawn together for layering) --%>
        <%= case @layout.envelope.kind do %>
          <% :smooth -> %>
            <ellipse
              class="arkea-arkeon-schematic__cytoplasm"
              cx={@layout.envelope.cx}
              cy={@layout.envelope.cy}
              rx={@layout.envelope.rx}
              ry={@layout.envelope.ry}
              fill-opacity={@layout.cytoplasm.fill_opacity}
            />
            <ellipse
              :if={@layout.envelope.double?}
              class="arkea-arkeon-schematic__envelope-inner"
              cx={@layout.envelope.cx}
              cy={@layout.envelope.cy}
              rx={@layout.envelope.rx - @layout.envelope.inner_offset}
              ry={@layout.envelope.ry - @layout.envelope.inner_offset}
              fill="none"
            />
            <ellipse
              class="arkea-arkeon-schematic__envelope"
              cx={@layout.envelope.cx}
              cy={@layout.envelope.cy}
              rx={@layout.envelope.rx}
              ry={@layout.envelope.ry}
              fill="none"
              stroke-width={@layout.envelope.stroke_width}
            />
          <% :scalloped -> %>
            <path
              class="arkea-arkeon-schematic__cytoplasm"
              d={@layout.envelope.path}
              fill-opacity={@layout.cytoplasm.fill_opacity}
            />
            <path
              class="arkea-arkeon-schematic__envelope"
              d={@layout.envelope.path}
              fill="none"
              stroke-width={@layout.envelope.stroke_width}
            />
        <% end %>

        <%!-- Transmembrane spans --%>
        <g class="arkea-arkeon-schematic__tm-spans">
          <line
            :for={span <- @layout.membrane_spans}
            x1={span.x1}
            y1={span.y1}
            x2={span.x2}
            y2={span.y2}
            class="arkea-arkeon-schematic__tm-span"
          />
        </g>

        <%!-- Storage granules --%>
        <g class="arkea-arkeon-schematic__granules">
          <circle
            :for={g <- @layout.granules}
            cx={g.cx}
            cy={g.cy}
            r={g.r}
            class="arkea-arkeon-schematic__granule"
          />
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
          />
        </g>

        <%!-- Nucleoid (looped chromosome) --%>
        <path
          class="arkea-arkeon-schematic__nucleoid"
          d={@layout.nucleoid.path}
          fill="none"
        />

        <%!-- Prophage mark --%>
        <polygon
          :if={@layout.prophage}
          class="arkea-arkeon-schematic__prophage"
          points={prophage_points(@layout.prophage)}
        />

        <%!-- Surface appendages --%>
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
                />
              <% :adhesin -> %>
                <circle
                  cx={app.cx}
                  cy={app.cy}
                  r={app.r}
                  class="arkea-arkeon-schematic__adhesin"
                />
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
                />
            <% end %>
          <% end %>
        </g>
      </svg>
    </div>
    """
  end

  defp prophage_points(p) do
    "#{p.x},#{p.y} #{p.x + p.size},#{p.y - p.size / 2} #{p.x + p.size / 2},#{p.y + p.size / 2}"
  end
end
