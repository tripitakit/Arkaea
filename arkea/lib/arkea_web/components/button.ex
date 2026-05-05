defmodule ArkeaWeb.Components.Button do
  @moduledoc """
  Unified button component for the Arkea UI restyle.

  Replaces the heterogeneous mix of `.arkea-action-button`, `.arkea-button`,
  raw `<button>` and daisyUI `.btn` markup that grew across the app. One
  variant scale (`primary | secondary | ghost | danger`) and two sizes
  (`sm | md`) are intended to cover every interactive button in the app.

  Visual + interaction conventions:

    * Hover/active/focus-visible/disabled/loading states are all visible by
      contract — the `:focus-visible` outline is required for keyboard a11y.
    * `loading={true}` shows an inline spinner, sets `aria-busy="true"`
      and disables interaction.
    * If the button has a `phx-click` and the consumer did not pass an
      explicit `phx-disable-with`, a default ellipsis is injected so the
      button gets feedback during the LiveView round-trip.
    * `icon` accepts a Heroicon name (without the `hero-` prefix) and is
      rendered before the label.
    * `icon_only={true}` visually hides the label (kept available to screen
      readers); the slot text is still required for accessible naming.

  ## Examples

      <.arkea_button phx-click="save">Save</.arkea_button>

      <.arkea_button variant="ghost" size="sm" icon="arrow-path"
                     phx-click="refresh" disable_with="Refreshing…">
        Refresh
      </.arkea_button>

      <.arkea_button variant="ghost" icon="x-mark" icon_only phx-click="close">
        Close
      </.arkea_button>
  """
  use Phoenix.Component

  @variants ~w(primary secondary ghost danger)
  @sizes ~w(sm md)

  attr :variant, :string, default: "secondary", values: @variants
  attr :size, :string, default: "md", values: @sizes
  attr :type, :string, default: "button", values: ~w(button submit reset)
  attr :loading, :boolean, default: false
  attr :icon, :string, default: nil
  attr :icon_only, :boolean, default: false

  attr :disable_with, :string,
    default: nil,
    doc: "Text shown by LiveView while a phx-click is in flight. Defaults to ellipsis."

  attr :navigate, :string, default: nil
  attr :patch, :string, default: nil
  attr :href, :string, default: nil

  attr :class, :string, default: nil

  attr :rest, :global,
    include:
      ~w(disabled name value form autofocus download
         title target rel
         aria-label aria-controls aria-expanded aria-pressed
         phx-click phx-disable-with phx-target phx-value-id
         phx-submit phx-change phx-confirm)

  slot :inner_block, required: true

  def arkea_button(assigns) do
    assigns =
      assigns
      |> assign(:rest, finalize_rest(assigns))
      |> assign(:link?, link?(assigns))
      |> assign(:classes, build_classes(assigns))

    ~H"""
    <%= if @link? do %>
      <.link
        navigate={@navigate}
        patch={@patch}
        href={@href}
        class={@classes}
        aria-busy={(@loading && "true") || nil}
        {@rest}
      >
        <span :if={@loading} class="arkea-button__spinner" aria-hidden="true"></span>
        <span
          :if={@icon && !@loading}
          class={["arkea-button__icon", "hero-#{@icon}"]}
          aria-hidden="true"
        >
        </span>
        <span class={["arkea-button__label", @icon_only && "arkea-sr-only"]}>
          {render_slot(@inner_block)}
        </span>
      </.link>
    <% else %>
      <button
        type={@type}
        class={@classes}
        aria-busy={(@loading && "true") || nil}
        {@rest}
      >
        <span :if={@loading} class="arkea-button__spinner" aria-hidden="true"></span>
        <span
          :if={@icon && !@loading}
          class={["arkea-button__icon", "hero-#{@icon}"]}
          aria-hidden="true"
        >
        </span>
        <span class={["arkea-button__label", @icon_only && "arkea-sr-only"]}>
          {render_slot(@inner_block)}
        </span>
      </button>
    <% end %>
    """
  end

  defp link?(%{navigate: n, patch: p, href: h}),
    do: not is_nil(n) or not is_nil(p) or not is_nil(h)

  defp build_classes(assigns) do
    [
      "arkea-button",
      "arkea-button--#{assigns.variant}",
      "arkea-button--#{assigns.size}",
      assigns.icon_only && "arkea-button--icon-only",
      assigns.loading && "is-loading",
      assigns.class
    ]
  end

  defp finalize_rest(%{rest: rest, loading: loading} = assigns) do
    rest
    |> maybe_inject_disable_with(assigns)
    |> maybe_force_disabled(loading)
  end

  defp maybe_inject_disable_with(rest, assigns) do
    cond do
      not Map.has_key?(rest, :"phx-click") -> rest
      Map.has_key?(rest, :"phx-disable-with") -> rest
      true -> Map.put(rest, :"phx-disable-with", assigns.disable_with || "…")
    end
  end

  defp maybe_force_disabled(rest, true), do: Map.put(rest, :disabled, true)
  defp maybe_force_disabled(rest, false), do: rest
end
