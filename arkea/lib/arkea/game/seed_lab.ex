defmodule Arkea.Game.SeedLab do
  @moduledoc """
  Prototype seed-builder and home-biotope provisioning flow.

  The current version is intentionally lightweight:

  - phenotype-first choices produce a deterministic genome scaffold
  - the genome is previewable before provisioning
  - provisioning persists a blueprint plus one owned home biotope for the
    prototype player
  """

  alias Arkea.Ecology.Biotope
  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Game.PlayerAssets
  alias Arkea.Game.PrototypePlayer
  alias Arkea.Game.World
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Persistence.ArkeonBlueprint
  alias Arkea.Persistence.PlayerBiotope
  alias Arkea.Persistence.Store
  alias Arkea.Sim.Biotope.Supervisor, as: BiotopeSupervisor
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Phenotype

  @starter_ecotypes [
    %{
      id: "eutrophic_pond",
      archetype: :eutrophic_pond,
      label: "Eutrophic pond",
      strapline: "Fast nutrient turnover, forgiving early growth, swamp-edge zone.",
      zone: :swampy_zone
    },
    %{
      id: "oligotrophic_lake",
      archetype: :oligotrophic_lake,
      label: "Oligotrophic lake",
      strapline: "Cleaner water, more oxygen, lower carbon inflow, lacustrine zone.",
      zone: :lacustrine_zone
    },
    %{
      id: "mesophilic_soil",
      archetype: :mesophilic_soil,
      label: "Mesophilic soil",
      strapline: "Patchy oxygen and wet clumps, robust generalist play, soil zone.",
      zone: :soil_zone
    }
  ]

  @metabolism_profiles [
    %{
      id: "thrifty",
      label: "Resource thrifty",
      description: "Lower draw, higher affinity, slower but resilient early spread."
    },
    %{
      id: "balanced",
      label: "Balanced facultative",
      description: "Middle-ground cassette for mixed phase occupancy and steady growth."
    },
    %{
      id: "bloom",
      label: "Bloom chaser",
      description: "Higher throughput and cost, strongest in rich compartments."
    }
  ]

  @membrane_profiles [
    %{
      id: "porous",
      label: "Porous shell",
      description: "Low-cost envelope with minimal membrane complexity."
    },
    %{
      id: "fortified",
      label: "Fortified wall",
      description: "Heavier structural stability and higher upkeep."
    },
    %{
      id: "salinity_tuned",
      label: "Salinity tuned",
      description: "More membrane hardware and osmotic tolerance bias."
    }
  ]

  @regulation_profiles [
    %{
      id: "steady",
      label: "Steady expression",
      description: "Simpler regulation and higher repair fidelity."
    },
    %{
      id: "responsive",
      label: "Responsive circuit",
      description: "Adds signal sensing and stronger transcriptional coupling."
    },
    %{
      id: "mutator",
      label: "Mutator edge",
      description: "Less repair discipline, more variation pressure."
    }
  ]

  @mobile_modules [
    %{
      id: "none",
      label: "Clean chromosome",
      description: "No mobile accessory at launch."
    },
    %{
      id: "conjugative_plasmid",
      label: "Conjugative plasmid",
      description: "Extra membrane-coded helper plasmid for later HGT opportunities."
    },
    %{
      id: "latent_prophage",
      label: "Latent prophage",
      description: "Integrates a dormant prophage cassette into the seed genome."
    }
  ]

  @defaults %{
    "seed_name" => "Aster-Seed",
    "starter_archetype" => "eutrophic_pond",
    "metabolism_profile" => "balanced",
    "membrane_profile" => "porous",
    "regulation_profile" => "responsive",
    "mobile_module" => "none"
  }

  @type preview :: %{
          spec: map(),
          player: %{id: binary(), display_name: binary()},
          ecotype: map(),
          phenotype: Phenotype.t(),
          genome: Genome.t(),
          gene_count: non_neg_integer(),
          plasmid_count: non_neg_integer(),
          prophage_count: non_neg_integer(),
          playstyle: binary(),
          modules: [map()],
          spawn_coords: {float(), float()},
          neighbor_ids: [binary()],
          phase_names: [atom()],
          phase_count: non_neg_integer()
        }

  @spec form_defaults() :: map()
  def form_defaults, do: @defaults

  @spec starter_ecotypes() :: [map()]
  def starter_ecotypes, do: @starter_ecotypes

  @spec metabolism_profiles() :: [map()]
  def metabolism_profiles, do: @metabolism_profiles

  @spec membrane_profiles() :: [map()]
  def membrane_profiles, do: @membrane_profiles

  @spec regulation_profiles() :: [map()]
  def regulation_profiles, do: @regulation_profiles

  @spec mobile_modules() :: [map()]
  def mobile_modules, do: @mobile_modules

  @spec locked_seed() ::
          %{
            biotope_id: binary(),
            blueprint_id: binary(),
            params: map(),
            preview: preview()
          }
          | nil
  def locked_seed do
    case PlayerAssets.active_home_with_blueprint(PrototypePlayer.id()) do
      %PlayerBiotope{
        biotope_id: biotope_id,
        source_blueprint: %ArkeonBlueprint{} = blueprint
      } ->
        params = blueprint_params(blueprint)

        %{
          biotope_id: biotope_id,
          blueprint_id: blueprint.id,
          params: params,
          preview: locked_preview(blueprint, params)
        }

      _ ->
        nil
    end
  end

  @spec can_provision_home?() :: boolean()
  def can_provision_home? do
    is_nil(PlayerAssets.active_home(PrototypePlayer.id()))
  end

  @spec owned_biotopes() :: [World.biotope_summary()]
  def owned_biotopes do
    World.list_biotopes(PrototypePlayer.id())
    |> Enum.filter(&(&1.ownership == :player_controlled))
  end

  @spec preview(map()) :: preview()
  def preview(params) when is_map(params) do
    spec = normalize_params(params)
    genome = build_genome(spec)
    build_preview(spec, genome)
  end

  @spec provision_home(map()) :: {:ok, binary()} | {:error, %{atom() => binary()}}
  def provision_home(params) when is_map(params) do
    spec = normalize_params(params)

    with :ok <- validate(spec),
         :ok <- ensure_home_slot_available() do
      do_provision(spec)
    end
  end

  defp do_provision(spec) do
    ecotype = starter_ecotype(spec.starter_archetype)
    {x, y} = World.spawn_coords(spec.starter_archetype)
    neighbors = candidate_neighbors(spec.starter_archetype, {x, y})
    phases = build_seed_phases(spec.starter_archetype)
    genome = build_genome(spec)
    lineage = build_seed_lineage(genome, phases)

    state =
      BiotopeState.new_from_opts(
        id: Arkea.UUID.v4(),
        archetype: spec.starter_archetype,
        x: x,
        y: y,
        zone: ecotype.zone,
        owner_player_id: PrototypePlayer.id(),
        neighbor_ids: Enum.map(neighbors, & &1.id),
        phases: phases,
        dilution_rate: mean_dilution(phases),
        lineages: [lineage],
        metabolite_inflow: inflow_profile(spec.starter_archetype)
      )

    with {:ok, _pid} <- BiotopeSupervisor.start_biotope(state),
         {:ok, _changes} <-
           PlayerAssets.register_home(PrototypePlayer.profile(), spec, genome, state) do
      _ = persist_seed_transition(state, lineage, spec)
      Phoenix.PubSub.broadcast(Arkea.PubSub, "world:registry", {:world_changed, state.id})
      {:ok, state.id}
    else
      {:error, operation, reason, _changes} ->
        stop_started_biotope(state.id)
        {:error, home_registration_error(operation, reason)}

      {:error, reason} ->
        stop_started_biotope(state.id)
        {:error, %{starter_archetype: "Could not provision home biotope: #{inspect(reason)}"}}
    end
  end

  defp persist_seed_transition(state, lineage, spec) do
    Store.persist_transition(
      state,
      [
        %{
          type: :intervention,
          payload: %{
            lineage_id: lineage.id,
            seed_name: spec.seed_name,
            starter_archetype: Atom.to_string(spec.starter_archetype),
            actor: PrototypePlayer.display_name(),
            actor_player_id: PrototypePlayer.id(),
            kind: "seed_provisioned"
          }
        }
      ],
      :seed
    )
  end

  defp validate(spec) do
    errors =
      %{}
      |> maybe_put_error(:seed_name, String.trim(spec.seed_name) == "", "Seed name is required.")
      |> maybe_put_error(
        :seed_name,
        String.length(spec.seed_name) > 40,
        "Seed name must stay within 40 characters."
      )

    if map_size(errors) == 0, do: :ok, else: {:error, errors}
  end

  defp ensure_home_slot_available do
    if can_provision_home?() do
      :ok
    else
      {:error, %{starter_archetype: "Prototype player already owns a home biotope."}}
    end
  end

  defp stop_started_biotope(id) do
    case Registry.lookup(Arkea.Sim.Registry, {:biotope, id}) do
      [{pid, _value}] when is_pid(pid) ->
        if Process.alive?(pid) do
          DynamicSupervisor.terminate_child(BiotopeSupervisor, pid)
        end

        :ok

      _ ->
        :ok
    end
  end

  defp home_registration_error(:player_biotope, reason), do: changeset_errors(reason)
  defp home_registration_error(:blueprint, reason), do: changeset_errors(reason)
  defp home_registration_error(:player, reason), do: changeset_errors(reason)
  defp home_registration_error(:biotope, reason), do: changeset_errors(reason)

  defp home_registration_error(_operation, _reason),
    do: %{starter_archetype: "Could not persist player home."}

  defp changeset_errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map(fn {field, [message | _rest]} -> {field, message} end)
    |> Map.new()
  end

  defp changeset_errors(_reason), do: %{starter_archetype: "Could not persist player home."}

  defp locked_preview(%ArkeonBlueprint{} = blueprint, params) do
    spec = normalize_params(params)

    case ArkeonBlueprint.load_genome(blueprint.genome_binary) do
      {:ok, genome} -> build_preview(spec, genome)
      _ -> build_preview(spec, build_genome(spec))
    end
  end

  defp build_preview(spec, %Genome{} = genome) do
    ecotype = starter_ecotype(spec.starter_archetype)
    phenotype = Phenotype.from_genome(genome)
    {x, y} = World.spawn_coords(spec.starter_archetype)
    neighbors = candidate_neighbors(spec.starter_archetype, {x, y})
    phase_names = spec.starter_archetype |> Biotope.default_phases() |> Enum.map(& &1.name)

    %{
      spec: spec,
      player: PrototypePlayer.profile(),
      ecotype: ecotype,
      phenotype: phenotype,
      genome: genome,
      gene_count: Genome.gene_count(genome),
      plasmid_count: length(genome.plasmids),
      prophage_count: length(genome.prophages),
      playstyle: playstyle_for(phenotype),
      modules: genome_manifest(genome),
      spawn_coords: {x, y},
      neighbor_ids: Enum.map(neighbors, & &1.id),
      phase_names: phase_names,
      phase_count: length(phase_names)
    }
  end

  defp build_seed_phases(archetype) do
    pool = starting_pool(archetype)

    archetype
    |> Biotope.default_phases()
    |> Enum.map(fn phase ->
      Enum.reduce(pool, phase, fn {metabolite, concentration}, acc ->
        Phase.update_metabolite(
          acc,
          metabolite,
          Float.round(concentration * phase_pool_factor(phase.name, metabolite), 2)
        )
      end)
    end)
  end

  defp build_seed_lineage(genome, phases) do
    abundances =
      phases
      |> Enum.map(fn phase -> {phase.name, phase_seed_weight(phase.name)} end)
      |> normalize_counts(420)

    Lineage.new_founder(genome, abundances, 0)
  end

  defp normalize_counts(weighted_phases, total) do
    total_weight = Enum.sum(Enum.map(weighted_phases, fn {_phase_name, weight} -> weight end))

    raw_counts =
      Enum.map(weighted_phases, fn {phase_name, weight} ->
        {phase_name, max(1, round(total * weight / total_weight))}
      end)

    delta = total - Enum.sum(Enum.map(raw_counts, fn {_phase_name, count} -> count end))

    case raw_counts do
      [{first_phase, count} | rest] -> Map.new([{first_phase, count + delta} | rest])
      [] -> %{}
    end
  end

  defp build_genome(spec) do
    chromosome_domains =
      [
        substrate_domain(spec.metabolism_profile),
        catalytic_domain(spec.metabolism_profile),
        energy_domain(spec.metabolism_profile, spec.membrane_profile),
        repair_domain(spec.regulation_profile)
      ] ++ membrane_domains(spec.membrane_profile) ++ regulation_domains(spec.regulation_profile)

    genome = Genome.new([Gene.from_domains(chromosome_domains)])

    case spec.mobile_module do
      "conjugative_plasmid" ->
        plasmid_gene =
          Gene.from_domains([
            Domain.new([0, 0, 2], List.duplicate(9, 20)),
            Domain.new([0, 0, 9], [0 | List.duplicate(8, 19)])
          ])

        Genome.add_plasmid(genome, [plasmid_gene])

      "latent_prophage" ->
        prophage_gene = Gene.from_domains([Domain.new([0, 0, 8], List.duplicate(6, 20))])
        Genome.integrate_prophage(genome, [prophage_gene])

      _ ->
        genome
    end
  end

  defp substrate_domain("thrifty"), do: Domain.new([0, 0, 0], [0 | List.duplicate(2, 19)])
  defp substrate_domain("balanced"), do: Domain.new([0, 0, 0], [0 | List.duplicate(5, 19)])
  defp substrate_domain("bloom"), do: Domain.new([0, 0, 0], [0 | List.duplicate(9, 19)])

  defp catalytic_domain("thrifty"), do: Domain.new([0, 0, 1], List.duplicate(7, 20))
  defp catalytic_domain("balanced"), do: Domain.new([0, 0, 1], List.duplicate(10, 20))
  defp catalytic_domain("bloom"), do: Domain.new([0, 0, 1], List.duplicate(13, 20))

  defp energy_domain("thrifty", "porous"), do: Domain.new([0, 1, 3], List.duplicate(4, 20))
  defp energy_domain("thrifty", _), do: Domain.new([0, 1, 3], List.duplicate(5, 20))
  defp energy_domain("balanced", "porous"), do: Domain.new([0, 1, 3], List.duplicate(5, 20))
  defp energy_domain("balanced", _), do: Domain.new([0, 1, 3], List.duplicate(6, 20))
  defp energy_domain("bloom", "porous"), do: Domain.new([0, 1, 3], List.duplicate(7, 20))
  defp energy_domain("bloom", _), do: Domain.new([0, 1, 3], List.duplicate(8, 20))

  defp repair_domain("steady"), do: Domain.new([0, 1, 9], List.duplicate(11, 20))
  defp repair_domain("responsive"), do: Domain.new([0, 1, 9], List.duplicate(8, 20))
  defp repair_domain("mutator"), do: Domain.new([0, 1, 9], List.duplicate(2, 20))

  defp membrane_domains("porous") do
    [Domain.new([0, 0, 2], List.duplicate(4, 20))]
  end

  defp membrane_domains("fortified") do
    [
      Domain.new([0, 0, 2], List.duplicate(8, 20)),
      Domain.new([0, 0, 8], List.duplicate(11, 20))
    ]
  end

  defp membrane_domains("salinity_tuned") do
    [
      Domain.new([0, 0, 2], List.duplicate(10, 20)),
      Domain.new([0, 0, 2], List.duplicate(7, 20))
    ]
  end

  defp regulation_domains("steady"), do: []

  defp regulation_domains("responsive") do
    [
      Domain.new([0, 0, 5], List.duplicate(12, 20)),
      Domain.new([0, 3, 4], List.duplicate(10, 20))
    ]
  end

  defp regulation_domains("mutator") do
    [Domain.new([0, 0, 5], List.duplicate(7, 20))]
  end

  defp genome_manifest(%Genome{} = genome) do
    chromosome =
      Enum.with_index(genome.chromosome, 1)
      |> Enum.map(fn {gene, index} ->
        %{
          scope: "Chromosome",
          label: "Core cassette #{index}",
          domains: Enum.map(gene.domains, &domain_label(&1.type))
        }
      end)

    plasmids =
      Enum.with_index(genome.plasmids, 1)
      |> Enum.map(fn {genes, index} ->
        %{
          scope: "Plasmid",
          label: "Mobile plasmid #{index}",
          domains:
            genes
            |> List.flatten()
            |> Enum.flat_map(&Enum.map(&1.domains, fn d -> domain_label(d.type) end))
        }
      end)

    prophages =
      Enum.with_index(genome.prophages, 1)
      |> Enum.map(fn {genes, index} ->
        %{
          scope: "Prophage",
          label: "Latent cassette #{index}",
          domains:
            genes
            |> List.flatten()
            |> Enum.flat_map(&Enum.map(&1.domains, fn d -> domain_label(d.type) end))
        }
      end)

    chromosome ++ plasmids ++ prophages
  end

  defp candidate_neighbors(archetype, {x, y}) do
    zone = starter_ecotype(archetype).zone

    World.list_biotopes()
    |> Enum.sort_by(fn biotope ->
      zone_penalty(biotope.zone, zone) + distance({biotope.display_x, biotope.display_y}, {x, y})
    end)
    |> Enum.take(3)
  end

  defp starting_pool(:eutrophic_pond) do
    %{glucose: 20.0, oxygen: 10.0, nh3: 4.0, po4: 2.0, co2: 5.0}
  end

  defp starting_pool(:oligotrophic_lake) do
    %{glucose: 8.0, oxygen: 14.0, nh3: 2.0, po4: 1.0, co2: 4.0}
  end

  defp starting_pool(:mesophilic_soil) do
    %{glucose: 12.0, acetate: 6.0, oxygen: 8.0, nh3: 3.0, po4: 1.5, co2: 4.0}
  end

  defp inflow_profile(:eutrophic_pond) do
    %{glucose: 10.0, oxygen: 5.0, nh3: 2.0, po4: 1.0}
  end

  defp inflow_profile(:oligotrophic_lake) do
    %{glucose: 4.0, oxygen: 7.0, nh3: 1.0, po4: 0.5}
  end

  defp inflow_profile(:mesophilic_soil) do
    %{glucose: 6.0, acetate: 2.0, oxygen: 4.0, nh3: 1.5, po4: 0.7}
  end

  defp phase_pool_factor(phase_name, :oxygen)
       when phase_name in [:sediment, :wet_clump, :peat_core, :bulk_sediment, :marine_layer],
       do: 0.25

  defp phase_pool_factor(phase_name, :glucose)
       when phase_name in [:sediment, :wet_clump, :peat_core, :bulk_sediment],
       do: 1.25

  defp phase_pool_factor(_phase_name, _metabolite), do: 1.0

  defp phase_seed_weight(:surface), do: 1.0
  defp phase_seed_weight(:water_column), do: 1.2
  defp phase_seed_weight(:sediment), do: 0.4
  defp phase_seed_weight(:aerated_pore), do: 0.95
  defp phase_seed_weight(:wet_clump), do: 0.7
  defp phase_seed_weight(:soil_water), do: 1.0
  defp phase_seed_weight(:freshwater_layer), do: 1.0
  defp phase_seed_weight(:mixing_zone), do: 0.8
  defp phase_seed_weight(:marine_layer), do: 0.5
  defp phase_seed_weight(_phase_name), do: 0.85

  defp starter_ecotype(archetype) when is_atom(archetype) do
    Enum.find(@starter_ecotypes, &(&1.archetype == archetype))
  end

  defp starter_ecotype(archetype) when is_binary(archetype) do
    Enum.find(@starter_ecotypes, &(&1.id == archetype))
  end

  defp domain_label(type) when is_atom(type) do
    type
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp playstyle_for(%Phenotype{} = phenotype) do
    cond do
      phenotype.repair_efficiency <= 0.12 ->
        "Mutator explorer"

      phenotype.n_transmembrane >= 2 and phenotype.structural_stability >= 0.45 ->
        "Envelope-heavy expansionist"

      phenotype.base_growth_rate >= 0.45 and phenotype.energy_cost >= 1.0 ->
        "Fast bloom opportunist"

      true ->
        "Generalist colonizer"
    end
  end

  defp blueprint_params(%ArkeonBlueprint{} = blueprint) do
    form_defaults()
    |> Map.merge(Map.new(blueprint.phenotype_spec || %{}))
    |> Map.merge(%{
      "seed_name" => blueprint.name,
      "starter_archetype" => blueprint.starter_archetype
    })
  end

  defp normalize_params(params) do
    merged = Map.merge(@defaults, Map.new(params))
    starter = safe_option_id(merged["starter_archetype"], @starter_ecotypes, "eutrophic_pond")
    metabolism = safe_option_id(merged["metabolism_profile"], @metabolism_profiles, "balanced")
    membrane = safe_option_id(merged["membrane_profile"], @membrane_profiles, "porous")
    regulation = safe_option_id(merged["regulation_profile"], @regulation_profiles, "responsive")
    mobile = safe_option_id(merged["mobile_module"], @mobile_modules, "none")

    %{
      seed_name: merged["seed_name"] |> to_string() |> String.trim(),
      starter_archetype: starter |> starter_ecotype() |> Map.fetch!(:archetype),
      metabolism_profile: metabolism,
      membrane_profile: membrane,
      regulation_profile: regulation,
      mobile_module: mobile
    }
  end

  defp safe_option_id(candidate, options, fallback) when is_binary(candidate) do
    if Enum.any?(options, &(&1.id == candidate)), do: candidate, else: fallback
  end

  defp maybe_put_error(errors, _field, false, _message), do: errors
  defp maybe_put_error(errors, field, true, message), do: Map.put(errors, field, message)

  defp zone_penalty(zone, zone), do: 0.0
  defp zone_penalty(_other, _expected), do: 40.0

  defp distance({x1, y1}, {x2, y2}) do
    :math.sqrt(:math.pow(x1 - x2, 2) + :math.pow(y1 - y2, 2))
  end

  defp mean_dilution(phases) do
    Enum.sum(Enum.map(phases, & &1.dilution_rate)) / max(length(phases), 1)
  end
end
