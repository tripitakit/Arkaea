defmodule ArkeaWeb.SeedLabLive do
  @moduledoc """
  Phenotype-first seed builder for the authenticated player.
  """

  use ArkeaWeb, :live_view

  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Game.SeedLab
  alias Arkea.Views.GenomeCanvas, as: CanvasLayout
  alias Arkea.Views.ArkeonSchematic, as: SchematicLayout
  alias ArkeaWeb.Components.ArkeonSchematic
  alias ArkeaWeb.Components.GenomeCanvas
  alias ArkeaWeb.Components.Metric
  alias ArkeaWeb.Components.Shell

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       player: socket.assigns.current_player,
       starter_ecotypes: SeedLab.starter_ecotypes(),
       metabolism_profiles: SeedLab.metabolism_profiles(),
       membrane_profiles: SeedLab.membrane_profiles(),
       regulation_profiles: SeedLab.regulation_profiles(),
       mobile_modules: SeedLab.mobile_modules(),
       domain_palette: SeedLab.domain_palette(),
       intergenic_palette: SeedLab.intergenic_palette(),
       errors: %{},
       gene_draft: empty_gene_draft(),
       gene_editor_error: nil,
       selected_replicon_id: "chromosome",
       selected_gene_index: 1,
       inspector_expanded: false,
       recolonize_mode?: false,
       page_title: "Arkea Seed Lab"
     )
     |> apply_form(SeedLab.form_defaults())}
  end

  @impl Phoenix.LiveView
  def handle_event("change_seed", %{"seed" => params}, socket) do
    {:noreply,
     socket
     |> assign(errors: %{}, gene_editor_error: nil)
     |> maybe_apply_seed_form(params)}
  end

  def handle_event("append_domain", %{"type" => type_id}, socket) do
    draft = socket.assigns.gene_draft
    draft_domains = Map.get(draft, :domains, [])

    cond do
      socket.assigns.seed_locked? ->
        {:noreply, socket}

      not valid_domain_palette_id?(socket.assigns.domain_palette, type_id) ->
        {:noreply, assign(socket, gene_editor_error: "Unknown functional domain.")}

      length(draft_domains) >= 9 ->
        {:noreply,
         assign(socket,
           gene_editor_error: "A custom gene can carry at most 9 functional domains."
         )}

      true ->
        draft = Map.put(draft, :domains, draft_domains ++ [type_id])
        {:noreply, assign(socket, gene_draft: draft, gene_editor_error: nil)}
    end
  end

  def handle_event("toggle_intergenic", %{"family" => family, "module" => module_id}, socket) do
    if socket.assigns.seed_locked? do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(
         gene_draft:
           toggle_intergenic_module(
             socket.assigns.gene_draft,
             family,
             module_id,
             socket.assigns.intergenic_palette
           ),
         gene_editor_error: nil
       )}
    end
  end

  def handle_event("undo_gene_domain", _params, socket) do
    if socket.assigns.seed_locked? do
      {:noreply, socket}
    else
      draft = socket.assigns.gene_draft
      draft_domains = Map.get(draft, :domains, [])

      {:noreply,
       assign(
         socket,
         gene_draft: Map.put(draft, :domains, Enum.drop(draft_domains, -1)),
         gene_editor_error: nil
       )}
    end
  end

  def handle_event("clear_gene_draft", _params, socket) do
    if socket.assigns.seed_locked? do
      {:noreply, socket}
    else
      {:noreply, assign(socket, gene_draft: empty_gene_draft(), gene_editor_error: nil)}
    end
  end

  def handle_event("commit_custom_gene", _params, socket) do
    if socket.assigns.seed_locked? do
      {:noreply, socket}
    else
      draft = socket.assigns.gene_draft

      case Map.get(draft, :domains, []) do
        [] ->
          {:noreply,
           assign(socket,
             gene_editor_error: "Add at least one functional domain before committing a gene."
           )}

        domains ->
          custom_genes =
            socket.assigns.custom_gene_specs ++
              [
                %{
                  domains: domains,
                  intergenic: Map.get(draft, :intergenic, empty_intergenic_blocks())
                }
              ]

          {:noreply,
           socket
           |> assign(gene_draft: empty_gene_draft(), gene_editor_error: nil)
           |> replace_custom_genes(custom_genes)
           |> focus_chromosome_tail()}
      end
    end
  end

  def handle_event("remove_custom_gene", %{"index" => index}, socket) do
    if socket.assigns.seed_locked? do
      {:noreply, socket}
    else
      idx = parse_positive_index(index)
      custom_genes = List.delete_at(socket.assigns.custom_gene_specs, idx)

      {:noreply,
       socket
       |> assign(gene_editor_error: nil)
       |> replace_custom_genes(custom_genes)}
    end
  end

  def handle_event("focus_gene", %{"replicon" => replicon_id, "gene" => gene_index}, socket) do
    {:noreply,
     assign(socket,
       selected_replicon_id: replicon_id,
       selected_gene_index: String.to_integer(gene_index)
     )}
  end

  def handle_event("select_gene", %{"id" => gene_id}, socket) do
    case locate_gene_by_id(socket.assigns.preview, gene_id) do
      {replicon_id, index} ->
        {:noreply,
         assign(socket,
           selected_replicon_id: replicon_id,
           selected_gene_index: index,
           inspector_expanded: true
         )}

      :not_found ->
        {:noreply, socket}
    end
  end

  def handle_event("move_draft_domain", %{"index" => raw_index, "to" => to}, socket) do
    if socket.assigns.seed_locked? do
      {:noreply, socket}
    else
      idx = parse_positive_index(raw_index)
      draft = socket.assigns.gene_draft
      domains = Map.get(draft, :domains, [])

      shifted =
        case to do
          "up" -> swap_at(domains, idx, idx - 1)
          "down" -> swap_at(domains, idx, idx + 1)
          _ -> domains
        end

      {:noreply,
       assign(socket,
         gene_draft: Map.put(draft, :domains, shifted),
         gene_editor_error: nil
       )}
    end
  end

  def handle_event("remove_draft_domain", %{"index" => raw_index}, socket) do
    if socket.assigns.seed_locked? do
      {:noreply, socket}
    else
      idx = parse_positive_index(raw_index)
      draft = socket.assigns.gene_draft
      domains = Map.get(draft, :domains, [])

      {:noreply,
       assign(socket,
         gene_draft: Map.put(draft, :domains, List.delete_at(domains, idx)),
         gene_editor_error: nil
       )}
    end
  end

  def handle_event("toggle_inspector", _params, socket) do
    {:noreply, assign(socket, inspector_expanded: not socket.assigns.inspector_expanded)}
  end

  def handle_event("provision_seed", %{"seed" => params}, socket) do
    cond do
      socket.assigns.seed_locked? ->
        {:noreply,
         socket
         |> assign(
           errors: %{
             starter_archetype: "This Arkeon seed is already committed to a home biotope."
           }
         )
         |> apply_form(%{})}

      socket.assigns[:recolonize_mode?] ->
        # Force the archetype back to the locked value before validation
        # so a tampered client cannot widen the recolonization scope.
        locked_archetype =
          socket.assigns.seed_params
          |> Map.get("starter_archetype")

        params = Map.put(params, "starter_archetype", locked_archetype)

        case SeedLab.recolonize_home_with_spec(socket.assigns.player, params) do
          {:ok, %{biotope_id: biotope_id}} ->
            {:noreply, push_navigate(socket, to: ~p"/biotopes/#{biotope_id}")}

          {:error, errors} when is_map(errors) ->
            {:noreply, socket |> assign(errors: errors) |> apply_form(params)}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(errors: %{starter_archetype: recolonize_error(reason)})
             |> apply_form(params)}
        end

      true ->
        case SeedLab.provision_home(socket.assigns.player, params) do
          {:ok, biotope_id} ->
            {:noreply, push_navigate(socket, to: ~p"/biotopes/#{biotope_id}")}

          {:error, errors} ->
            {:noreply, socket |> assign(errors: errors) |> apply_form(params)}
        end
    end
  end

  defp recolonize_error(:not_extinct),
    do: "Recolonization is only allowed when the home biotope is extinct."

  defp recolonize_error(:no_home),
    do: "No locked home biotope is associated with this player."

  defp recolonize_error(:biotope_missing),
    do: "The home biotope process is no longer running on this node."

  defp recolonize_error(:archetype_mismatch),
    do: "The starter archetype is fixed by the existing home biotope."

  defp recolonize_error(:blueprint_persist_failed),
    do: "Could not persist the new blueprint; recolonization aborted."

  defp recolonize_error(other), do: "Recolonization failed: #{inspect(other)}."

  @impl Phoenix.LiveView
  def render(assigns) do
    # canvas_layout is computed once per genome change (in apply_form/2) and
    # cached on socket.assigns; here we only resolve the currently selected
    # gene id, which is a cheap lookup.
    selected_gene_id =
      selected_gene_id(
        assigns.preview,
        assigns.selected_replicon_id,
        assigns.selected_gene_index
      )

    assigns = assign(assigns, selected_gene_id: selected_gene_id)

    ~H"""
    <Shell.shell sidebar?={false}>
      <:header>
        <Shell.shell_brand>Arkea</Shell.shell_brand>
        <Shell.shell_nav items={seed_lab_nav_items()} />
        <div class="arkea-shell__spacer"></div>
        <Shell.shell_user name={@player.display_name} logout_href={~p"/players/log-out"} />
      </:header>

      <div class="arkea-seed-lab arkea-scrollable">
        <header class="arkea-seed-lab__heading">
          <span class="arkea-seed-lab__eyebrow">Seed Lab</span>
          <h1 class="arkea-seed-lab__title">Visual genome editor</h1>
          <p class="arkea-seed-lab__copy">
            Compose phenotype + genome from functional domain palettes. The
            chromosome renders as a circular replicon with a domain crown;
            click a gene to inspect it.
          </p>
        </header>

        <Metric.metric_strip class="arkea-seed-lab__chips">
          <Metric.metric_chip label="genes" value={@preview.gene_count} tone="teal" />
          <Metric.metric_chip label="plasmids" value={@preview.plasmid_count} tone="sky" />
          <Metric.metric_chip label="prophages" value={@preview.prophage_count} tone="rust" />
          <Metric.metric_chip label="playstyle" value={@preview.playstyle} tone="muted" />
        </Metric.metric_strip>

        <div
          class="arkea-main-grid mt-6"
          style="grid-template-columns: minmax(0, 0.9fr) minmax(21rem, 1.1fr);"
        >
          <section class="arkea-card arkea-seed-form-card">
            <div class="arkea-card__header">
              <div>
                <div class="arkea-card__eyebrow">Builder</div>
                <h2 class="arkea-card__title">Phenotype + genome engineering</h2>
              </div>
              <div class="arkea-card__meta">
                {builder_status(@seed_locked?, @seed_ready?, @home_slot_open?)}
              </div>
            </div>

            <%= cond do %>
              <% @seed_locked? -> %>
                <div class="arkea-seed-lock-banner">
                  <div>
                    <div class="arkea-seed-lock-banner__title">Arkeon seed locked</div>
                    <div class="arkea-seed-lock-banner__copy">
                      This phenotype/genome configuration is already bound to the first colonized home biotope and can no longer be edited.
                    </div>
                  </div>

                  <.link
                    :if={@home_biotope_id}
                    href={~p"/biotopes/#{@home_biotope_id}"}
                    class="arkea-action-button"
                  >
                    Open home viewport
                  </.link>
                </div>
              <% @recolonize_mode? -> %>
                <div class="arkea-seed-lock-banner arkea-seed-lock-banner--recolonize">
                  <div>
                    <div class="arkea-seed-lock-banner__title">Edit seed to recolonize</div>
                    <div class="arkea-seed-lock-banner__copy">
                      The home biotope is extinct. You can edit every spec field except the
                      starter archetype (fixed by the existing biotope) and submit to
                      re-inoculate with the modified founder. The previous blueprint is
                      preserved in the audit log.
                    </div>
                  </div>

                  <.link
                    :if={@home_biotope_id}
                    href={~p"/biotopes/#{@home_biotope_id}"}
                    class="arkea-action-button"
                  >
                    Back to home viewport
                  </.link>
                </div>
              <% true -> %>
            <% end %>

            <form phx-change="change_seed" phx-submit="provision_seed" class="arkea-seed-form">
              <fieldset disabled={@seed_locked?} class="arkea-seed-form__fieldset">
                <div class="arkea-seed-field">
                  <label class="arkea-seed-field__label" for="seed_name">Seed name</label>
                  <input
                    id="seed_name"
                    name="seed[seed_name]"
                    type="text"
                    value={@form[:seed_name].value}
                    class="arkea-seed-input"
                    maxlength="40"
                  />
                  <p :if={Map.has_key?(@errors, :seed_name)} class="arkea-seed-field__error">
                    {@errors.seed_name}
                  </p>
                </div>

                <div class="arkea-seed-field">
                  <div class="arkea-seed-field__label">
                    Biotope archetype to colonize
                    <span :if={@recolonize_mode?} class="arkea-seed-field__hint">
                      (locked — recolonization keeps the existing biotope)
                    </span>
                  </div>
                  <div class="arkea-seed-choice-grid">
                    <label
                      :for={ecotype <- @starter_ecotypes}
                      class={[
                        "arkea-seed-choice",
                        @form[:starter_archetype].value == ecotype.id && "arkea-seed-choice--active",
                        (@seed_locked? || @recolonize_mode?) && "arkea-seed-choice--locked"
                      ]}
                    >
                      <input
                        type="radio"
                        name="seed[starter_archetype]"
                        value={ecotype.id}
                        checked={@form[:starter_archetype].value == ecotype.id}
                        disabled={@recolonize_mode?}
                      />
                      <span class="arkea-seed-choice__title">{ecotype.label}</span>
                      <span class="arkea-seed-choice__copy">{ecotype.strapline}</span>
                    </label>
                  </div>
                  <p :if={Map.has_key?(@errors, :starter_archetype)} class="arkea-seed-field__error">
                    {@errors.starter_archetype}
                  </p>
                </div>

                <div class="arkea-seed-config-grid">
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

                <input
                  type="hidden"
                  name="seed[custom_gene_payload]"
                  value={@seed_params["custom_gene_payload"]}
                />
              </fieldset>

              <div class="arkea-seed-submit-row">
                <button
                  type="submit"
                  class="arkea-action-button arkea-seed-submit"
                  disabled={!@seed_ready?}
                >
                  <%= cond do %>
                    <% @recolonize_mode? -> %>
                      Recolonize home with this seed
                    <% true -> %>
                      Colonize selected biotope
                  <% end %>
                </button>
                <p class="arkea-muted">
                  <%= cond do %>
                    <% @seed_locked? -> %>
                      The committed seed stays readable here, but its phenotype and genome options are frozen after first colonization.
                    <% @recolonize_mode? -> %>
                      The home biotope is extinct. Editing the seed and submitting will re-inoculate it with the modified founder. The previous blueprint stays in the audit log.
                    <% true -> %>
                      The player must name the seed and explicitly choose the first biotope archetype before colonization can start.
                  <% end %>
                </p>
              </div>
            </form>
          </section>

          <div class="arkea-sidebar">
            <section class="arkea-card">
              <div class="arkea-card__header">
                <div>
                  <div class="arkea-card__eyebrow">Morphology</div>
                  <h2 class="arkea-card__title">Arkeon phenotype portrait</h2>
                </div>
                <div class="arkea-card__meta">
                  <%= if @seed_locked? do %>
                    committed
                  <% else %>
                    live preview
                  <% end %>
                </div>
              </div>

              <.arkeon_portrait preview={@preview} seed_locked?={@seed_locked?} />
            </section>

            <section class="arkea-card">
              <div class="arkea-card__header">
                <div>
                  <div class="arkea-card__eyebrow">Preview</div>
                  <h2 class="arkea-card__title">{preview_seed_name(@preview)}</h2>
                </div>
                <div class="arkea-card__meta">{preview_ecotype_label(@preview)}</div>
              </div>

              <div class="arkea-phase-kpis" style="grid-template-columns: repeat(3, minmax(0, 1fr));">
                <div class="arkea-mini-stat">
                  <span class="arkea-mini-stat__label">µ (h⁻¹)</span>
                  <span class="arkea-mini-stat__value">
                    {format_float(@preview.phenotype.base_growth_rate, 2)}
                  </span>
                </div>
                <div class="arkea-mini-stat">
                  <span class="arkea-mini-stat__label">ε (repair)</span>
                  <span class="arkea-mini-stat__value">
                    {format_float(@preview.phenotype.repair_efficiency, 2)}
                  </span>
                </div>
                <div class="arkea-mini-stat">
                  <span class="arkea-mini-stat__label">E (ATP)</span>
                  <span class="arkea-mini-stat__value">
                    {format_float(@preview.phenotype.energy_cost, 2)}
                  </span>
                </div>
                <div class="arkea-mini-stat">
                  <span class="arkea-mini-stat__label">n_TM</span>
                  <span class="arkea-mini-stat__value">{@preview.phenotype.n_transmembrane}</span>
                </div>
                <div class="arkea-mini-stat">
                  <span class="arkea-mini-stat__label">σ affinity</span>
                  <span class="arkea-mini-stat__value">
                    {format_float(@preview.phenotype.dna_binding_affinity, 2)}
                  </span>
                </div>
                <div class="arkea-mini-stat">
                  <span class="arkea-mini-stat__label">QS signals</span>
                  <span class="arkea-mini-stat__value">{length(@preview.phenotype.qs_produces)}</span>
                </div>
              </div>

              <div class="arkea-seed-preview-copy">
                <div class="arkea-mini-list__title">{@preview.playstyle}</div>
                <div class="arkea-mini-list__copy">
                  {preview_world_copy(@preview)}
                </div>
              </div>
            </section>

            <section class="arkea-card">
              <div class="arkea-card__header">
                <div>
                  <div class="arkea-card__eyebrow">Genome preview</div>
                  <h2 class="arkea-card__title">Chromosome atlas</h2>
                </div>
                <div class="arkea-card__meta">{@preview.gene_count} genes total</div>
              </div>

              <.gene_designer
                domain_palette={@domain_palette}
                intergenic_palette={@intergenic_palette}
                gene_draft={@gene_draft}
                custom_gene_specs={@custom_gene_specs}
                seed_locked?={@seed_locked?}
                gene_editor_error={@gene_editor_error}
                preview={@preview}
              />

              <GenomeCanvas.genome_canvas
                layout={@canvas_layout}
                selected_gene_id={@selected_gene_id}
                class="arkea-seed-lab__canvas"
              />

              <div>
                <button
                  type="button"
                  class="arkea-card__eyebrow mb-2"
                  phx-click="toggle_inspector"
                  style="background: transparent; border: none; cursor: pointer; display: flex; align-items: center; gap: 0.5rem; color: #67e8f9;"
                >
                  Gene inspector <span>{if @inspector_expanded, do: "−", else: "+"}</span>
                </button>

                <%= if @inspector_expanded do %>
                  <.gene_inspector
                    preview={@preview}
                    custom_gene_specs={@custom_gene_specs}
                    selected_replicon_id={@selected_replicon_id}
                    selected_gene_index={@selected_gene_index}
                  />
                <% end %>
              </div>
            </section>

            <section class="arkea-card">
              <div class="arkea-card__header">
                <div>
                  <div class="arkea-card__eyebrow">Cassette manifest</div>
                  <h2 class="arkea-card__title">Domain inventory</h2>
                </div>
                <div class="arkea-card__meta">{length(@preview.modules)} replicon views</div>
              </div>

              <div class="arkea-mini-list">
                <div :for={entry <- @preview.modules} class="arkea-mini-list__item">
                  <div class="arkea-mini-list__title">{entry.scope} · {entry.label}</div>
                  <div class="arkea-mini-list__copy">{Enum.join(entry.domains, " · ")}</div>
                </div>
              </div>
            </section>

            <section class="arkea-card">
              <div class="arkea-card__header">
                <div>
                  <div class="arkea-card__eyebrow">World insertion</div>
                  <h2 class="arkea-card__title">Home placement</h2>
                </div>
                <div class="arkea-card__meta">
                  <%= if starter_selected?(@preview) do %>
                    {@preview.phase_count} phases
                  <% else %>
                    starter choice required
                  <% end %>
                </div>
              </div>

              <%= if starter_selected?(@preview) do %>
                <div class="arkea-topology-grid">
                  <.env_reading
                    label="coords"
                    value={format_float(elem(@preview.spawn_coords, 0), 1) <> ", " <> format_float(elem(@preview.spawn_coords, 1), 1)}
                  />
                  <.env_reading label="neighbors" value={length(@preview.neighbor_ids)} />
                </div>

                <div>
                  <div class="arkea-card__eyebrow mb-2">Outgoing arcs</div>
                  <%= if @preview.neighbor_ids == [] do %>
                    <p class="arkea-muted">
                      No active biotopes detected yet. This home will start as an isolated prototype node.
                    </p>
                  <% else %>
                    <div class="arkea-token-cloud">
                      <span
                        :for={neighbor_id <- @preview.neighbor_ids}
                        class="arkea-token arkea-token--ghost"
                      >
                        {String.slice(neighbor_id, 0, 8)}
                      </span>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <p class="arkea-muted">
                  Choose a starter biotope archetype to preview insertion coordinates, nearby arcs, and the phase layout of the first controlled colony.
                </p>
              <% end %>
            </section>
          </div>
        </div>
      </div>
    </Shell.shell>
    """
  end

  defp selected_gene_id(preview, replicon_id, gene_index) do
    case replicon_id do
      "chromosome" ->
        case Enum.at(preview.genome.chromosome, max(gene_index - 1, 0)) do
          %{id: id} -> id
          _ -> nil
        end

      "plasmid_" <> rest ->
        case Integer.parse(rest) do
          {idx, _} ->
            plasmid = Enum.at(preview.genome.plasmids, max(idx - 1, 0))

            cond do
              is_nil(plasmid) ->
                nil

              true ->
                genes = if is_map(plasmid), do: plasmid.genes, else: plasmid

                case Enum.at(genes, max(gene_index - 1, 0)) do
                  %{id: id} -> id
                  _ -> nil
                end
            end

          :error ->
            nil
        end

      _ ->
        nil
    end
  end

  attr(:field, :string, required: true)
  attr(:label, :string, required: true)
  attr(:value, :string, required: true)
  attr(:options, :list, required: true)

  defp option_select(assigns) do
    ~H"""
    <div class="arkea-seed-field">
      <label class="arkea-seed-field__label" for={@field}>{@label}</label>
      <select id={@field} name={"seed[#{@field}]"} class="arkea-seed-input">
        <option :for={option <- @options} value={option.id} selected={@value == option.id}>
          {option.label}
        </option>
      </select>
      <p class="arkea-seed-field__hint">
        {selected_description(@options, @value)}
      </p>
    </div>
    """
  end

  attr(:preview, :map, required: true)
  attr(:seed_locked?, :boolean, required: true)

  defp arkeon_portrait(assigns) do
    layout = SchematicLayout.build(assigns.preview)
    assigns = assign(assigns, layout: layout)

    ~H"""
    <div class="arkea-seed-portrait">
      <ArkeonSchematic.arkeon_schematic layout={@layout} />

      <div class="arkea-seed-portrait__legend">
        <div :for={entry <- @layout.legend} class="arkea-seed-portrait__legend-item">
          <span class="arkea-seed-portrait__legend-label">{entry.label}</span>
          <span class="arkea-seed-portrait__legend-copy">{entry.value}</span>
        </div>
      </div>

      <p class="arkea-muted">
        Schematic representation of the cell derived from the current phenotype
        and genome choices. Envelope shape, transmembrane spans, plasmids,
        prophage integration, surface appendages, and stress halo all map to
        a phenotype feature; the layout stays diagrammatic, not photoreal.
      </p>
    </div>
    """
  end

  attr(:preview, :map, required: true)
  attr(:domain_palette, :list, required: true)
  attr(:intergenic_palette, :map, required: true)
  attr(:gene_draft, :map, required: true)
  attr(:custom_gene_specs, :list, required: true)
  attr(:seed_locked?, :boolean, required: true)
  attr(:gene_editor_error, :string, default: nil)

  defp gene_designer(assigns) do
    draft_domains = Map.get(assigns.gene_draft, :domains, [])
    draft_intergenic = Map.get(assigns.gene_draft, :intergenic, empty_intergenic_blocks())

    assigns =
      assign(assigns,
        draft_domains: draft_domains,
        draft_intergenic: draft_intergenic,
        draft_intergenic_count: intergenic_count(draft_intergenic),
        custom_gene_count: length(assigns.custom_gene_specs)
      )

    ~H"""
    <div class="arkea-seed-editor">
      <div class="arkea-seed-editor__summary">
        <div class="arkea-phase-kpis">
          <div class="arkea-mini-stat">
            <span class="arkea-mini-stat__label">chromosome genes</span>
            <span class="arkea-mini-stat__value">{@preview.chromosome_gene_count}</span>
          </div>
          <div class="arkea-mini-stat">
            <span class="arkea-mini-stat__label">custom genes</span>
            <span class="arkea-mini-stat__value">{@preview.custom_gene_count}</span>
          </div>
          <div class="arkea-mini-stat">
            <span class="arkea-mini-stat__label">draft blocks</span>
            <span class="arkea-mini-stat__value">
              {length(@draft_domains)} + {@draft_intergenic_count}
            </span>
          </div>
          <div class="arkea-mini-stat">
            <span class="arkea-mini-stat__label">replicons</span>
            <span class="arkea-mini-stat__value">
              {1 + @preview.plasmid_count + @preview.prophage_count}
            </span>
          </div>
        </div>
      </div>

      <div class="arkea-seed-editor__panel">
        <div class="arkea-card__eyebrow">Custom chromosome gene designer</div>
        <p class="arkea-muted arkea-seed-editor__copy">
          Compose a chromosome gene from the functional domains implemented in the simulation. Intergenic blocks now feed runtime expression control, transfer bias, and duplication hotspots.
        </p>

        <div class="arkea-seed-editor__draft">
          <div class="arkea-seed-editor__draft-title">Draft gene</div>
          <ul class="arkea-draft-domains" role="list">
            <li
              :for={{domain_id, idx} <- Enum.with_index(@draft_domains)}
              class={[
                "arkea-draft-domain",
                "arkea-draft-domain--#{domain_tone(domain_type_from_id(domain_id))}"
              ]}
              data-draft-index={idx}
            >
              <span
                class="arkea-draft-domain__swatch"
                style={"background: #{CanvasLayout.domain_color(domain_type_from_id(domain_id))}"}
                aria-hidden="true"
              />
              <span class="arkea-draft-domain__label">
                {domain_label(domain_type_from_id(domain_id))}
              </span>
              <span class="arkea-draft-domain__controls">
                <button
                  type="button"
                  phx-click="move_draft_domain"
                  phx-value-index={idx}
                  phx-value-to="up"
                  class="arkea-draft-domain__btn"
                  disabled={@seed_locked? or idx == 0}
                  aria-label="Move domain up"
                  title="Move up"
                >
                  ↑
                </button>
                <button
                  type="button"
                  phx-click="move_draft_domain"
                  phx-value-index={idx}
                  phx-value-to="down"
                  class="arkea-draft-domain__btn"
                  disabled={@seed_locked? or idx == length(@draft_domains) - 1}
                  aria-label="Move domain down"
                  title="Move down"
                >
                  ↓
                </button>
                <button
                  type="button"
                  phx-click="remove_draft_domain"
                  phx-value-index={idx}
                  class="arkea-draft-domain__btn arkea-draft-domain__btn--danger"
                  disabled={@seed_locked?}
                  aria-label="Remove domain"
                  title="Remove"
                >
                  ×
                </button>
              </span>
            </li>
            <li :if={@draft_domains == []} class="arkea-draft-domain arkea-draft-domain--empty">
              Add functional domains from the palette below.
            </li>
          </ul>

          <div class="arkea-seed-intergenic-summary">
            <span
              :for={entry <- intergenic_badges(@draft_intergenic)}
              class="arkea-seed-intergenic-chip"
            >
              {entry}
            </span>
            <span :if={intergenic_badges(@draft_intergenic) == []} class="arkea-muted">
              no intergenic blocks attached
            </span>
          </div>

          <p :if={@gene_editor_error} class="arkea-seed-field__error">{@gene_editor_error}</p>
        </div>

        <div class="arkea-seed-editor__palette">
          <button
            :for={domain <- @domain_palette}
            type="button"
            class={[
              "arkea-seed-palette-button",
              domain.runtime == :latent && "arkea-seed-palette-button--latent"
            ]}
            phx-click="append_domain"
            phx-value-type={domain.id}
            disabled={@seed_locked?}
            title={domain.description}
          >
            <span class="arkea-seed-palette-button__title">{domain.label}</span>
            <span class="arkea-seed-palette-button__meta">
              {if(domain.runtime == :active, do: "active now", else: "stored / future")}
            </span>
          </button>
        </div>

        <div class="arkea-seed-intergenic-grid">
          <div :for={{family, entries} <- @intergenic_palette} class="arkea-seed-intergenic-group">
            <div class="arkea-seed-editor__draft-title">{intergenic_family_label(family)}</div>
            <div class="arkea-seed-intergenic-group__buttons">
              <button
                :for={entry <- entries}
                type="button"
                class={[
                  "arkea-seed-intergenic-button",
                  intergenic_selected?(@draft_intergenic, family, entry.id) &&
                    "arkea-seed-intergenic-button--active"
                ]}
                phx-click="toggle_intergenic"
                phx-value-family={family}
                phx-value-module={entry.id}
                disabled={@seed_locked?}
                title={entry.description}
              >
                {entry.label}
              </button>
            </div>
          </div>
        </div>

        <div class="arkea-seed-editor__actions">
          <button
            type="button"
            class="arkea-action-button"
            phx-click="undo_gene_domain"
            disabled={@seed_locked? or @draft_domains == []}
          >
            Undo domain
          </button>
          <button
            type="button"
            class="arkea-action-button"
            phx-click="clear_gene_draft"
            disabled={@seed_locked? or (@draft_domains == [] and @draft_intergenic_count == 0)}
          >
            Clear draft
          </button>
          <button
            type="button"
            class="arkea-action-button"
            phx-click="commit_custom_gene"
            disabled={@seed_locked?}
          >
            Commit chromosome gene
          </button>
        </div>
      </div>

      <div class="arkea-seed-custom-gene-list">
        <div class="arkea-seed-editor__draft-title">Committed custom genes</div>
        <%= if @custom_gene_specs == [] do %>
          <p class="arkea-muted">
            No custom chromosome genes committed yet. The atlas currently shows only the phenotype-derived base genome.
          </p>
        <% else %>
          <div
            :for={{gene, index} <- Enum.with_index(@custom_gene_specs, 1)}
            class="arkea-seed-custom-gene"
          >
            <div class="arkea-seed-custom-gene__header">
              <span class="arkea-seed-custom-gene__title">Custom gene {index}</span>
              <button
                :if={!@seed_locked?}
                type="button"
                class="arkea-seed-custom-gene__remove"
                phx-click="remove_custom_gene"
                phx-value-index={index - 1}
              >
                Remove
              </button>
            </div>
            <div class="arkea-seed-gene__bar">
              <span
                :for={domain_id <- gene.domains}
                class={[
                  "arkea-seed-domain",
                  "arkea-seed-domain--#{domain_tone(domain_type_from_id(domain_id))}"
                ]}
                style="flex: 23;"
                title={domain_label(domain_type_from_id(domain_id))}
              >
              </span>
            </div>
            <div class="arkea-seed-custom-gene__meta">
              {Enum.map_join(gene.domains, " · ", &domain_label(domain_type_from_id(&1)))}
            </div>
            <div class="arkea-seed-intergenic-summary">
              <span
                :for={entry <- intergenic_badges(gene.intergenic)}
                class="arkea-seed-intergenic-chip"
              >
                {entry}
              </span>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr(:preview, :map, required: true)
  attr(:custom_gene_specs, :list, required: true)
  attr(:selected_replicon_id, :string, required: true)
  attr(:selected_gene_index, :integer, required: true)

  defp gene_inspector(assigns) do
    gene =
      selected_gene_view(
        assigns.preview,
        assigns.custom_gene_specs,
        assigns.selected_replicon_id,
        assigns.selected_gene_index
      )

    assigns = assign(assigns, gene: gene)

    ~H"""
    <div :if={@gene} class="arkea-seed-gene-inspector">
      <div class="arkea-seed-gene-inspector__header">
        <div>
          <div class="arkea-card__eyebrow">Gene inspector</div>
          <h3 id="arkea-seed-gene-inspector-title" class="arkea-seed-gene-inspector__title">
            {@gene.replicon_label} · {@gene.label}
          </h3>
        </div>
        <div class="arkea-seed-gene-inspector__meta">
          {@gene.domain_count} domains · {@gene.codon_count} codons
        </div>
      </div>

      <p class="arkea-muted">
        {@gene.behavior_copy}
      </p>

      <div
        :if={intergenic_badges(@gene.intergenic_blocks) != []}
        class="arkea-seed-gene-inspector__blocks"
      >
        <span
          :for={entry <- intergenic_badges(@gene.intergenic_blocks)}
          class="arkea-seed-intergenic-chip"
        >
          {entry}
        </span>
      </div>

      <div class="arkea-seed-domain-stack">
        <div
          :for={{domain, index} <- Enum.with_index(@gene.raw_gene.domains, 1)}
          class="arkea-seed-domain-card"
        >
          <div class="arkea-seed-domain-card__header">
            <span class={[
              "arkea-seed-domain-legend__swatch",
              "arkea-seed-domain-legend__swatch--#{domain_tone(domain.type)}"
            ]}>
            </span>
            <span class="arkea-seed-domain-card__title">
              Domain {index} · {domain_label(domain.type)}
            </span>
          </div>
          <div class="arkea-seed-domain-card__copy">{domain_summary(domain)}</div>
        </div>
      </div>
    </div>
    """
  end

  defp env_reading(assigns) do
    ~H"""
    <div class="arkea-env-reading">
      <span class="arkea-env-reading__label">{@label}</span>
      <span class="arkea-env-reading__value">{@value}</span>
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
    case SeedLab.locked_seed(socket.assigns.player) do
      %{params: locked_params, preview: locked_preview, biotope_id: biotope_id} = locked ->
        if SeedLab.home_extinct?(socket.assigns.player) do
          # Extinct home: form is editable for recolonization. The
          # starter_archetype is fixed (the existing biotope already lives
          # at that archetype), but every other field is up for change so
          # the player can iterate the seed strategy.
          base =
            socket
            |> Map.get(:assigns)
            |> Map.get(:seed_params, locked_params)

          merged =
            base
            |> Map.merge(Map.new(params))
            # Force the archetype back to the locked one in case the
            # client tried to override it.
            |> Map.put(
              "starter_archetype",
              Map.get(locked_params, "starter_archetype")
            )

          preview = SeedLab.preview(merged, socket.assigns.player)

          socket
          |> assign(
            form: to_form(merged, as: :seed),
            preview: preview,
            can_provision_home?: false,
            home_slot_open?: false,
            seed_ready?: seed_ready_for_provision?(preview),
            seed_locked?: false,
            recolonize_mode?: true,
            home_biotope_id: biotope_id,
            seed_params: merged,
            custom_gene_specs: preview.spec.custom_genes
          )
          |> assign_editor_focus(preview)
        else
          # Alive locked home: read-only form, the original behaviour.
          _ = locked

          socket
          |> assign(
            form: to_form(locked_params, as: :seed),
            preview: locked_preview,
            can_provision_home?: false,
            home_slot_open?: false,
            seed_ready?: false,
            seed_locked?: true,
            recolonize_mode?: false,
            home_biotope_id: biotope_id,
            seed_params: locked_params,
            custom_gene_specs: locked_preview.spec.custom_genes
          )
          |> assign_editor_focus(locked_preview)
        end

      nil ->
        merged =
          socket
          |> Map.get(:assigns)
          |> Map.get(:seed_params, SeedLab.form_defaults())
          |> Map.merge(Map.new(params))

        preview = SeedLab.preview(merged, socket.assigns.player)
        home_slot_open? = SeedLab.can_provision_home?(socket.assigns.player)

        socket
        |> assign(
          form: to_form(merged, as: :seed),
          preview: preview,
          can_provision_home?: home_slot_open?,
          home_slot_open?: home_slot_open?,
          seed_ready?: home_slot_open? and seed_ready_for_provision?(preview),
          seed_locked?: false,
          recolonize_mode?: false,
          home_biotope_id: nil,
          seed_params: merged,
          custom_gene_specs: preview.spec.custom_genes
        )
        |> assign_editor_focus(preview)
    end
  end

  defp assign_editor_focus(socket, preview) do
    replicons = replicon_views(preview, preview.spec.custom_genes)

    socket =
      case find_gene_view(
             replicons,
             socket.assigns[:selected_replicon_id],
             socket.assigns[:selected_gene_index]
           ) do
        nil ->
          assign(socket,
            selected_replicon_id: "chromosome",
            selected_gene_index: 1
          )

        _gene ->
          socket
      end

    assign_canvas_layout(socket)
  end

  defp assign_canvas_layout(socket) do
    layout = CanvasLayout.build(CanvasLayout.from_preview(socket.assigns.preview))
    assign(socket, canvas_layout: layout)
  end

  defp replace_custom_genes(socket, custom_gene_specs) do
    params =
      socket.assigns.seed_params
      |> Map.put("custom_gene_payload", Jason.encode!(custom_gene_specs))

    apply_form(socket, params)
  end

  defp seed_ready_for_provision?(preview) do
    preview.spec.seed_name != "" and starter_selected?(preview)
  end

  defp starter_selected?(preview) do
    Map.get(preview.spec, :starter_selected?, false)
  end

  defp preview_seed_name(preview) do
    case preview.spec.seed_name do
      "" -> "Unnamed seed"
      name -> name
    end
  end

  defp preview_ecotype_label(preview) do
    if starter_selected?(preview), do: preview.ecotype.label, else: "Choose a starter biotope"
  end

  defp preview_world_copy(preview) do
    if starter_selected?(preview) do
      "Spawn zone #{zone_label(preview.ecotype.zone)} · phases #{Enum.map_join(preview.phase_names, ", ", &phase_label/1)}"
    else
      "Choose the first biotope archetype to colonize. World placement and phase layout preview unlock after that selection."
    end
  end

  defp builder_status(true, _seed_ready?, _home_slot_open?), do: "seed locked after colonization"
  defp builder_status(false, true, _home_slot_open?), do: "home slot open"
  defp builder_status(false, false, true), do: "design seed + choose biotope"
  defp builder_status(false, false, false), do: "home slot unavailable"

  defp focus_chromosome_tail(socket) do
    assign(socket,
      selected_replicon_id: "chromosome",
      selected_gene_index: length(socket.assigns.preview.genome.chromosome)
    )
  end

  defp empty_gene_draft do
    %{domains: [], intergenic: empty_intergenic_blocks()}
  end

  defp empty_intergenic_blocks do
    %{expression: [], transfer: [], duplication: []}
  end

  defp valid_domain_palette_id?(palette, type_id) do
    Enum.any?(palette, &(&1.id == type_id))
  end

  defp toggle_intergenic_module(draft, family, module_id, palette) do
    family_key = parse_intergenic_family(family)

    valid_ids =
      palette
      |> Map.fetch!(family_key)
      |> Enum.map(& &1.id)

    if module_id in valid_ids do
      update_in(draft, [:intergenic, family_key], fn values ->
        if module_id in values do
          List.delete(values, module_id)
        else
          values ++ [module_id]
        end
      end)
    else
      draft
    end
  end

  defp parse_intergenic_family("expression"), do: :expression
  defp parse_intergenic_family("transfer"), do: :transfer
  defp parse_intergenic_family("duplication"), do: :duplication
  defp parse_intergenic_family(:expression), do: :expression
  defp parse_intergenic_family(:transfer), do: :transfer
  defp parse_intergenic_family(:duplication), do: :duplication

  defp intergenic_selected?(blocks, family, module_id) do
    module_id in Map.get(blocks, parse_intergenic_family(family), [])
  end

  defp intergenic_badges(blocks) do
    [
      label_intergenic_modules(Map.get(blocks, :expression, []), "expr"),
      label_intergenic_modules(Map.get(blocks, :transfer, []), "xfer"),
      label_intergenic_modules(Map.get(blocks, :duplication, []), "dup")
    ]
    |> List.flatten()
  end

  defp label_intergenic_modules(modules, prefix) do
    Enum.map(modules, fn module_id ->
      "#{prefix}:#{module_short_label(module_id)}"
    end)
  end

  defp module_short_label("sigma_promoter"), do: "sigma"
  defp module_short_label("multi_sigma_operator"), do: "multi-op"
  defp module_short_label("metabolite_riboswitch"), do: "riboswitch"
  defp module_short_label("orit_site"), do: "oriT"
  defp module_short_label("integration_hotspot"), do: "landing"
  defp module_short_label("repeat_array"), do: "repeat"
  defp module_short_label("duplication_hotspot"), do: "hotspot"
  defp module_short_label(other), do: other

  defp intergenic_family_label(:expression), do: "Expression control"
  defp intergenic_family_label(:transfer), do: "Transfer"
  defp intergenic_family_label(:duplication), do: "Duplication"

  defp intergenic_count(blocks) do
    blocks.expression
    |> length()
    |> Kernel.+(length(blocks.transfer))
    |> Kernel.+(length(blocks.duplication))
  end

  defp parse_positive_index(index) when is_binary(index) do
    case Integer.parse(index) do
      {value, _rest} when value >= 0 -> value
      _ -> 0
    end
  end

  defp locate_gene_by_id(preview, gene_id) do
    case Enum.find_index(preview.genome.chromosome, &(&1.id == gene_id)) do
      nil ->
        preview.genome.plasmids
        |> Enum.with_index(1)
        |> Enum.find_value(:not_found, fn {plasmid, idx} ->
          genes = if is_map(plasmid), do: plasmid.genes, else: plasmid

          case Enum.find_index(genes, &(&1.id == gene_id)) do
            nil -> nil
            gene_idx -> {"plasmid_#{idx}", gene_idx + 1}
          end
        end)

      chrom_idx ->
        {"chromosome", chrom_idx + 1}
    end
  end

  defp swap_at(list, i, j)
       when is_integer(i) and is_integer(j) and i >= 0 and j >= 0 and i != j do
    case {Enum.at(list, i), Enum.at(list, j)} do
      {nil, _} -> list
      {_, nil} -> list
      {a, b} -> list |> List.replace_at(i, b) |> List.replace_at(j, a)
    end
  end

  defp swap_at(list, _i, _j), do: list

  defp seed_lab_nav_items do
    [
      %{label: "Dashboard", href: "/dashboard", active: false},
      %{label: "World", href: "/world", active: false},
      %{label: "Seed Lab", href: "/seed-lab", active: true}
    ]
  end

  defp replicon_views(preview, custom_gene_specs) do
    base_chromosome_count = preview.chromosome_gene_count - length(custom_gene_specs)

    chromosome =
      %{
        id: "chromosome",
        label: "Chromosome",
        tone: "core",
        genes:
          preview.genome.chromosome
          |> Enum.with_index(1)
          |> Enum.map(fn {gene, index} ->
            gene_view(
              gene,
              index,
              "chromosome",
              "Chromosome",
              "G#{index}",
              index > base_chromosome_count
            )
          end)
      }

    plasmids =
      preview.genome.plasmids
      |> Enum.with_index(1)
      |> Enum.map(fn {plasmid, index} ->
        %{
          id: "plasmid_#{index}",
          label: "Plasmid #{index}",
          tone: "plasmid",
          genes:
            plasmid.genes
            |> Enum.with_index(1)
            |> Enum.map(fn {gene, gene_index} ->
              gene_view(
                gene,
                gene_index,
                "plasmid_#{index}",
                "Plasmid #{index}",
                "P#{index}.#{gene_index}",
                false
              )
            end)
        }
      end)

    prophages =
      preview.genome.prophages
      |> Enum.with_index(1)
      |> Enum.map(fn {prophage, index} ->
        %{
          id: "prophage_#{index}",
          label: "Prophage #{index}",
          tone: "prophage",
          genes:
            prophage.genes
            |> Enum.with_index(1)
            |> Enum.map(fn {gene, gene_index} ->
              gene_view(
                gene,
                gene_index,
                "prophage_#{index}",
                "Prophage #{index}",
                "Phi#{index}.#{gene_index}",
                false
              )
            end)
        }
      end)

    [chromosome | plasmids ++ prophages]
  end

  defp gene_view(%Gene{} = gene, index, replicon_id, replicon_label, label, is_custom) do
    %{
      index: index,
      replicon_id: replicon_id,
      replicon_label: replicon_label,
      label: if(is_custom, do: "Custom #{label}", else: label),
      codon_count: length(gene.codons),
      domain_count: length(gene.domains),
      domains: domain_views(gene),
      intergenic_blocks: Map.get(gene, :intergenic_blocks, empty_intergenic_blocks()),
      is_custom: is_custom,
      raw_gene: gene,
      behavior_copy: behavior_copy(replicon_id, is_custom)
    }
  end

  defp selected_gene_view(preview, custom_gene_specs, selected_replicon_id, selected_gene_index) do
    preview
    |> replicon_views(custom_gene_specs)
    |> find_gene_view(selected_replicon_id, selected_gene_index)
  end

  defp find_gene_view(replicons, selected_replicon_id, selected_gene_index) do
    replicons
    |> Enum.find(&(&1.id == selected_replicon_id))
    |> case do
      nil -> nil
      replicon -> Enum.find(replicon.genes, &(&1.index == selected_gene_index))
    end
  end

  defp behavior_copy("chromosome", true),
    do:
      "Custom chromosome cassette. It will inherit vertically from the home seed and can alter phenotype immediately."

  defp behavior_copy("chromosome", false),
    do: "Baseline chromosome cassette derived from the phenotype-first seed configuration."

  defp behavior_copy(replicon_id, _is_custom) do
    cond do
      String.starts_with?(replicon_id, "plasmid") ->
        "Accessory plasmid cassette. It remains mobile and actively participates in transfer logic."

      String.starts_with?(replicon_id, "prophage") ->
        "Integrated prophage cassette. It stays latent until future induction or transfer pathways activate it."

      true ->
        "Genome cassette."
    end
  end

  defp domain_summary(%Domain{type: :substrate_binding, params: params}) do
    "Target metabolite #{params.target_metabolite_id} · Km #{format_float(params.km, 2)} · breadth #{format_float(params.specificity_breadth, 2)}"
  end

  defp domain_summary(%Domain{type: :catalytic_site, params: params}) do
    "Reaction #{params.reaction_class} · kcat #{format_float(params.kcat, 2)} · signal #{params.signal_key}"
  end

  defp domain_summary(%Domain{type: :transmembrane_anchor, params: params}) do
    "Hydrophobicity #{format_float(params.hydrophobicity, 2)} · #{params.n_passes} membrane passes"
  end

  defp domain_summary(%Domain{type: :channel_pore, params: params}) do
    "Selectivity #{format_float(params.selectivity, 2)} · gating #{format_float(params.gating_threshold, 2)}"
  end

  defp domain_summary(%Domain{type: :energy_coupling, params: params}) do
    "ATP cost #{format_float(params.atp_cost, 2)} · PMF #{format_float(params.pmf_coupling, 2)}"
  end

  defp domain_summary(%Domain{type: :dna_binding, params: params}) do
    "Promoter specificity #{format_float(params.promoter_specificity, 2)} · affinity #{format_float(params.binding_affinity, 2)}"
  end

  defp domain_summary(%Domain{type: :regulator_output, params: params}) do
    "Mode #{params.mode} · cooperativity #{format_float(params.cooperativity, 2)}"
  end

  defp domain_summary(%Domain{type: :ligand_sensor, params: params}) do
    "Signal #{params.signal_key} · threshold #{format_float(params.threshold, 2)} · curve #{params.response_curve}"
  end

  defp domain_summary(%Domain{type: :structural_fold, params: params}) do
    "Stability #{format_float(params.stability, 2)} · multimerization #{params.multimerization_n}"
  end

  defp domain_summary(%Domain{type: :surface_tag, params: params}) do
    "Surface identity #{params.tag_class}"
  end

  defp domain_summary(%Domain{type: :repair_fidelity, params: params}) do
    "Repair class #{params.repair_class} · efficiency #{format_float(params.efficiency, 2)}"
  end

  defp domain_summary(%Domain{type: type}) do
    "#{domain_label(type)} domain stored in the genome. Detailed runtime aggregation is deferred."
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

  # Old `shell_class/1`, `core_class/1`, `pulse_class/1`, `accessory_class/1`
  # and the `*_copy/1` helpers were absorbed by `Arkea.Views.ArkeonSchematic`
  # when the cell glyph was replaced by an SVG schematic.

  defp domain_views(%Gene{} = gene) do
    Enum.map(gene.domains, fn domain ->
      %{
        label: domain_label(domain.type),
        tone: domain_tone(domain.type),
        flex: Domain.codon_length(domain)
      }
    end)
  end

  # All 11 functional domain types map to a distinct CSS tone (Block 7).
  defp domain_tone(:substrate_binding), do: "binding"
  defp domain_tone(:catalytic_site), do: "catalytic"
  defp domain_tone(:transmembrane_anchor), do: "membrane"
  defp domain_tone(:channel_pore), do: "channel"
  defp domain_tone(:energy_coupling), do: "energy"
  defp domain_tone(:dna_binding), do: "regulation"
  defp domain_tone(:regulator_output), do: "regulator"
  defp domain_tone(:ligand_sensor), do: "sensor"
  defp domain_tone(:structural_fold), do: "structure"
  defp domain_tone(:surface_tag), do: "surface"
  defp domain_tone(:repair_fidelity), do: "repair"
  defp domain_tone(_type), do: "other"

  defp domain_label(:dna_binding), do: "DNA Binding"

  defp domain_label(type) when is_atom(type) do
    type
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  # Resolve a palette `domain_id` (string) to its canonical Domain.Type atom.
  # The palette is server-rendered, so a mismatched id is always a bug rather
  # than user input — return `:unknown` so the UI shows a neutral tone instead
  # of silently masquerading as Substrate Binding.
  defp domain_type_from_id(domain_id) when is_binary(domain_id) do
    atom = String.to_existing_atom(domain_id)

    if Arkea.Genome.Domain.Type.valid?(atom) do
      atom
    else
      :unknown
    end
  rescue
    ArgumentError -> :unknown
  end
end
