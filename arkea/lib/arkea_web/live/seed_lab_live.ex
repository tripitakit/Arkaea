defmodule ArkeaWeb.SeedLabLive do
  @moduledoc """
  Phenotype-first seed builder for the prototype player.
  """

  use ArkeaWeb, :live_view

  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Game.PrototypePlayer
  alias Arkea.Game.SeedLab
  alias ArkeaWeb.GameChrome

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       player: PrototypePlayer.profile(),
       starter_ecotypes: SeedLab.starter_ecotypes(),
       metabolism_profiles: SeedLab.metabolism_profiles(),
       membrane_profiles: SeedLab.membrane_profiles(),
       regulation_profiles: SeedLab.regulation_profiles(),
       mobile_modules: SeedLab.mobile_modules(),
       errors: %{},
       page_title: "Arkea Seed Lab"
     )
     |> apply_form(SeedLab.form_defaults())}
  end

  @impl Phoenix.LiveView
  def handle_event("change_seed", %{"seed" => params}, socket) do
    {:noreply,
     socket
     |> assign(errors: %{})
     |> maybe_apply_seed_form(params)}
  end

  def handle_event("provision_seed", %{"seed" => params}, socket) do
    if socket.assigns.seed_locked? do
      {:noreply,
       socket
       |> assign(
         errors: %{starter_archetype: "This Arkeon seed is already committed to a home biotope."}
       )
       |> apply_form(%{})}
    else
      case SeedLab.provision_home(params) do
        {:ok, biotope_id} ->
          {:noreply, push_navigate(socket, to: ~p"/biotopes/#{biotope_id}")}

        {:error, errors} ->
          {:noreply, socket |> assign(errors: errors) |> apply_form(params)}
      end
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="sim-shell" data-view="seed-lab">
      <div class="sim-shell__aurora sim-shell__aurora--west"></div>
      <div class="sim-shell__aurora sim-shell__aurora--east"></div>
      <div class="sim-shell__grid"></div>
      <div class="sim-shell__content">
        <GameChrome.top_nav active={:seed_lab} player_name={@player.display_name} />

        <section class="sim-hero seed-hero mt-6">
          <div>
            <div class="sim-hero__eyebrow">Arkea prototype · onboarding shell</div>
            <h1 class="sim-hero__title">Seed lab</h1>
            <p class="sim-hero__copy">
              Build an initial Arkeon seed from phenotype-level choices and inspect the derived genome scaffold before provisioning a home biotope.
            </p>
          </div>

          <div class="sim-stat-strip">
            <.stat_chip label="starter tier" value="3 ecotypes" tone="gold" />
            <.stat_chip label="genes" value={@preview.gene_count} tone="teal" />
            <.stat_chip label="plasmids" value={@preview.plasmid_count} tone="sky" />
            <.stat_chip label="prophages" value={@preview.prophage_count} tone="amber" />
            <.stat_chip label="playstyle" value={@preview.playstyle} tone="slate" />
          </div>
        </section>

        <div class="sim-main-grid mt-6">
          <section class="sim-card seed-form-card">
            <div class="sim-card__header">
              <div>
                <div class="sim-card__eyebrow">Builder</div>
                <h2 class="sim-card__title">Phenotype + genome engineering</h2>
              </div>
              <div class="sim-card__meta">
                <%= if @can_provision_home? do %>
                  home slot open
                <% else %>
                  seed locked after colonization
                <% end %>
              </div>
            </div>

            <%= if @seed_locked? do %>
              <div class="seed-lock-banner">
                <div>
                  <div class="seed-lock-banner__title">Arkeon seed locked</div>
                  <div class="seed-lock-banner__copy">
                    This phenotype/genome configuration is already bound to the first colonized home biotope and can no longer be edited.
                  </div>
                </div>

                <.link
                  :if={@home_biotope_id}
                  href={~p"/biotopes/#{@home_biotope_id}"}
                  class="sim-action-button"
                >
                  Open home viewport
                </.link>
              </div>
            <% end %>

            <form phx-change="change_seed" phx-submit="provision_seed" class="seed-form">
              <fieldset disabled={@seed_locked?} class="seed-form__fieldset">
                <div class="seed-field">
                  <label class="seed-field__label" for="seed_name">Seed name</label>
                  <input
                    id="seed_name"
                    name="seed[seed_name]"
                    type="text"
                    value={@form[:seed_name].value}
                    class="seed-input"
                    maxlength="40"
                  />
                  <p :if={Map.has_key?(@errors, :seed_name)} class="seed-field__error">
                    {@errors.seed_name}
                  </p>
                </div>

                <div class="seed-field">
                  <div class="seed-field__label">Starter ecotype</div>
                  <div class="seed-choice-grid">
                    <label
                      :for={ecotype <- @starter_ecotypes}
                      class={[
                        "seed-choice",
                        @form[:starter_archetype].value == ecotype.id && "seed-choice--active",
                        @seed_locked? && "seed-choice--locked"
                      ]}
                    >
                      <input
                        type="radio"
                        name="seed[starter_archetype]"
                        value={ecotype.id}
                        checked={@form[:starter_archetype].value == ecotype.id}
                      />
                      <span class="seed-choice__title">{ecotype.label}</span>
                      <span class="seed-choice__copy">{ecotype.strapline}</span>
                    </label>
                  </div>
                  <p :if={Map.has_key?(@errors, :starter_archetype)} class="seed-field__error">
                    {@errors.starter_archetype}
                  </p>
                </div>

                <div class="seed-config-grid">
                  <.option_select
                    field="metabolism_profile"
                    label="Metabolic cassette"
                    value={@form[:metabolism_profile].value}
                    options={@metabolism_profiles}
                  />
                  <.option_select
                    field="membrane_profile"
                    label="Envelope profile"
                    value={@form[:membrane_profile].value}
                    options={@membrane_profiles}
                  />
                  <.option_select
                    field="regulation_profile"
                    label="Regulation mode"
                    value={@form[:regulation_profile].value}
                    options={@regulation_profiles}
                  />
                  <.option_select
                    field="mobile_module"
                    label="Mobile module"
                    value={@form[:mobile_module].value}
                    options={@mobile_modules}
                  />
                </div>
              </fieldset>

              <div class="seed-submit-row">
                <button
                  type="submit"
                  class="sim-action-button seed-submit"
                  disabled={!@can_provision_home?}
                >
                  Provision home biotope
                </button>
                <p class="sim-muted">
                  <%= if @seed_locked? do %>
                    The committed seed stays readable here, but its phenotype and genome options are frozen after first colonization.
                  <% else %>
                    Provisioning starts a player-owned runtime biotope and redirects straight into the detailed viewport.
                  <% end %>
                </p>
              </div>
            </form>
          </section>

          <div class="sim-sidebar">
            <section class="sim-card">
              <div class="sim-card__header">
                <div>
                  <div class="sim-card__eyebrow">Morphology</div>
                  <h2 class="sim-card__title">Arkeon phenotype portrait</h2>
                </div>
                <div class="sim-card__meta">
                  <%= if @seed_locked? do %>
                    committed
                  <% else %>
                    live preview
                  <% end %>
                </div>
              </div>

              <.arkeon_portrait preview={@preview} seed_locked?={@seed_locked?} />
            </section>

            <section class="sim-card">
              <div class="sim-card__header">
                <div>
                  <div class="sim-card__eyebrow">Preview</div>
                  <h2 class="sim-card__title">{@preview.spec.seed_name}</h2>
                </div>
                <div class="sim-card__meta">{@preview.ecotype.label}</div>
              </div>

              <div class="sim-phase-kpis">
                <div class="sim-mini-stat">
                  <span class="sim-mini-stat__label">growth</span>
                  <span class="sim-mini-stat__value">
                    {format_float(@preview.phenotype.base_growth_rate, 2)}
                  </span>
                </div>
                <div class="sim-mini-stat">
                  <span class="sim-mini-stat__label">repair</span>
                  <span class="sim-mini-stat__value">
                    {format_float(@preview.phenotype.repair_efficiency, 2)}
                  </span>
                </div>
                <div class="sim-mini-stat">
                  <span class="sim-mini-stat__label">ATP cost</span>
                  <span class="sim-mini-stat__value">
                    {format_float(@preview.phenotype.energy_cost, 2)}
                  </span>
                </div>
                <div class="sim-mini-stat">
                  <span class="sim-mini-stat__label">TM anchors</span>
                  <span class="sim-mini-stat__value">{@preview.phenotype.n_transmembrane}</span>
                </div>
              </div>

              <div class="seed-preview-copy">
                <div class="world-mini-list__title">{@preview.playstyle}</div>
                <div class="world-mini-list__copy">
                  Spawn zone {zone_label(@preview.ecotype.zone)} · phases {Enum.map_join(
                    @preview.phase_names,
                    ", ",
                    &phase_label/1
                  )}
                </div>
              </div>
            </section>

            <section class="sim-card">
              <div class="sim-card__header">
                <div>
                  <div class="sim-card__eyebrow">Genome preview</div>
                  <h2 class="sim-card__title">Chromosome atlas</h2>
                </div>
                <div class="sim-card__meta">{@preview.gene_count} genes total</div>
              </div>

              <.genome_atlas preview={@preview} />
            </section>

            <section class="sim-card">
              <div class="sim-card__header">
                <div>
                  <div class="sim-card__eyebrow">Cassette manifest</div>
                  <h2 class="sim-card__title">Domain inventory</h2>
                </div>
                <div class="sim-card__meta">{length(@preview.modules)} replicon views</div>
              </div>

              <div class="world-mini-list">
                <div :for={entry <- @preview.modules} class="world-mini-list__item">
                  <div class="world-mini-list__title">{entry.scope} · {entry.label}</div>
                  <div class="world-mini-list__copy">{Enum.join(entry.domains, " · ")}</div>
                </div>
              </div>
            </section>

            <section class="sim-card">
              <div class="sim-card__header">
                <div>
                  <div class="sim-card__eyebrow">World insertion</div>
                  <h2 class="sim-card__title">Home placement</h2>
                </div>
                <div class="sim-card__meta">{@preview.phase_count} phases</div>
              </div>

              <div class="sim-topology-grid">
                <.env_reading
                  label="coords"
                  value={format_float(elem(@preview.spawn_coords, 0), 1) <> ", " <> format_float(elem(@preview.spawn_coords, 1), 1)}
                />
                <.env_reading label="neighbors" value={length(@preview.neighbor_ids)} />
              </div>

              <div>
                <div class="sim-card__eyebrow mb-2">Outgoing arcs</div>
                <%= if @preview.neighbor_ids == [] do %>
                  <p class="sim-muted">
                    No active biotopes detected yet. This home will start as an isolated prototype node.
                  </p>
                <% else %>
                  <div class="sim-token-cloud">
                    <span
                      :for={neighbor_id <- @preview.neighbor_ids}
                      class="sim-token sim-token--ghost"
                    >
                      {String.slice(neighbor_id, 0, 8)}
                    </span>
                  </div>
                <% end %>
              </div>
            </section>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :field, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :options, :list, required: true

  defp option_select(assigns) do
    ~H"""
    <div class="seed-field">
      <label class="seed-field__label" for={@field}>{@label}</label>
      <select id={@field} name={"seed[#{@field}]"} class="seed-input">
        <option :for={option <- @options} value={option.id} selected={@value == option.id}>
          {option.label}
        </option>
      </select>
      <p class="seed-field__hint">
        {selected_description(@options, @value)}
      </p>
    </div>
    """
  end

  attr :preview, :map, required: true
  attr :seed_locked?, :boolean, required: true

  defp arkeon_portrait(assigns) do
    antenna_count = max(assigns.preview.phenotype.n_transmembrane, 1)

    assigns =
      assign(assigns,
        antenna_slots: Enum.to_list(1..antenna_count),
        shell_class: shell_class(assigns.preview.spec.membrane_profile),
        core_class: core_class(assigns.preview.spec.metabolism_profile),
        pulse_class: pulse_class(assigns.preview.spec.regulation_profile),
        accessory_class: accessory_class(assigns.preview.spec.mobile_module),
        membrane_copy: membrane_copy(assigns.preview.spec.membrane_profile),
        metabolism_copy: metabolism_copy(assigns.preview.spec.metabolism_profile),
        regulation_copy: regulation_copy(assigns.preview.spec.regulation_profile),
        accessory_copy: accessory_copy(assigns.preview.spec.mobile_module)
      )

    ~H"""
    <div class="seed-portrait">
      <div class={["seed-portrait__glyph", @shell_class, @core_class, @pulse_class, @accessory_class]}>
        <span
          :for={slot <- @antenna_slots}
          class="seed-portrait__antenna"
          style={"--slot: #{slot}; --slots: #{length(@antenna_slots)};"}
        >
        </span>
        <span class="seed-portrait__ring seed-portrait__ring--outer"></span>
        <span class="seed-portrait__ring seed-portrait__ring--mid"></span>
        <span class="seed-portrait__core"></span>
        <span class="seed-portrait__accessory"></span>
      </div>

      <div class="seed-portrait__legend">
        <div class="seed-portrait__legend-item">
          <span class="seed-portrait__legend-label">Envelope</span>
          <span class="seed-portrait__legend-copy">{@membrane_copy}</span>
        </div>
        <div class="seed-portrait__legend-item">
          <span class="seed-portrait__legend-label">Metabolism</span>
          <span class="seed-portrait__legend-copy">{@metabolism_copy}</span>
        </div>
        <div class="seed-portrait__legend-item">
          <span class="seed-portrait__legend-label">Regulation</span>
          <span class="seed-portrait__legend-copy">{@regulation_copy}</span>
        </div>
        <div class="seed-portrait__legend-item">
          <span class="seed-portrait__legend-label">Accessory</span>
          <span class="seed-portrait__legend-copy">{@accessory_copy}</span>
        </div>
      </div>

      <p class="sim-muted">
        This portrait is a gameplay-facing abstraction derived from the current phenotype choices. It is not a cell renderer, but it makes envelope, metabolism, regulation, and accessory modules visually legible.
      </p>
    </div>
    """
  end

  attr :preview, :map, required: true

  defp genome_atlas(assigns) do
    chromosome = %{label: "Chromosome", tone: "core", genes: assigns.preview.genome.chromosome}

    plasmids =
      assigns.preview.genome.plasmids
      |> Enum.with_index(1)
      |> Enum.map(fn {genes, index} ->
        %{label: "Plasmid #{index}", tone: "plasmid", genes: genes}
      end)

    prophages =
      assigns.preview.genome.prophages
      |> Enum.with_index(1)
      |> Enum.map(fn {genes, index} ->
        %{label: "Prophage #{index}", tone: "prophage", genes: genes}
      end)

    assigns = assign(assigns, replicons: [chromosome | plasmids ++ prophages])

    ~H"""
    <div class="seed-atlas">
      <.replicon_track :for={replicon <- @replicons} replicon={replicon} />

      <div class="seed-domain-legend">
        <span :for={entry <- domain_legend()} class="seed-domain-legend__item">
          <span class={["seed-domain-legend__swatch", "seed-domain-legend__swatch--#{entry.tone}"]}>
          </span>
          <span>{entry.label}</span>
        </span>
      </div>

      <p class="sim-muted">
        This read-only atlas is the foundation for the future advanced editor: chromosome and mobile cassettes are already separated as distinct visual tracks.
      </p>
    </div>
    """
  end

  attr :replicon, :map, required: true

  defp replicon_track(assigns) do
    gene_views =
      assigns.replicon.genes
      |> Enum.with_index(1)
      |> Enum.map(fn {gene, index} ->
        %{
          index: index,
          codon_count: length(gene.codons),
          domain_count: length(gene.domains),
          domains: domain_views(gene)
        }
      end)

    assigns = assign(assigns, gene_views: gene_views)

    ~H"""
    <div class="seed-replicon">
      <div class="seed-replicon__header">
        <span class={["seed-replicon__tone", "seed-replicon__tone--#{@replicon.tone}"]}></span>
        <span class="seed-replicon__title">{@replicon.label}</span>
        <span class="seed-replicon__meta">{length(@replicon.genes)} genes</span>
      </div>

      <div class="seed-replicon__genes">
        <div :for={gene <- @gene_views} class="seed-gene">
          <div class="seed-gene__bar">
            <span
              :for={domain <- gene.domains}
              class={["seed-domain", "seed-domain--#{domain.tone}"]}
              style={"flex: #{domain.flex};"}
              title={domain.label}
            >
            </span>
          </div>
          <div class="seed-gene__meta">
            G{gene.index} · {gene.domain_count} domains · {gene.codon_count} codons
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp env_reading(assigns) do
    ~H"""
    <div class="sim-env-reading">
      <span class="sim-env-reading__label">{@label}</span>
      <span class="sim-env-reading__value">{@value}</span>
    </div>
    """
  end

  defp stat_chip(assigns) do
    ~H"""
    <div class={["sim-stat-chip", "sim-stat-chip--#{@tone}"]}>
      <span class="sim-stat-chip__label">{@label}</span>
      <span class="sim-stat-chip__value">{@value}</span>
    </div>
    """
  end

  defp maybe_apply_seed_form(socket, params) do
    if socket.assigns.seed_locked? do
      apply_form(socket, %{})
    else
      apply_form(socket, params)
    end
  end

  defp apply_form(socket, params) do
    case SeedLab.locked_seed() do
      %{params: locked_params, preview: preview, biotope_id: biotope_id} ->
        assign(socket,
          form: to_form(locked_params, as: :seed),
          preview: preview,
          can_provision_home?: false,
          seed_locked?: true,
          home_biotope_id: biotope_id
        )

      nil ->
        merged = Map.merge(SeedLab.form_defaults(), Map.new(params))

        assign(socket,
          form: to_form(merged, as: :seed),
          preview: SeedLab.preview(merged),
          can_provision_home?: SeedLab.can_provision_home?(),
          seed_locked?: false,
          home_biotope_id: nil
        )
    end
  end

  defp selected_description(options, selected_id) do
    options
    |> Enum.find(&(&1.id == selected_id))
    |> case do
      nil -> ""
      option -> option.description
    end
  end

  defp phase_label(phase_name) when is_atom(phase_name) do
    phase_name
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp zone_label(zone) when is_atom(zone) do
    zone
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp format_float(value, decimals) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: decimals)

  defp format_float(value, _decimals) when is_integer(value), do: to_string(value)

  defp shell_class("porous"), do: "seed-portrait__glyph--porous"
  defp shell_class("fortified"), do: "seed-portrait__glyph--fortified"
  defp shell_class("salinity_tuned"), do: "seed-portrait__glyph--salinity"

  defp core_class("thrifty"), do: "seed-portrait__glyph--thrifty"
  defp core_class("balanced"), do: "seed-portrait__glyph--balanced"
  defp core_class("bloom"), do: "seed-portrait__glyph--bloom"

  defp pulse_class("steady"), do: "seed-portrait__glyph--steady"
  defp pulse_class("responsive"), do: "seed-portrait__glyph--responsive"
  defp pulse_class("mutator"), do: "seed-portrait__glyph--mutator"

  defp accessory_class("none"), do: "seed-portrait__glyph--no-accessory"
  defp accessory_class("conjugative_plasmid"), do: "seed-portrait__glyph--plasmid"
  defp accessory_class("latent_prophage"), do: "seed-portrait__glyph--prophage"

  defp membrane_copy("porous"), do: "Light shell, lower structural cost."
  defp membrane_copy("fortified"), do: "Thicker wall, higher upkeep, sturdier shell."
  defp membrane_copy("salinity_tuned"), do: "Membrane bias toward osmotic tolerance."

  defp metabolism_copy("thrifty"), do: "Slow, efficient uptake in lean environments."
  defp metabolism_copy("balanced"), do: "Mixed-phase generalist throughput."
  defp metabolism_copy("bloom"), do: "Aggressive core tuned for nutrient surges."

  defp regulation_copy("steady"), do: "Low-noise expression and repair discipline."
  defp regulation_copy("responsive"), do: "Signal-coupled switching and sensing."
  defp regulation_copy("mutator"), do: "Looser repair for exploratory variation."

  defp accessory_copy("none"), do: "No mobile cassette attached."
  defp accessory_copy("conjugative_plasmid"), do: "Mobile plasmid carried as a detachable ring."
  defp accessory_copy("latent_prophage"), do: "Dormant prophage cassette embedded in the seed."

  defp domain_views(%Gene{} = gene) do
    Enum.map(gene.domains, fn domain ->
      %{
        label: domain_label(domain.type),
        tone: domain_tone(domain.type),
        flex: Domain.codon_length(domain)
      }
    end)
  end

  defp domain_tone(:substrate_binding), do: "binding"
  defp domain_tone(:catalytic_site), do: "catalytic"
  defp domain_tone(:energy_coupling), do: "energy"
  defp domain_tone(:transmembrane_anchor), do: "membrane"
  defp domain_tone(:dna_binding), do: "regulation"
  defp domain_tone(:ligand_sensor), do: "sensor"
  defp domain_tone(:repair_fidelity), do: "repair"
  defp domain_tone(:structural_fold), do: "structure"
  defp domain_tone(_type), do: "other"

  defp domain_legend do
    [
      %{label: "Binding", tone: "binding"},
      %{label: "Catalysis", tone: "catalytic"},
      %{label: "Energy", tone: "energy"},
      %{label: "Membrane", tone: "membrane"},
      %{label: "Regulation", tone: "regulation"},
      %{label: "Sensor", tone: "sensor"},
      %{label: "Repair", tone: "repair"},
      %{label: "Structure", tone: "structure"},
      %{label: "Other", tone: "other"}
    ]
  end

  defp domain_label(type) when is_atom(type) do
    type
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
