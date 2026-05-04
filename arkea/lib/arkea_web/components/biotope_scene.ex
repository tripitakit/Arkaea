defmodule ArkeaWeb.Components.BiotopeScene do
  @moduledoc """
  SVG render of the biotope scene (UI rewrite — phase U3, replaces the
  former PixiJS canvas hook).

  The component is data-driven by an `Arkea.Views.BiotopeScene.build/1`
  layout struct. Click on a phase band emits `phx-click="select_phase"`
  with the band name; the LiveView uses the same handler the old Pixi
  pointer listener used.
  """
  use Phoenix.Component

  alias Arkea.Views.BiotopeScene, as: Layout

  attr :layout, :map, required: true
  attr :class, :string, default: nil
  attr :rest, :global

  def biotope_scene(assigns) do
    ~H"""
    <div class={["arkea-scene", @class]} {@rest}>
      <%= if @layout.empty? do %>
        <div class="arkea-scene__empty">
          <p>No phases to render.</p>
        </div>
      <% else %>
        <svg
          class="arkea-scene__svg"
          viewBox={Layout.viewbox()}
          preserveAspectRatio="xMidYMid meet"
          role="img"
          aria-label="Biotope scene"
        >
          <defs>
            <pattern id="arkea-scene-grid" width="36" height="28" patternUnits="userSpaceOnUse">
              <path
                d="M 36 0 L 0 0 0 28"
                fill="none"
                stroke="#102034"
                stroke-width="0.4"
                opacity="0.32"
              />
            </pattern>
          </defs>

          <rect
            class="arkea-scene__backdrop"
            x="0"
            y="0"
            width={@layout.width}
            height={@layout.height}
            rx="20"
            ry="20"
          />
          <rect
            class="arkea-scene__grid"
            x="0"
            y="0"
            width={@layout.width}
            height={@layout.height}
            rx="20"
            ry="20"
            fill="url(#arkea-scene-grid)"
          />

          <g class="arkea-scene__bands">
            <g
              :for={band <- @layout.bands}
              class={[
                "arkea-scene__band",
                band.selected? && "arkea-scene__band--selected"
              ]}
              phx-click="select_phase"
              phx-value-phase={band.name}
              role="button"
              tabindex="0"
              aria-label={"Select phase #{band.label}"}
            >
              <rect
                class="arkea-scene__band-rect"
                x={band.x}
                y={band.y}
                width={band.w}
                height={band.h}
                rx="18"
                ry="18"
                style={"--arkea-band-color: #{band.color};"}
              />
              <rect
                :if={band.selected?}
                class="arkea-scene__band-highlight"
                x={band.x + 2}
                y={band.y}
                width={band.w - 4}
                height="2"
                rx="1"
                ry="1"
                style={"--arkea-band-color: #{band.color};"}
              />
              <text class="arkea-scene__band-title" x={band.x + 14} y={band.y + 18}>
                {String.upcase(band.label)} · N {format_compact(band.total_abundance)}
              </text>
              <text class="arkea-scene__band-detail" x={band.x + 14} y={band.y + 32}>
                {format_band_detail(band)}
              </text>
            </g>
          </g>

          <g class="arkea-scene__particles">
            <g
              :for={p <- @layout.particles}
              class={"arkea-scene__particle arkea-scene__particle--#{p.cluster}"}
              transform={"translate(#{p.cx} #{p.cy})"}
            >
              <%= case p.cluster do %>
                <% "biofilm" -> %>
                  <rect
                    x={-p.r * 0.8}
                    y={-p.r * 0.8}
                    width={p.r * 1.6}
                    height={p.r * 1.6}
                    rx="0.4"
                    fill={p.color}
                  />
                <% "motile" -> %>
                  <ellipse cx="0" cy="0" rx={p.r * 1.5} ry={p.r * 0.6} fill={p.color} />
                <% _ -> %>
                  <circle cx="0" cy="0" r={p.r} fill={p.color} />
              <% end %>
            </g>
          </g>

          <g class="arkea-scene__overlay">
            <text
              class="arkea-scene__tick"
              x={@layout.width - 18}
              y="20"
              text-anchor="end"
            >
              tick {@layout.tick}
            </text>
          </g>
        </svg>
      <% end %>
    </div>
    """
  end

  defp format_compact(v) when is_integer(v) do
    cond do
      v >= 1_000_000 -> "#{Float.round(v / 1_000_000, 1)}M"
      v >= 1_000 -> "#{Float.round(v / 1_000, 1)}k"
      true -> Integer.to_string(v)
    end
  end

  defp format_compact(v), do: to_string(v)

  defp format_band_detail(band) do
    parts = [
      band.temperature && "T #{band.temperature}°C",
      band.ph && "pH #{band.ph}",
      band.dilution_rate && "D #{round(band.dilution_rate * 100)}%/tick"
    ]

    parts |> Enum.reject(&is_nil/1) |> Enum.join(" · ")
  end
end
