defmodule ArkeaWeb.Components.Shell do
  @moduledoc """
  Top-level layout primitive for the Arkea UI rewrite (phase U0).

  A `<.shell>` fills the viewport (100dvh) and locks global scroll. It is
  composed of a header (48px), an optional sidebar (240px) and a main area;
  scrolling only happens inside opt-in sub-panels (`.arkea-scrollable` or
  `<.panel_body scroll>`).

  Slots are kept minimal so each LiveView can drive its own header/nav and
  sidebar content without inheriting decisions from this module.
  """
  use Phoenix.Component

  attr :sidebar?, :boolean, default: false, doc: "render sidebar grid column"
  attr :class, :string, default: nil
  attr :rest, :global

  slot :header, doc: "top bar content (left aligned)"
  slot :sidebar, doc: "sidebar content; ignored unless sidebar?: true"
  slot :inner_block, required: true, doc: "main view content"

  def shell(assigns) do
    ~H"""
    <div
      class={[
        "arkea-shell",
        @sidebar? && "arkea-shell--with-sidebar",
        @class
      ]}
      {@rest}
    >
      <header :if={@header != []} class="arkea-shell__header">
        {render_slot(@header)}
      </header>

      <div class="arkea-shell__body">
        <aside :if={@sidebar?} class="arkea-shell__sidebar">
          {render_slot(@sidebar)}
        </aside>

        <main class="arkea-shell__main">
          {render_slot(@inner_block)}
        </main>
      </div>
    </div>
    """
  end

  attr :class, :string, default: nil
  slot :inner_block, required: true

  def shell_brand(assigns) do
    ~H"""
    <div class={["arkea-shell__brand", @class]}>
      <span class="arkea-shell__brand-dot" aria-hidden="true"></span>
      <span>{render_slot(@inner_block)}</span>
    </div>
    """
  end

  attr :items, :list,
    required: true,
    doc: ~s"""
    list of {label, href, active?} tuples or maps with :label/:href/:active keys
    """

  def shell_nav(assigns) do
    assigns = assign(assigns, :items, normalize_nav_items(assigns.items))

    ~H"""
    <nav class="arkea-shell__nav" aria-label="Primary">
      <a
        :for={item <- @items}
        class="arkea-shell__nav-link"
        href={item.href}
        aria-current={if item.active, do: "page", else: nil}
      >
        {item.label}
      </a>
    </nav>
    """
  end

  attr :name, :string, default: nil
  attr :logout_href, :string, default: nil

  def shell_user(assigns) do
    ~H"""
    <div class="arkea-shell__user">
      <span :if={@name} class="arkea-shell__user-name">{@name}</span>
      <a :if={@logout_href} class="arkea-shell__user-action" href={@logout_href}>
        Log out
      </a>
    </div>
    """
  end

  defp normalize_nav_items(items) do
    Enum.map(items, fn
      %{label: l, href: h} = m -> %{label: l, href: h, active: Map.get(m, :active, false)}
      {label, href, active} -> %{label: label, href: href, active: active}
      {label, href} -> %{label: label, href: href, active: false}
    end)
  end
end
