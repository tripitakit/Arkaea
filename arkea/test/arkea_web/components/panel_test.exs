defmodule ArkeaWeb.Components.PanelTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias ArkeaWeb.Components.Panel

  test "panel/1 renders a body using inner_block when no :body slot is given" do
    assigns = %{}
    html = rendered_to_string(~H"<Panel.panel>PLAIN</Panel.panel>")

    assert html =~ "arkea-panel"
    assert html =~ "arkea-panel__body"
    assert html =~ "PLAIN"
    refute html =~ "arkea-panel__body--scroll"
  end

  test "panel/1 :body slot can opt-in to scroll" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Panel.panel>
        <:body scroll>SCROLLED</:body>
      </Panel.panel>
      """)

    assert html =~ "arkea-panel__body--scroll"
    assert html =~ "SCROLLED"
  end

  test "panel/1 renders header with eyebrow, title, meta" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Panel.panel>
        <:header eyebrow="World" title="Biotope network" meta="6 active" />
        body
      </Panel.panel>
      """)

    assert html =~ "arkea-panel__header"
    assert html =~ "World"
    assert html =~ "Biotope network"
    assert html =~ "6 active"
  end

  test "panel/1 with flush: true drops the surface" do
    assigns = %{}
    html = rendered_to_string(~H|<Panel.panel flush>x</Panel.panel>|)
    assert html =~ "arkea-panel--flush"
  end

  test "empty_state/1 renders title and message" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Panel.empty_state title="No biotopes yet">
        Provision one to start.
      </Panel.empty_state>
      """)

    assert html =~ "arkea-empty"
    assert html =~ "No biotopes yet"
    assert html =~ "Provision one to start."
  end
end
