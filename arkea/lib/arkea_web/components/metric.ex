defmodule ArkeaWeb.Components.Metric do
  @moduledoc """
  Compact telemetry primitives (UI rewrite — phase U0).

    * `<.metric_strip>` — horizontal collection of chips
    * `<.metric_chip>` — label/value chip with optional tone
    * `<.metric_bar>` — labelled horizontal bar (0..max), used for phenotype
      trait readouts in the Seed Lab and Biotope drawer

  Replaces the duplicated `stat_chip/1` definitions previously embedded in
  `WorldLive` and `SeedLabLive`.
  """
  use Phoenix.Component

  @tones ~w(gold teal sky rust growth stress signal metabolite muted)

  attr :class, :string, default: nil
  slot :inner_block, required: true

  def metric_strip(assigns) do
    ~H"""
    <div class={["arkea-metric-strip", @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :tone, :string, default: nil, values: [nil] ++ @tones
  attr :class, :string, default: nil

  def metric_chip(assigns) do
    ~H"""
    <div class={[
      "arkea-metric-chip",
      @tone && "arkea-metric-chip--#{@tone}",
      @class
    ]}>
      <span class="arkea-metric-chip__label">{@label}</span>
      <span class="arkea-metric-chip__value">{@value}</span>
    </div>
    """
  end

  @doc """
  Labelled horizontal bar.

  `value` is clamped to `[0, max]`. `format` controls the displayed numeric
  form (default: 2 significant digits).
  """
  attr :label, :string, required: true
  attr :value, :any, required: true, doc: "numeric value (int or float)"
  attr :max, :any, default: 1.0, doc: "numeric max (int or float)"
  attr :tone, :string, default: "metabolite", values: @tones
  attr :format, :atom, default: :decimal, values: [:decimal, :percent, :integer]
  attr :class, :string, default: nil

  def metric_bar(assigns) do
    value = to_float(assigns.value)
    max = to_float(assigns.max)
    pct = clamp_percent(value, max)
    formatted = format_value(value, assigns.format)

    assigns =
      assign(assigns,
        value_f: value,
        max_f: max,
        percent: pct,
        formatted: formatted
      )

    ~H"""
    <div class={["arkea-metric-bar", "arkea-metric-bar--#{@tone}", @class]}>
      <span class="arkea-metric-bar__label">{@label}</span>
      <span class="arkea-metric-bar__value">{@formatted}</span>
      <div
        class="arkea-metric-bar__track"
        role="meter"
        aria-label={@label}
        aria-valuenow={:io_lib.format("~.4f", [@value_f]) |> IO.iodata_to_binary()}
        aria-valuemin="0"
        aria-valuemax={:io_lib.format("~.4f", [@max_f]) |> IO.iodata_to_binary()}
      >
        <div class="arkea-metric-bar__fill" style={"width: #{@percent}%"}></div>
      </div>
    </div>
    """
  end

  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v * 1.0

  defp clamp_percent(_value, max) when max <= 0, do: 0
  defp clamp_percent(value, _max) when value <= 0, do: 0

  defp clamp_percent(value, max) do
    pct = value / max * 100
    pct |> min(100.0) |> max(0.0) |> Float.round(1)
  end

  defp format_value(value, :integer), do: Integer.to_string(round(value))

  defp format_value(value, :percent) do
    rounded = (value * 100) |> Float.round(1)
    "#{rounded}%"
  end

  defp format_value(value, :decimal) do
    cond do
      value == 0 -> "0"
      abs(value) >= 100 -> Integer.to_string(round(value))
      abs(value) >= 10 -> :io_lib.format("~.1f", [value]) |> IO.iodata_to_binary()
      true -> :io_lib.format("~.2f", [value]) |> IO.iodata_to_binary()
    end
  end
end
