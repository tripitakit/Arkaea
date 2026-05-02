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
        <.link
          href={~p"/world"}
          class={nav_class(@active == :world)}
          aria-current={if @active == :world, do: "page", else: false}
        >
          World
        </.link>
        <.link
          href={~p"/seed-lab"}
          class={nav_class(@active == :seed_lab)}
          aria-current={if @active == :seed_lab, do: "page", else: false}
        >
          Seed lab
        </.link>

        <span
          :if={@active == :biotope}
          class={nav_class(true)}
          aria-current="page"
          style="font-size: var(--text-sm);"
        >
          {@biotope_label || "Biotope"}
        </span>
      </div>

      <div :if={@player_name} class="dropdown dropdown-end">
        <div
          tabindex="0"
          role="button"
          class="game-nav__operator"
          style="cursor: pointer; display: inline-flex; align-items: center; gap: 0.4rem;"
        >
          <span>{@player_name}</span>
          <span class="hero-chevron-down w-3 h-3" style="color: var(--sim-muted);"></span>
        </div>
        <ul
          tabindex="0"
          class="dropdown-content menu menu-sm"
          style="z-index: 100; background: var(--sim-panel); border: 1px solid var(--sim-panel-border); border-radius: 0.75rem; padding: 0.5rem; min-width: 10rem; margin-top: 0.25rem; box-shadow: 0 8px 24px rgba(2,6,23,0.3);"
        >
          <li>
            <.link
              href={~p"/players/log-out"}
              style="color: var(--sim-muted); font-size: var(--text-sm); padding: 0.5rem 0.75rem; border-radius: 0.5rem;"
            >
              <span class="hero-arrow-right-on-rectangle w-4 h-4"></span>
              Log out
            </.link>
          </li>
        </ul>
      </div>
    </nav>
    """
  end

  defp nav_class(true), do: "game-nav__link game-nav__link--active"
  defp nav_class(false), do: "game-nav__link"
end
