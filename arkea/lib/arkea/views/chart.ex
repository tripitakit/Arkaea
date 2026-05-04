defmodule Arkea.Views.Chart do
  @moduledoc """
  Pure SVG chart helpers (UI Phase C).

  This module is the visualisation primitive layer used by every chart
  shipping in Phase C and beyond. It does not render — it computes
  scales, paths, axis ticks and bin maps, which the Phoenix function
  components in `ArkeaWeb.Components.Chart` then turn into SVG.

  Discipline: deterministic and pure. No DOM, no Phoenix, no IO.

  ## Conventions

  - The chart viewport uses the standard SVG coordinate system: `(0, 0)`
    is top-left, `y` increases downward. `linear_scale/3` flips the
    domain so larger values render higher on screen.
  - All scales return a `(value -> coordinate)` function (`(number ->
    float)`) so callers can pre-compute the function once and apply it
    per-point.
  - Series are lists of `{x, y}` pairs of numbers (NaN-free; callers
    must sanitise upstream).
  - Path strings use a single-character SVG command alphabet
    (`M`/`L`/`Z`) for maximum compatibility with the SVG renderer used
    everywhere in Arkea.
  """

  @type point :: {number(), number()}
  @type series :: [point()]
  @type scale_fn :: (number() -> float())
  @type domain :: {number(), number()}

  @doc """
  Build a linear scale function from `domain` to `range`. The returned
  function clamps inputs to the domain.
  """
  @spec linear_scale(domain(), domain(), keyword()) :: scale_fn()
  def linear_scale({d_min, d_max} = _domain, {r_min, r_max} = _range, _opts \\ [])
      when is_number(d_min) and is_number(d_max) and is_number(r_min) and is_number(r_max) do
    span_d = d_max - d_min

    cond do
      span_d == 0 ->
        fn _v -> r_min * 1.0 end

      true ->
        slope = (r_max - r_min) / span_d
        fn v -> r_min + (clamp(v, d_min, d_max) - d_min) * slope end
    end
  end

  @doc """
  Build a log10 scale function. Inputs ≤ 0 are clamped to a small
  positive epsilon (default 1.0e-6) to avoid `:math.log10/1` raising.
  """
  @spec log_scale(domain(), domain(), keyword()) :: scale_fn()
  def log_scale({d_min, d_max}, {r_min, r_max}, opts \\ []) do
    epsilon = Keyword.get(opts, :epsilon, 1.0e-6)

    safe_min = max(d_min, epsilon)
    safe_max = max(d_max, safe_min * (1 + epsilon))

    log_min = :math.log10(safe_min)
    log_max = :math.log10(safe_max)
    span = log_max - log_min

    if span <= 0 do
      fn _v -> r_min * 1.0 end
    else
      slope = (r_max - r_min) / span

      fn v ->
        clamped = max(v, epsilon) |> min(safe_max)
        r_min + (:math.log10(clamped) - log_min) * slope
      end
    end
  end

  @doc """
  Compute "nice" tick values for a numeric axis between `min` and
  `max`, biased toward 5 to 8 ticks total (configurable). The
  algorithm is the standard "nice number" rounding (Heckbert 1990).
  """
  @spec axis_ticks(number(), number(), keyword()) :: [number()]
  def axis_ticks(min, max, opts \\ []) when is_number(min) and is_number(max) do
    target = Keyword.get(opts, :target, 6)

    cond do
      min >= max ->
        [min]

      true ->
        range = nice_number(max - min, false)
        step = nice_number(range / max(target - 1, 1), true)

        nice_min = :math.floor(min / step) * step
        nice_max = :math.ceil(max / step) * step

        Stream.iterate(nice_min, fn t -> t + step end)
        |> Enum.take_while(fn t -> t <= nice_max + step / 2 end)
    end
  end

  @doc """
  Build an SVG `<path d>` string from a list of points using the given
  scale functions for x and y. Returns the path data only (no `<path>`
  wrapping).

  Empty input returns an empty string (so callers can drop the path
  node entirely without conditional logic).

  ## Options

    * `:closed` — `true` to close the path with a `Z`. Default `false`.
    * `:downsample` — integer; if the series has more than this many
      points, bin sequential pairs (mean) until under threshold.
      Default `2_000`.
  """
  @spec path_for_series(series(), scale_fn(), scale_fn(), keyword()) :: String.t()
  def path_for_series(points, x_scale, y_scale, opts \\ [])

  def path_for_series([], _x_scale, _y_scale, _opts), do: ""

  def path_for_series(points, x_scale, y_scale, opts) when is_list(points) do
    closed? = Keyword.get(opts, :closed, false)
    downsampled = downsample(points, Keyword.get(opts, :downsample, 2_000))

    [{x0, y0} | rest] = downsampled

    head = "M#{format(x_scale.(x0))} #{format(y_scale.(y0))}"

    body =
      Enum.reduce(rest, [], fn {x, y}, acc ->
        ["L#{format(x_scale.(x))} #{format(y_scale.(y))}" | acc]
      end)
      |> Enum.reverse()
      |> Enum.join("")

    [head, body, if(closed?, do: "Z", else: "")]
    |> Enum.join("")
  end

  @doc """
  Build a stacked-area path series. Given a list of `{label, points}`
  pairs all sharing the same x-axis values, returns a list of `{label,
  path_d}` for each layer. Layer order is preserved.
  """
  @spec stacked_area_paths([{term(), series()}], scale_fn(), scale_fn(), keyword()) ::
          [{term(), String.t()}]
  def stacked_area_paths(layers, x_scale, y_scale, opts \\ [])

  def stacked_area_paths([], _x_scale, _y_scale, _opts), do: []

  def stacked_area_paths(layers, x_scale, y_scale, opts) when is_list(layers) do
    {_, baseline} = build_baseline(layers)

    {_acc, paths} =
      Enum.reduce(layers, {baseline, []}, fn {label, points}, {prev_baseline, acc} ->
        new_baseline =
          Enum.zip_with(prev_baseline, points, fn {x, y_low}, {_, dy} -> {x, y_low + dy} end)

        upper_path = path_for_series(new_baseline, x_scale, y_scale, opts)
        lower_path = path_for_series(Enum.reverse(prev_baseline), x_scale, y_scale, opts)

        # Concatenate "upper, then lower reversed, then close" to form a closed shape.
        d =
          upper_path <>
            String.replace_prefix(
              lower_path,
              "M",
              "L"
            ) <> "Z"

        {new_baseline, [{label, d} | acc]}
      end)

    Enum.reverse(paths)
  end

  @doc """
  Bucket points into equal-width bins and return the per-bin mean.
  Used by the heatmap builder to coarsen ticks into pixel columns.
  """
  @spec bin_mean([{number(), number()}], pos_integer()) :: [{number(), float()}]
  def bin_mean([], _n_bins), do: []

  def bin_mean(points, n_bins) when n_bins >= 1 do
    {min_x, max_x} =
      points
      |> Enum.map(&elem(&1, 0))
      |> Enum.min_max()

    span = max(max_x - min_x, 1)
    bin_width = span / n_bins

    points
    |> Enum.group_by(fn {x, _} ->
      div(round((x - min_x) * 1.0), max(round(bin_width), 1))
    end)
    |> Enum.sort_by(fn {bin, _} -> bin end)
    |> Enum.map(fn {bin, ps} ->
      mean_y = Enum.sum(Enum.map(ps, &elem(&1, 1))) / length(ps)
      x = min_x + (bin + 0.5) * bin_width
      {x, mean_y}
    end)
  end

  @doc """
  Format a numeric coordinate for SVG output. Trims trailing zeros and
  rounds to 2 decimals to keep path strings compact.
  """
  @spec format(number()) :: String.t()
  def format(value) when is_integer(value), do: Integer.to_string(value)

  def format(value) when is_float(value) do
    case Float.round(value, 2) do
      n when n == trunc(n) -> Integer.to_string(trunc(n))
      n -> Float.to_string(n)
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers

  defp clamp(v, lo, _hi) when v < lo, do: lo
  defp clamp(v, _lo, hi) when v > hi, do: hi
  defp clamp(v, _lo, _hi), do: v

  # If the series exceeds `max_points`, average sequential pairs until
  # within budget. Stable: returns at least one point for any non-empty
  # input.
  defp downsample(points, max_points) when length(points) <= max_points, do: points

  defp downsample(points, max_points) do
    factor = ceil(length(points) / max_points)

    points
    |> Enum.chunk_every(factor)
    |> Enum.map(fn chunk ->
      n = length(chunk)
      mean_x = Enum.sum(Enum.map(chunk, &elem(&1, 0))) / n
      mean_y = Enum.sum(Enum.map(chunk, &elem(&1, 1))) / n
      {mean_x, mean_y}
    end)
  end

  # Build the zero-baseline list `{x, 0.0}` from the first layer.
  defp build_baseline([{_label, points} | _] = layers) do
    baseline = Enum.map(points, fn {x, _} -> {x, 0.0} end)
    {layers, baseline}
  end

  # "Nice number" Heckbert algorithm — finds round numbers for axis ticks.
  defp nice_number(0, _round?), do: 1.0

  defp nice_number(x, round?) do
    expv = :math.floor(:math.log10(x))
    f = x / :math.pow(10, expv)

    nf =
      if round? do
        cond do
          f < 1.5 -> 1.0
          f < 3.0 -> 2.0
          f < 7.0 -> 5.0
          true -> 10.0
        end
      else
        cond do
          f <= 1.0 -> 1.0
          f <= 2.0 -> 2.0
          f <= 5.0 -> 5.0
          true -> 10.0
        end
      end

    nf * :math.pow(10, expv)
  end
end
