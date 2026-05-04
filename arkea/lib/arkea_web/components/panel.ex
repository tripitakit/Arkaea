defmodule ArkeaWeb.Components.Panel do
  @moduledoc """
  Card-style container used throughout the Arkea UI rewrite (phase U0).

  A `<.panel>` is a bordered surface with an optional header/footer and a
  body that can opt-in to internal scrolling. Panels never grow scrollbars
  on the page itself; `scroll: true` makes the body scrollable inside its
  fixed allotment.

  ## Examples

      <.panel>
        <:header eyebrow="World" title="Biotope network" meta="6 active" />
        <:body scroll>...</:body>
      </.panel>
  """
  use Phoenix.Component

  attr :class, :string, default: nil
  attr :flush, :boolean, default: false, doc: "drop border/background (transparent panel)"
  attr :rest, :global

  slot :header do
    attr :eyebrow, :string
    attr :title, :string
    attr :meta, :string
  end

  slot :body do
    attr :scroll, :boolean
    attr :flush, :boolean
  end

  slot :footer

  slot :inner_block,
    doc: """
    Free-form content. If neither :body nor :inner_block is provided, the panel
    renders empty. When both are provided, :body wins.
    """

  def panel(assigns) do
    ~H"""
    <section
      class={[
        "arkea-panel",
        @flush && "arkea-panel--flush",
        @class
      ]}
      {@rest}
    >
      <header :for={h <- @header} class="arkea-panel__header">
        <div class="arkea-panel__heading">
          <span :if={h[:eyebrow]} class="arkea-panel__eyebrow">{h[:eyebrow]}</span>
          <h2 :if={h[:title]} class="arkea-panel__title">{h[:title]}</h2>
        </div>
        <span :if={h[:meta]} class="arkea-panel__meta">{h[:meta]}</span>
      </header>

      <div
        :for={b <- @body}
        class={[
          "arkea-panel__body",
          b[:scroll] && "arkea-panel__body--scroll",
          b[:flush] && "arkea-panel__body--flush"
        ]}
      >
        {render_slot(b)}
      </div>

      <div :if={@body == [] and @inner_block != []} class="arkea-panel__body">
        {render_slot(@inner_block)}
      </div>

      <footer :for={f <- @footer} class="arkea-panel__footer">
        {render_slot(f)}
      </footer>
    </section>
    """
  end

  @doc """
  Empty-state placeholder, intended to live inside a panel body.
  """
  attr :title, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block

  def empty_state(assigns) do
    ~H"""
    <div class={["arkea-empty", @class]}>
      <span :if={@title} class="arkea-empty__title">{@title}</span>
      <span :if={@inner_block != []}>{render_slot(@inner_block)}</span>
    </div>
    """
  end
end
