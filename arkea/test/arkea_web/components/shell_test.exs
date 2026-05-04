defmodule ArkeaWeb.Components.ShellTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias ArkeaWeb.Components.Shell

  test "shell/1 renders header and main without sidebar by default" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Shell.shell sidebar?={false}>
        <:header>HEADER</:header>
        MAIN
      </Shell.shell>
      """)

    assert html =~ "arkea-shell"
    refute html =~ "arkea-shell--with-sidebar"
    assert html =~ "arkea-shell__header"
    assert html =~ "HEADER"
    assert html =~ "arkea-shell__main"
    assert html =~ "MAIN"
    refute html =~ "arkea-shell__sidebar"
  end

  test "shell/1 renders sidebar when sidebar?: true" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Shell.shell sidebar?={true}>
        <:sidebar>SIDE</:sidebar>
        MAIN
      </Shell.shell>
      """)

    assert html =~ "arkea-shell--with-sidebar"
    assert html =~ "arkea-shell__sidebar"
    assert html =~ "SIDE"
  end

  test "shell_brand/1 wraps content with brand dot" do
    assigns = %{}
    html = rendered_to_string(~H"<Shell.shell_brand>Arkea</Shell.shell_brand>")

    assert html =~ "arkea-shell__brand"
    assert html =~ "arkea-shell__brand-dot"
    assert html =~ "Arkea"
  end

  test "shell_nav/1 marks active item with aria-current=page" do
    assigns = %{
      items: [
        %{label: "World", href: "/world", active: true},
        %{label: "Seed Lab", href: "/seed-lab", active: false}
      ]
    }

    html = rendered_to_string(~H"<Shell.shell_nav items={@items} />")

    assert html =~ ~s|aria-current="page"|
    assert html =~ "/world"
    assert html =~ "Seed Lab"
  end

  test "shell_nav/1 accepts tuple form" do
    assigns = %{
      items: [{"Dashboard", "/dashboard", false}, {"World", "/world", true}]
    }

    html = rendered_to_string(~H"<Shell.shell_nav items={@items} />")

    assert html =~ "Dashboard"
    assert html =~ "/dashboard"
  end

  test "shell_user/1 renders name and logout link" do
    assigns = %{}

    html =
      rendered_to_string(
        ~H|<Shell.shell_user name="patrick" logout_href="/players/log-out" />|
      )

    assert html =~ "patrick"
    assert html =~ "Log out"
    assert html =~ "/players/log-out"
  end

  test "shell_user/1 renders nothing harmful when name and logout_href are nil" do
    assigns = %{}
    html = rendered_to_string(~H|<Shell.shell_user name={nil} logout_href={nil} />|)
    assert html =~ "arkea-shell__user"
  end
end
