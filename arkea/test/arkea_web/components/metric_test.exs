defmodule ArkeaWeb.Components.MetricTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias ArkeaWeb.Components.Metric

  test "metric_chip/1 renders label and value" do
    assigns = %{}
    html = rendered_to_string(~H|<Metric.metric_chip label="active" value={7} tone="gold" />|)

    assert html =~ "arkea-metric-chip"
    assert html =~ "arkea-metric-chip--gold"
    assert html =~ "active"
    assert html =~ ">7<"
  end

  test "metric_chip/1 omits tone modifier when tone is nil" do
    assigns = %{}
    html = rendered_to_string(~H|<Metric.metric_chip label="tick" value={0} tone={nil} />|)
    refute html =~ "arkea-metric-chip--"
  end

  test "metric_strip/1 wraps inner content" do
    assigns = %{}
    html = rendered_to_string(~H|<Metric.metric_strip>INNER</Metric.metric_strip>|)
    assert html =~ "arkea-metric-strip"
    assert html =~ "INNER"
  end

  test "metric_bar/1 clamps overflowing value to 100% width" do
    assigns = %{}

    html =
      rendered_to_string(
        ~H|<Metric.metric_bar label="growth" value={5.0} max={1.0} tone="growth" />|
      )

    assert html =~ "arkea-metric-bar"
    assert html =~ "arkea-metric-bar--growth"
    assert html =~ "width: 100"
    assert html =~ ~s|role="meter"|
  end

  test "metric_bar/1 renders 0% for non-positive values" do
    assigns = %{}

    html =
      rendered_to_string(
        ~H|<Metric.metric_bar label="stress" value={-1.0} max={1.0} tone="stress" />|
      )

    assert html =~ "width: 0"
  end

  test "metric_bar/1 with format: :percent prints percent string" do
    assigns = %{}

    html =
      rendered_to_string(
        ~H|<Metric.metric_bar label="kcat" value={0.42} max={1.0} format={:percent} tone="metabolite" />|
      )

    assert html =~ "42.0%"
  end

  test "metric_bar/1 accepts integer value/max" do
    assigns = %{}

    html =
      rendered_to_string(
        ~H|<Metric.metric_bar label="events" value={3} max={10} format={:integer} tone="teal" />|
      )

    assert html =~ "arkea-metric-bar"
    assert html =~ "width: 30"
    assert html =~ ">3<"
  end
end
