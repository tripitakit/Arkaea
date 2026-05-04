defmodule Arkea.Views.ArkeonSchematic do
  @moduledoc """
  Pure layout for a schematic SVG of the Arkeon cell.

  Translates the seed `preview` (spec + phenotype + genome) into a structured
  set of geometric primitives that the HEEx component can render directly.
  The output is *diagrammatic*, not microscope-faithful: each visual feature
  has a one-to-one biological correspondence with a feature of the modelled
  phenotype, but proportions are tuned for legibility at a glance.

  ## What's drawn (and why)

    * **Envelope** — the outer cell boundary, parameterised by the
      `membrane_profile`. `:porous` → smooth elliptical contour; `:fortified`
      → second concentric outline (double-membrane / cell-wall hint);
      `:salinity_tuned` → scalloped contour (osmotic deformation).
    * **Transmembrane spans** — short radial bars crossing the envelope, one
      per `phenotype.n_transmembrane`. Distributed evenly around the cell.
    * **Cytoplasm** — softly tinted interior whose density hint comes from
      the `metabolism_profile`.
    * **Nucleoid** — the chromosome as a compact looped curve in the centre,
      drawn denser for `:bloom`, sparser for `:thrifty`.
    * **Plasmids** — small isolated rings near the nucleoid, one per
      plasmid in the genome (cap at 3 for legibility).
    * **Prophage mark** — a triangular notch integrated into the nucleoid
      when at least one prophage is present.
    * **Storage granules** — scattered small filled dots in the cytoplasm,
      count proportional to the metabolism profile (`:bloom` ≫ `:thrifty`).
    * **Surface appendages** — pili, adhesins, phage receptors derived
      from `phenotype.surface_tags`.
    * **Flagellum** — single curved tail when the phenotype clusters as
      "motile" (heuristic: `n_transmembrane >= 2`).
    * **Stress halo** — faint dashed outer ring when `regulation_profile`
      is `:mutator`.

  Output is pure data (atom-keyed maps); no I/O, no GenServer, no HTML.
  """

  @viewbox_w 360
  @viewbox_h 320
  @cx 180
  @cy 160
  @rx 116
  @ry 76

  @type layout :: map()

  @doc """
  Build the schematic layout from a seed `preview` (output of
  `Arkea.Game.SeedLab.preview/1` or any compatible map carrying the
  fields `:spec`, `:phenotype`, `:genome`).
  """
  @spec build(map()) :: layout()
  def build(preview) when is_map(preview) do
    spec = Map.get(preview, :spec, %{})
    phenotype = Map.get(preview, :phenotype, %{})
    genome = Map.get(preview, :genome, %{})

    membrane = membrane_atom(get(spec, :membrane_profile))
    metabolism = metabolism_atom(get(spec, :metabolism_profile))
    regulation = regulation_atom(get(spec, :regulation_profile))
    mobile = mobile_atom(get(spec, :mobile_module))

    n_tm = max(get(phenotype, :n_transmembrane, 0), 0) |> min(12)
    surface_tags = List.wrap(get(phenotype, :surface_tags, []))

    cluster = cluster_for(phenotype, surface_tags, n_tm)

    %{
      viewbox: viewbox(),
      width: @viewbox_w,
      height: @viewbox_h,
      envelope: envelope(membrane),
      membrane_spans: transmembrane_spans(n_tm, membrane),
      cytoplasm: cytoplasm(metabolism),
      nucleoid: nucleoid(metabolism),
      plasmids: plasmids(get(genome, :plasmids, []), mobile),
      prophage: prophage(get(genome, :prophages, []), mobile),
      granules: granules(metabolism),
      surface_appendages: appendages(surface_tags),
      flagellum: flagellum_for(cluster, mobile),
      stress_halo: stress_halo(regulation),
      cluster: cluster,
      legend: legend(membrane, metabolism, regulation, mobile)
    }
  end

  # Map/struct accessor that doesn't require Access protocol.
  defp get(container, key, default \\ nil)
  defp get(%_{} = struct, key, default), do: Map.get(struct, key, default)
  defp get(map, key, default) when is_map(map), do: Map.get(map, key, default)
  defp get(_, _, default), do: default

  @doc "viewBox attribute string (`0 0 W H`)."
  def viewbox, do: "0 0 #{@viewbox_w} #{@viewbox_h}"

  # ---------------------------------------------------------------------------
  # Envelope

  # Each membrane profile produces a structurally different envelope:
  # `:porous` is a single thin membrane studded with porin marks; `:fortified`
  # is a true double envelope with a visible periplasmic shell + inner
  # plasma membrane; `:salinity_tuned` adds deep scalloping (osmotic
  # adaptation) plus an inner ion-handling layer.

  defp envelope(:porous) do
    %{
      kind: :porous,
      cx: @cx,
      cy: @cy,
      rx: @rx,
      ry: @ry,
      double?: false,
      stroke_width: 1.6,
      porins: porin_marks(8)
    }
  end

  defp envelope(:fortified) do
    inner_offset = 7

    %{
      kind: :fortified,
      cx: @cx,
      cy: @cy,
      rx: @rx,
      ry: @ry,
      double?: true,
      inner_offset: inner_offset,
      stroke_width: 2.4,
      inner_stroke_width: 1.4,
      # Periplasm: small radial ticks between outer and inner envelope,
      # suggesting the dense peptidoglycan layer.
      periplasm_ticks: periplasm_ticks(inner_offset, 30)
    }
  end

  defp envelope(:salinity_tuned) do
    inner_offset = 5

    %{
      kind: :salinity_tuned,
      cx: @cx,
      cy: @cy,
      rx: @rx,
      ry: @ry,
      lobes: 22,
      lobe_amp: 4.5,
      path: scalloped_path(@cx, @cy, @rx, @ry, 22, 4.5),
      inner_offset: inner_offset,
      stroke_width: 2.0,
      inner_stroke_width: 1.0,
      # Inner ion-handling layer: a slightly smaller dashed ellipse hinting
      # at the compartmentalised ion sequestration these envelopes carry.
      inner_dashed?: true
    }
  end

  defp envelope(_), do: envelope(:porous)

  # Porins: small open circles INSIDE the membrane line, evenly distributed.
  # Make the "porous" name visible at a glance without crowding the cell.
  defp porin_marks(n) do
    for i <- 0..(n - 1) do
      theta = i * 2 * :math.pi() / n
      cx = @cx + @rx * :math.cos(theta)
      cy = @cy + @ry * :math.sin(theta)
      %{cx: cx, cy: cy, r: 2.4, index: i}
    end
  end

  # Periplasmic ticks: short radial line segments between outer and inner
  # envelope ellipses for the fortified profile. They suggest the dense
  # peptidoglycan / S-layer scaffolding sitting in the periplasm.
  defp periplasm_ticks(inner_offset, n) do
    pad = 0.8

    for i <- 0..(n - 1) do
      theta = i * 2 * :math.pi() / n
      cos_t = :math.cos(theta)
      sin_t = :math.sin(theta)

      x_outer = @cx + (@rx - pad) * cos_t
      y_outer = @cy + (@ry - pad) * sin_t
      x_inner = @cx + (@rx - inner_offset + pad) * cos_t
      y_inner = @cy + (@ry - inner_offset + pad) * sin_t

      %{x1: x_outer, y1: y_outer, x2: x_inner, y2: y_inner, index: i}
    end
  end

  defp scalloped_path(cx, cy, rx, ry, lobes, amp) do
    points =
      for i <- 0..(lobes * 2 - 1) do
        theta = i * :math.pi() / lobes
        wave = if rem(i, 2) == 0, do: amp, else: -amp
        x = cx + (rx + wave) * :math.cos(theta)
        y = cy + (ry + wave) * :math.sin(theta)
        {x, y}
      end

    [first | rest] = points
    {fx, fy} = first

    instructions =
      ["M ", f(fx), " ", f(fy)] ++
        Enum.flat_map(rest, fn {x, y} -> [" L ", f(x), " ", f(y)] end) ++ [" Z"]

    IO.iodata_to_binary(instructions)
  end

  # ---------------------------------------------------------------------------
  # Transmembrane spans

  defp transmembrane_spans(0, _membrane), do: []

  defp transmembrane_spans(n, membrane) do
    inner = if membrane == :fortified, do: 4, else: 0
    span_len = if membrane == :fortified, do: 9, else: 7

    for i <- 0..(n - 1) do
      theta = -:math.pi() / 2 + i * 2 * :math.pi() / n
      cos_t = :math.cos(theta)
      sin_t = :math.sin(theta)

      x_outer = @cx + (@rx + span_len / 2) * cos_t
      y_outer = @cy + (@ry + span_len / 2) * sin_t
      x_inner = @cx + (@rx - span_len / 2 - inner) * cos_t
      y_inner = @cy + (@ry - span_len / 2 - inner) * sin_t

      %{x1: x_outer, y1: y_outer, x2: x_inner, y2: y_inner, index: i}
    end
  end

  # ---------------------------------------------------------------------------
  # Cytoplasm

  defp cytoplasm(:bloom), do: %{fill_opacity: 0.22, density: :high}
  defp cytoplasm(:balanced), do: %{fill_opacity: 0.16, density: :medium}
  defp cytoplasm(:thrifty), do: %{fill_opacity: 0.10, density: :low}
  defp cytoplasm(_), do: %{fill_opacity: 0.16, density: :medium}

  # ---------------------------------------------------------------------------
  # Nucleoid (looped chromosome representation)
  #
  # Drawn as a small near-circular polyline with subtle wobble — denser
  # nucleoid for high-metabolism profiles.

  # The nucleoid is rendered as three overlapping loops at different
  # rotations, suggesting the folded supercoiled DNA actually visible in
  # bacterial cells. The number of coil bumps per loop tracks the metabolism
  # profile (more active metabolism → denser, more wrinkled chromosome).

  defp nucleoid(metabolism) do
    {coil_count, base_radius} =
      case metabolism do
        :bloom -> {7, 26}
        :balanced -> {5, 24}
        :thrifty -> {4, 22}
        _ -> {5, 24}
      end

    loops =
      for {tilt, scale} <- [{0.0, 1.0}, {:math.pi() / 3, 0.86}, {-:math.pi() / 3, 0.92}] do
        ry_loop = base_radius * scale * 0.62

        nucleoid_loop(@cx, @cy, base_radius, ry_loop, coil_count, tilt)
      end

    %{
      cx: @cx,
      cy: @cy,
      radius: base_radius,
      coil_count: coil_count,
      loops: loops
    }
  end

  defp nucleoid_loop(cx, cy, rx, ry, coil_count, tilt) do
    samples = 36

    points =
      for i <- 0..(samples - 1) do
        theta = i * 2 * :math.pi() / samples
        wobble = :math.sin(theta * coil_count) * 1.8

        # Local coords around (0,0), then rotate by `tilt`.
        lx = (rx + wobble) * :math.cos(theta)
        ly = (ry + wobble) * :math.sin(theta)

        cos_t = :math.cos(tilt)
        sin_t = :math.sin(tilt)

        x = cx + lx * cos_t - ly * sin_t
        y = cy + lx * sin_t + ly * cos_t
        {x, y}
      end

    %{path: polyline_path(points), tilt: tilt}
  end

  defp polyline_path([]), do: ""

  defp polyline_path([{fx, fy} | rest]) do
    instructions =
      ["M ", f(fx), " ", f(fy)] ++
        Enum.flat_map(rest, fn {x, y} -> [" L ", f(x), " ", f(y)] end) ++ [" Z"]

    IO.iodata_to_binary(instructions)
  end

  # ---------------------------------------------------------------------------
  # Plasmids (small isolated rings)

  defp plasmids([], :conjugative_plasmid), do: [hint_plasmid()]
  defp plasmids([], _), do: []

  defp plasmids(plasmids, _mobile) do
    plasmids
    |> Enum.with_index()
    |> Enum.take(3)
    |> Enum.map(fn {_p, idx} ->
      angle = -:math.pi() / 4 + idx * :math.pi() / 3
      pcx = @cx + 28 * :math.cos(angle)
      pcy = @cy + 22 * :math.sin(angle)

      %{
        cx: pcx,
        cy: pcy,
        rx: 5.5,
        ry: 4.2,
        index: idx
      }
    end)
  end

  # When the player chose `conjugative_plasmid` but the genome hasn't
  # materialised one yet (e.g. seed preview pre-provisioning), still hint
  # at the upcoming plasmid so the schematic is consistent with the choice.
  defp hint_plasmid do
    %{
      cx: @cx + 28,
      cy: @cy - 14,
      rx: 5.5,
      ry: 4.2,
      index: 0,
      hinted?: true
    }
  end

  # ---------------------------------------------------------------------------
  # Prophage (mark integrated into the nucleoid)

  defp prophage([_ | _] = _prophages, _mobile), do: prophage_mark()
  defp prophage(_, :latent_prophage), do: prophage_mark()
  defp prophage(_, _), do: nil

  # The prophage is rendered as a *labelled cassette* sitting on top of
  # the nucleoid: a thicker red/magenta arc segment with a bold "Φ" glyph
  # in its centre. Reads at a glance as "integrated phage genome on the
  # chromosome" rather than a generic decoration.

  defp prophage_mark do
    # Place the cassette on the upper-left of the nucleoid loop family
    # so it doesn't collide with the plasmids (which sit upper-right).
    angle = -:math.pi() * 0.62
    base_radius = 28
    sweep = :math.pi() * 0.32

    start_angle = angle - sweep / 2
    end_angle = angle + sweep / 2

    inner_r = base_radius - 3.5
    outer_r = base_radius + 3.5

    arc_path =
      ring_arc_path(@cx, @cy, outer_r, inner_r, start_angle, end_angle)

    label_x = @cx + base_radius * :math.cos(angle)
    label_y = @cy + base_radius * :math.sin(angle)

    %{
      kind: :integrated_cassette,
      arc_path: arc_path,
      label_x: label_x,
      label_y: label_y,
      label: "Φ"
    }
  end

  # Closed annular wedge — re-used from genome_canvas for the prophage
  # cassette. Inlined here to avoid a cross-module dependency on a UI
  # rendering helper.

  defp ring_arc_path(cx, cy, r_outer, r_inner, start_angle, end_angle) do
    large_arc = if end_angle - start_angle > :math.pi(), do: 1, else: 0

    x1 = cx + r_outer * :math.cos(start_angle)
    y1 = cy + r_outer * :math.sin(start_angle)
    x2 = cx + r_outer * :math.cos(end_angle)
    y2 = cy + r_outer * :math.sin(end_angle)
    x3 = cx + r_inner * :math.cos(end_angle)
    y3 = cy + r_inner * :math.sin(end_angle)
    x4 = cx + r_inner * :math.cos(start_angle)
    y4 = cy + r_inner * :math.sin(start_angle)

    [
      "M ",
      f(x1),
      " ",
      f(y1),
      " A ",
      f(r_outer),
      " ",
      f(r_outer),
      " 0 ",
      Integer.to_string(large_arc),
      " 1 ",
      f(x2),
      " ",
      f(y2),
      " L ",
      f(x3),
      " ",
      f(y3),
      " A ",
      f(r_inner),
      " ",
      f(r_inner),
      " 0 ",
      Integer.to_string(large_arc),
      " 0 ",
      f(x4),
      " ",
      f(y4),
      " Z"
    ]
    |> IO.iodata_to_binary()
  end

  # ---------------------------------------------------------------------------
  # Storage granules

  # Storage granules: bigger, with a discernible inner highlight (rendered
  # as a smaller paler circle on top of the granule body). Visually they
  # read as distinct *inclusions* (poly-β-hydroxybutyrate / polyP /
  # glycogen-like) rather than tiny dots. Distinct color from prophage
  # (we use gold/amber here; prophage uses red/magenta).

  defp granules(metabolism) do
    count =
      case metabolism do
        :bloom -> 8
        :balanced -> 5
        :thrifty -> 2
        _ -> 4
      end

    seed = :erlang.phash2({:granules, metabolism}, 1_000_000_007)

    for i <- 0..(count - 1) do
      h = :erlang.phash2({seed, i}, 1_000_000_007)
      ax = rem(h, 1000) / 1000.0
      ay = rem(div(h, 1000), 1000) / 1000.0
      ar = rem(div(h, 1_000_000), 1000) / 1000.0

      # Place inside an annular band: outside the nucleoid but inside the
      # envelope, biased toward the periphery so granules don't overlap
      # the nucleoid loops.
      angle = ax * 2 * :math.pi()
      r_norm = 0.55 + ay * 0.30
      x = @cx + r_norm * (@rx - 18) * :math.cos(angle)
      y = @cy + r_norm * (@ry - 18) * :math.sin(angle)

      r = 3.4 + ar * 1.2

      %{
        cx: x,
        cy: y,
        r: r,
        # Inner highlight gives them volume — subtle but recognisable.
        highlight_cx: x - r * 0.32,
        highlight_cy: y - r * 0.32,
        highlight_r: r * 0.38,
        index: i
      }
    end
  end

  # ---------------------------------------------------------------------------
  # Surface appendages (pili, adhesins, phage receptor)

  defp appendages([]), do: []

  defp appendages(surface_tags) when is_list(surface_tags) do
    surface_tags
    |> Enum.uniq()
    |> Enum.with_index()
    |> Enum.flat_map(fn {tag, idx} -> appendage_for(tag, idx) end)
  end

  defp appendage_for(tag, idx) do
    base_angle = idx * 2 * :math.pi() / 5 + 0.5

    case tag do
      :adhesin -> [appendage(:adhesin, base_angle)]
      :biofilm -> [appendage(:adhesin, base_angle), appendage(:adhesin, base_angle + 0.3)]
      :matrix -> [appendage(:adhesin, base_angle + 0.6)]
      :phage_receptor -> [appendage(:phage_receptor, base_angle + 1.1)]
      :pilus -> [appendage(:pilus, base_angle)]
      _ -> []
    end
  end

  defp appendage(:pilus, angle) do
    cos_t = :math.cos(angle)
    sin_t = :math.sin(angle)
    x1 = @cx + @rx * cos_t
    y1 = @cy + @ry * sin_t
    x2 = @cx + (@rx + 14) * cos_t
    y2 = @cy + (@ry + 14) * sin_t
    %{kind: :pilus, x1: x1, y1: y1, x2: x2, y2: y2}
  end

  defp appendage(:adhesin, angle) do
    cos_t = :math.cos(angle)
    sin_t = :math.sin(angle)
    cx = @cx + (@rx + 3) * cos_t
    cy = @cy + (@ry + 3) * sin_t
    %{kind: :adhesin, cx: cx, cy: cy, r: 2.6}
  end

  defp appendage(:phage_receptor, angle) do
    cos_t = :math.cos(angle)
    sin_t = :math.sin(angle)
    base_x = @cx + @rx * cos_t
    base_y = @cy + @ry * sin_t
    tip_x = @cx + (@rx + 9) * cos_t
    tip_y = @cy + (@ry + 9) * sin_t
    # Cross-bar on the tip (the "T" mark — recognisable as a receptor)
    perp_x = -sin_t * 3
    perp_y = cos_t * 3

    %{
      kind: :phage_receptor,
      base_x: base_x,
      base_y: base_y,
      tip_x: tip_x,
      tip_y: tip_y,
      bar_start_x: tip_x - perp_x,
      bar_start_y: tip_y - perp_y,
      bar_end_x: tip_x + perp_x,
      bar_end_y: tip_y + perp_y
    }
  end

  # ---------------------------------------------------------------------------
  # Flagellum

  defp flagellum_for(:motile, _mobile), do: flagellum()
  defp flagellum_for(_, _), do: nil

  defp flagellum do
    # A single curved bezier flagellum coming off the right end of the cell.
    base_x = @cx + @rx
    base_y = @cy + 4
    end_x = base_x + 60
    end_y = @cy - 8
    ctrl1_x = base_x + 18
    ctrl1_y = @cy + 22
    ctrl2_x = base_x + 44
    ctrl2_y = @cy - 24

    path =
      [
        "M ",
        f(base_x),
        " ",
        f(base_y),
        " C ",
        f(ctrl1_x),
        " ",
        f(ctrl1_y),
        " ",
        f(ctrl2_x),
        " ",
        f(ctrl2_y),
        " ",
        f(end_x),
        " ",
        f(end_y)
      ]
      |> IO.iodata_to_binary()

    %{path: path, base_x: base_x, base_y: base_y, end_x: end_x, end_y: end_y}
  end

  # ---------------------------------------------------------------------------
  # Stress halo
  #
  # Composed of five stacked ellipses (outer → inner): a wide soft glow that
  # fades almost to transparent at the outer edge, three intermediate bands
  # with progressively higher opacity, and a near-the-cell dashed ring that
  # carries the "rotational shimmer" animation in CSS. Stacking multiple
  # rings rather than relying on an SVG <filter> avoids feGaussianBlur
  # rendering quirks across browsers and keeps the halo crisp at any zoom.

  defp stress_halo(:mutator) do
    cx = @cx
    cy = @cy

    rings = [
      # Outer-most very soft glow.
      %{layer: :glow_outer, rx: @rx + 34, ry: @ry + 28, stroke_width: 10.0, opacity: 0.10},
      # Wide mid glow.
      %{layer: :glow_mid, rx: @rx + 24, ry: @ry + 20, stroke_width: 7.0, opacity: 0.20},
      # Inner glow band.
      %{layer: :glow_inner, rx: @rx + 16, ry: @ry + 13, stroke_width: 4.5, opacity: 0.34},
      # Dashed "shimmer" ring — the one that rotates / pulses; reads as the
      # actual halo edge.
      %{
        layer: :shimmer,
        rx: @rx + 9,
        ry: @ry + 7,
        stroke_width: 1.6,
        opacity: 0.85,
        dasharray: "3 4"
      },
      # Faint accent right above the envelope.
      %{layer: :accent, rx: @rx + 4, ry: @ry + 3, stroke_width: 0.8, opacity: 0.45}
    ]

    %{cx: cx, cy: cy, rings: rings}
  end

  defp stress_halo(_), do: nil

  # ---------------------------------------------------------------------------
  # Cluster heuristic (UI-only, mirrors sim_live phenotype_cluster fallback).
  # Order matches `SimLive.phenotype_cluster/1`:
  #   biofilm > motile > stress-tolerant > generalist.

  defp cluster_for(phenotype, surface_tags, n_tm) when is_list(surface_tags) do
    repair = get(phenotype, :repair_efficiency, 0.0)
    stability = get(phenotype, :structural_stability, 0.0)

    cond do
      Enum.any?(surface_tags, &(&1 in [:adhesin, :matrix, :biofilm])) ->
        :biofilm

      n_tm >= 2 ->
        :motile

      repair + stability >= 1.35 ->
        :stress_tolerant

      true ->
        :generalist
    end
  end

  defp cluster_for(_, _, _), do: :generalist

  # ---------------------------------------------------------------------------
  # Legend (4 lines, paired with the icon — same content the previous
  # implementation rendered, kept here so the component is one stop)

  defp legend(membrane, metabolism, regulation, mobile) do
    [
      %{label: "Envelope", value: membrane_copy(membrane)},
      %{label: "Metabolism", value: metabolism_copy(metabolism)},
      %{label: "Regulation", value: regulation_copy(regulation)},
      %{label: "Accessory", value: accessory_copy(mobile)}
    ]
  end

  defp membrane_copy(:porous), do: "Light shell, lower structural cost."
  defp membrane_copy(:fortified), do: "Thicker wall, higher upkeep, sturdier shell."
  defp membrane_copy(:salinity_tuned), do: "Membrane bias toward osmotic tolerance."
  defp membrane_copy(_), do: "Default membrane."

  defp metabolism_copy(:thrifty), do: "Slow, efficient uptake in lean environments."
  defp metabolism_copy(:balanced), do: "Mixed-phase generalist throughput."
  defp metabolism_copy(:bloom), do: "Fast, high-yield bursts on rich substrates."
  defp metabolism_copy(_), do: "Default metabolism."

  defp regulation_copy(:steady), do: "High repair, low mutation, conservative SOS."
  defp regulation_copy(:responsive), do: "Adaptive regulation, SOS-ready."
  defp regulation_copy(:mutator), do: "Low repair, hypermutator strain."
  defp regulation_copy(_), do: "Default regulation."

  defp accessory_copy(:none), do: "No accessory mobile module."
  defp accessory_copy(:conjugative_plasmid), do: "Conjugative plasmid pre-loaded."
  defp accessory_copy(:latent_prophage), do: "Latent prophage integrated."
  defp accessory_copy(_), do: "—"

  # ---------------------------------------------------------------------------
  # Coercion helpers (preview spec fields may be string- or atom-valued).

  defp membrane_atom(v), do: profile_atom(v, [:porous, :fortified, :salinity_tuned], :porous)
  defp metabolism_atom(v), do: profile_atom(v, [:thrifty, :balanced, :bloom], :balanced)
  defp regulation_atom(v), do: profile_atom(v, [:steady, :responsive, :mutator], :responsive)

  defp mobile_atom(v),
    do: profile_atom(v, [:none, :conjugative_plasmid, :latent_prophage], :none)

  defp profile_atom(v, allowed, default) when is_atom(v) do
    if v in allowed, do: v, else: default
  end

  defp profile_atom(v, allowed, default) when is_binary(v) do
    candidate = String.to_existing_atom(v)
    if candidate in allowed, do: candidate, else: default
  rescue
    ArgumentError -> default
  end

  defp profile_atom(_, _, default), do: default

  # ---------------------------------------------------------------------------
  # Number formatting for SVG path strings.

  defp f(num) when is_number(num) do
    Float.round(num * 1.0, 2) |> Float.to_string()
  end
end
