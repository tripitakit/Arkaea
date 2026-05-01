defmodule ArkeaWeb.GameChrome do
  use ArkeaWeb, :html

  attr :active, :atom, required: true
  attr :player_name, :string, default: nil
  attr :biotope_label, :string, default: nil

  def top_nav(assigns) do
    ~H"""
    <nav class="game-nav">
      <div class="game-nav__brand">
        <span class="game-nav__brand-mark"></span>
        <span>Arkea</span>
      </div>

      <div class="game-nav__links">
        <.link href={~p"/world"} class={nav_class(@active == :world)}>
          World
        </.link>
        <.link href={~p"/seed-lab"} class={nav_class(@active == :seed_lab)}>
          Seed lab
        </.link>

        <span :if={@active == :biotope} class={nav_class(true)}>
          {@biotope_label || "Biotope view"}
        </span>
      </div>

      <div :if={@player_name} class="game-nav__operator">
        Operator <span>{@player_name}</span>
      </div>
    </nav>
    """
  end

  defp nav_class(true), do: "game-nav__link game-nav__link--active"
  defp nav_class(false), do: "game-nav__link"
end
