defmodule Arkea.Views.BiotopeScene do
  @moduledoc """
  Pure layout for the biotope scene SVG (UI rewrite — phase U3, replaces
  the PixiJS canvas hook).

  The function `build/1` takes a snapshot map (atom-keyed) and returns a
  layout struct with pre-computed coordinates the HEEx component can render
  directly. No I/O, no GenServer, no rendering — just geometry.

  ## Snapshot shape

      %{
        biotope_id: binary(),
        tick: non_neg_integer(),
        archetype: String.t(),
        selected_phase: String.t() | nil,
        phases: [
          %{
            name: String.t(),                 # atom-as-string (e.g. "surface")
            label: String.t(),
            color: String.t(),                # hex
            temperature: float() | nil,
            ph: float() | nil,
            dilution_rate: float() | nil,
            total_abundance: non_neg_integer(),
            lineage_count: non_neg_integer()
          }
        ],
        lineages: [
          %{
            id: binary(),
            total_abundance: non_neg_integer(),
            cluster: String.t(),              # "biofilm" | "motile" | "stress-tolerant" | "generalist" | "cryptic"
            color: String.t(),
            phase_abundance: %{String.t() => non_neg_integer()}
          }
        ]
      }

  ## Output (atom-keyed)

      %{
        width: 800,
        height: 480,
        tick: 42,
        selected_phase: "surface" | nil,
        bands: [%{name, label, color, x, y, w, h, total_abundance, ...}],
        particles: [%{cx, cy, r, color, cluster, lineage_id, key}],
        empty?: false
      }
  """

  @viewbox_w 800
  @viewbox_h 480
  @h_margin 26
  @v_margin 22
  @top_overlay_gutter 32
  @bottom_overlay_gutter 20
  @band_gap 10
  @max_phase_particles 60

  @type snapshot :: map()
  @type layout :: map()

  @doc """
  Build a layout from a snapshot. Returns a map with bands and particles
  pre-positioned in the @viewbox_w × @viewbox_h coordinate system.
  """
  @spec build(snapshot()) :: layout()
  def build(snapshot) when is_map(snapshot) do
    phases = snapshot[:phases] || []
    lineages = snapshot[:lineages] || []
    selected = snapshot[:selected_phase]

    bands = layout_bands(phases, selected)
    particles = Enum.flat_map(bands, &particles_for_band(&1, lineages))

    %{
      width: @viewbox_w,
      height: @viewbox_h,
      tick: snapshot[:tick] || 0,
      selected_phase: selected,
      bands: bands,
      particles: particles,
      empty?: phases == []
    }
  end

  @doc "Convenience: viewBox string `0 0 W H`."
  def viewbox, do: "0 0 #{@viewbox_w} #{@viewbox_h}"

  # ---------------------------------------------------------------------------
  # Bands

  defp layout_bands([], _selected), do: []

  defp layout_bands(phases, selected) do
    inner_w = @viewbox_w - @h_margin * 2
    top_inset = @v_margin + @top_overlay_gutter
    bottom_inset = @v_margin + @bottom_overlay_gutter
    inner_h = @viewbox_h - top_inset - bottom_inset - @band_gap * max(length(phases) - 1, 0)

    weights = Enum.map(phases, fn p -> max(p[:total_abundance] || 0, 1) end)
    total_weight = Enum.sum(weights)
    min_band = min(72, inner_h / max(length(phases), 1))
    extra_h = max(0.0, inner_h - min_band * length(phases))

    {bands, _} =
      phases
      |> Enum.with_index()
      |> Enum.reduce({[], top_inset * 1.0}, fn {phase, idx}, {acc, cursor_y} ->
        weight = Enum.at(weights, idx)
        share = if total_weight > 0, do: extra_h * weight / total_weight, else: 0
        h_share = min_band + share

        h =
          if idx == length(phases) - 1 do
            @viewbox_h - bottom_inset - cursor_y
          else
            max(52.0, h_share)
          end

        band = %{
          name: phase[:name],
          label: phase[:label],
          color: phase[:color] || "#94a3b8",
          temperature: phase[:temperature],
          ph: phase[:ph],
          dilution_rate: phase[:dilution_rate],
          total_abundance: phase[:total_abundance] || 0,
          lineage_count: phase[:lineage_count] || 0,
          x: @h_margin * 1.0,
          y: cursor_y,
          w: inner_w * 1.0,
          h: h,
          selected?: phase[:name] == selected
        }

        {[band | acc], cursor_y + h + @band_gap}
      end)

    Enum.reverse(bands)
  end

  # ---------------------------------------------------------------------------
  # Particles

  defp particles_for_band(band, lineages) do
    in_band =
      lineages
      |> Enum.map(fn l ->
        n = get_in(l, [:phase_abundance, band.name]) || 0
        {l, n}
      end)
      |> Enum.filter(fn {_, n} -> n > 0 end)
      |> Enum.sort_by(fn {_, n} -> n end, :desc)

    if in_band == [] do
      []
    else
      total = Enum.reduce(in_band, 0, fn {_, n}, acc -> acc + n end)

      budget =
        max(18, min(@max_phase_particles, round(20 + :math.sqrt(total) * 2.5)))

      {particles, _used} =
        Enum.reduce(in_band, {[], 0}, fn {lineage, abundance}, {acc, used} ->
          if used >= budget do
            {acc, used}
          else
            fraction = if total > 0, do: abundance / total, else: 0.0
            count_raw = round(fraction * budget)

            count =
              cond do
                count_raw == 0 and abundance > 0 and used < budget * 0.75 -> 1
                true -> count_raw
              end
              |> min(budget - used)

            new_particles =
              for i <- 0..(count - 1)//1, count > 0 do
                build_particle(band, lineage, fraction, i)
              end

            {acc ++ new_particles, used + count}
          end
        end)

      particles
    end
  end

  defp build_particle(band, lineage, fraction, i) do
    seed = {band.name, lineage[:id], i}
    h = :erlang.phash2(seed, 1_000_000_007)
    ax = rem(h, 10_000) / 10_000.0
    ay = rem(div(h, 10_000), 10_000) / 10_000.0
    ar = rem(div(h, 100_000_000), 1000) / 1000.0

    cx = band.x + 18 + ax * max(band.w - 36, 10)
    cy = band.y + 22 + ay * max(band.h - 44, 10)
    base_r = 1.2 + fraction * 5.5 + ar * 0.5

    %{
      key: "#{band.name}:#{lineage[:id]}:#{i}",
      cx: cx,
      cy: cy,
      r: Float.round(base_r, 2),
      color: lineage[:color] || "#94a3b8",
      cluster: lineage[:cluster] || "generalist",
      lineage_id: lineage[:id]
    }
  end
end
