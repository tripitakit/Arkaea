defmodule Arkea.Game.SeedLab do
  @moduledoc """
  Seed-builder and explicit home-biotope provisioning flow.

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
  alias Arkea.Genome.Domain.Type, as: DomainType
  alias Arkea.Genome.Gene
  alias Arkea.Persistence.ArkeonBlueprint
  alias Arkea.Persistence.PlayerBiotope
  alias Arkea.Persistence.Store
  alias Arkea.Repo
  alias Arkea.Sim.Biotope.Server, as: BiotopeServer
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
    },
    %{
      id: "saline_estuary",
      archetype: :saline_estuary,
      label: "Saline estuary",
      strapline: "Tidal salinity gradient; rewards halotolerant envelopes and ion-handling.",
      zone: :coastal_zone
    },
    %{
      id: "marine_sediment",
      archetype: :marine_sediment,
      label: "Marine sediment",
      strapline: "Steep redox gradient, sulfate-reducer niches, slow turnover sea-floor zone.",
      zone: :marine_zone
    },
    %{
      id: "methanogenic_bog",
      archetype: :methanogenic_bog,
      label: "Methanogenic bog",
      strapline: "Anoxic, low-pH, H₂-driven; archaeon-favouring methanogenic wetland.",
      zone: :swampy_zone
    },
    %{
      id: "hydrothermal_vent",
      archetype: :hydrothermal_vent,
      label: "Hydrothermal vent",
      strapline:
        "Sharp thermal/redox gradients, sulfide-rich; thermophile + chemolithotroph play.",
      zone: :hydrothermal_zone
    },
    %{
      id: "acid_mine_drainage",
      archetype: :acid_mine_drainage,
      label: "Acid mine drainage",
      strapline: "Extreme low-pH, Fe²⁺/Fe³⁺ cycling; acidophile + iron-oxidiser niches.",
      zone: :hydrothermal_zone
    }
  ]

  # Maximum number of home biotopes a player can hold simultaneously.
  # Lifted from 1 to 3 to allow strategic colonisation across distinct
  # niches without committing the whole roster in a single shot.
  @max_homes 3

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

  @domain_palette [
    %{
      id: "substrate_binding",
      label: "Substrate binding",
      description: "Defines target metabolite affinity and breadth.",
      runtime: :active
    },
    %{
      id: "catalytic_site",
      label: "Catalytic site",
      description: "Adds catalytic turnover and reaction class.",
      runtime: :active
    },
    %{
      id: "transmembrane_anchor",
      label: "Transmembrane anchor",
      description: "Adds membrane insertion and pass count.",
      runtime: :active
    },
    %{
      id: "channel_pore",
      label: "Channel / pore",
      description: "Encodes transport selectivity and gating threshold.",
      runtime: :latent
    },
    %{
      id: "energy_coupling",
      label: "Energy coupling",
      description: "Defines ATP cost and proton-motive coupling.",
      runtime: :active
    },
    %{
      id: "dna_binding",
      label: "DNA binding",
      description: "Controls promoter affinity and sigma coupling.",
      runtime: :active
    },
    %{
      id: "regulator_output",
      label: "Regulator output",
      description: "Stores activator/repressor output logic for regulatory programs.",
      runtime: :latent
    },
    %{
      id: "ligand_sensor",
      label: "Ligand sensor",
      description: "Adds metabolite or signal sensing thresholds.",
      runtime: :active
    },
    %{
      id: "structural_fold",
      label: "Structural fold",
      description: "Adds stability and multimerization support.",
      runtime: :active
    },
    %{
      id: "surface_tag",
      label: "Surface tag",
      description: "Carries pilus/phage/surface identity tags.",
      runtime: :active
    },
    %{
      id: "repair_fidelity",
      label: "Repair / fidelity",
      description: "Tunes mismatch repair and mutator pressure.",
      runtime: :active
    }
  ]

  @intergenic_palette %{
    expression: [
      %{
        id: "sigma_promoter",
        label: "Sigma promoter",
        description: "Basal promoter block for expression gating."
      },
      %{
        id: "multi_sigma_operator",
        label: "Multi-sigma operator",
        description: "Overlapping operator logic for combinatorial expression."
      },
      %{
        id: "metabolite_riboswitch",
        label: "Metabolite riboswitch",
        description: "Ligand-responsive translation gate in the regulatory block."
      }
    ],
    transfer: [
      %{
        id: "orit_site",
        label: "oriT site",
        description: "Marks a transfer initiation hotspot for future mobility logic."
      },
      %{
        id: "integration_hotspot",
        label: "Integration hotspot",
        description: "Marks an insertion/landing site for future mobile-element routing."
      }
    ],
    duplication: [
      %{
        id: "repeat_array",
        label: "Repeat array",
        description: "Repetitive intergenic sequence biasing local duplications."
      },
      %{
        id: "duplication_hotspot",
        label: "Duplication hotspot",
        description: "Marks a local locus for copy-and-expand events."
      }
    ]
  }

  @defaults %{
    "seed_name" => "",
    "starter_archetype" => "",
    "metabolism_profile" => "balanced",
    "membrane_profile" => "porous",
    "regulation_profile" => "responsive",
    "mobile_module" => "none",
    "custom_gene_payload" => "[]",
    "custom_plasmid_payload" => "[]"
  }

  @type preview :: %{
          spec: map(),
          player: %{id: binary(), display_name: binary()},
          ecotype: map(),
          phenotype: Phenotype.t(),
          genome: Genome.t(),
          gene_count: non_neg_integer(),
          chromosome_gene_count: non_neg_integer(),
          custom_gene_count: non_neg_integer(),
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

  @spec domain_palette() :: [map()]
  def domain_palette, do: @domain_palette

  @spec intergenic_palette() :: %{required(atom()) => [map()]}
  def intergenic_palette, do: @intergenic_palette

  @spec locked_seed() ::
          %{
            biotope_id: binary(),
            blueprint_id: binary(),
            params: map(),
            preview: preview()
          }
          | nil
  def locked_seed do
    locked_seed(PrototypePlayer.profile())
  end

  @spec locked_seed(%{id: binary()} | binary()) ::
          %{
            biotope_id: binary(),
            blueprint_id: binary(),
            params: map(),
            preview: preview()
          }
          | nil
  def locked_seed(player_or_id) do
    player_profile = normalize_player_profile(player_or_id)

    case PlayerAssets.active_home_with_blueprint(player_profile.id) do
      %PlayerBiotope{
        biotope_id: biotope_id,
        source_blueprint: %ArkeonBlueprint{} = blueprint
      } ->
        params = blueprint_params(blueprint)

        %{
          biotope_id: biotope_id,
          blueprint_id: blueprint.id,
          params: params,
          preview: locked_preview(blueprint, params, player_profile)
        }

      _ ->
        nil
    end
  end

  @doc "Maximum number of home biotopes a player can hold simultaneously."
  @spec max_homes() :: pos_integer()
  def max_homes, do: @max_homes

  @spec can_provision_home?() :: boolean()
  def can_provision_home?, do: can_provision_home?(PrototypePlayer.profile())

  @spec can_provision_home?(%{id: binary()} | binary()) :: boolean()
  def can_provision_home?(player_or_id) do
    PlayerAssets.home_count(player_id(player_or_id)) < @max_homes
  end

  @doc """
  Number of home biotopes the player currently holds (0..@max_homes).
  """
  @spec home_count(%{id: binary()} | binary()) :: non_neg_integer()
  def home_count(player_or_id) do
    PlayerAssets.home_count(player_id(player_or_id))
  end

  @doc """
  Map a `biotope_id` to the player's locked seed for that specific home,
  or `nil` if the biotope is not registered as a home of the player.
  """
  @spec locked_seed_for(%{id: binary()} | binary(), binary()) ::
          %{biotope_id: binary(), blueprint_id: binary(), params: map(), preview: preview()}
          | nil
  def locked_seed_for(player_or_id, biotope_id) when is_binary(biotope_id) do
    player_profile = normalize_player_profile(player_or_id)

    case PlayerAssets.home_for_biotope(player_profile.id, biotope_id) do
      %PlayerBiotope{
        biotope_id: ^biotope_id,
        source_blueprint: %ArkeonBlueprint{} = blueprint
      } ->
        params = blueprint_params(blueprint)

        %{
          biotope_id: biotope_id,
          blueprint_id: blueprint.id,
          params: params,
          preview: locked_preview(blueprint, params, player_profile)
        }

      _ ->
        nil
    end
  end

  @spec owned_biotopes() :: [World.biotope_summary()]
  def owned_biotopes, do: owned_biotopes(PrototypePlayer.profile())

  @spec owned_biotopes(%{id: binary()} | binary()) :: [World.biotope_summary()]
  def owned_biotopes(player_or_id) do
    World.list_biotopes(player_id(player_or_id))
    |> Enum.filter(&(&1.ownership == :player_controlled))
  end

  @spec preview(map()) :: preview()
  def preview(params) when is_map(params), do: preview(params, PrototypePlayer.profile())

  @spec preview(map(), %{id: binary(), display_name: binary()} | binary()) :: preview()
  def preview(params, player_or_profile) when is_map(params) do
    spec = normalize_params(params)
    genome = build_genome(spec)
    build_preview(spec, genome, normalize_player_profile(player_or_profile))
  end

  @spec provision_home(map()) :: {:ok, binary()} | {:error, %{atom() => binary()}}
  def provision_home(params) when is_map(params),
    do: provision_home(PrototypePlayer.profile(), params)

  @spec provision_home(%{id: binary(), display_name: binary(), email: binary()}, map()) ::
          {:ok, binary()} | {:error, %{atom() => binary()}}
  def provision_home(player_profile, params) when is_map(player_profile) and is_map(params) do
    spec = normalize_params(params)
    player_profile = normalize_player_profile(player_profile)

    with :ok <- validate(spec),
         :ok <- ensure_home_slot_available(player_profile.id) do
      do_provision(player_profile, spec)
    end
  end

  @doc """
  Re-inoculate the player's home biotope with a fresh founder lineage built
  from the locked blueprint.

  Allowed only when the running biotope is **extinct**
  (`BiotopeState.total_abundance(state) == 0`). Returns `{:error, :no_home}`
  when the player has not yet provisioned, `{:error, :biotope_missing}` when
  the registered biotope is no longer running, `{:error, :not_extinct}`
  when the population is still alive, or `{:error, :blueprint_unreadable}`
  when the persisted genome cannot be decoded.
  """
  @spec recolonize_home(%{id: binary()} | binary(), binary() | nil) ::
          {:ok, %{biotope_id: binary(), lineage_id: binary(), tick: non_neg_integer()}}
          | {:error, atom()}
  def recolonize_home(player_or_id, biotope_id \\ nil)

  def recolonize_home(player_or_id, biotope_id) do
    player_profile = normalize_player_profile(player_or_id)

    with %{biotope_id: target_id, blueprint_id: _, params: params} <-
           lookup_locked_seed(player_profile, biotope_id) || :no_home,
         %BiotopeState{} = state <- safe_get_state(target_id),
         :ok <- ensure_extinct(state),
         {:ok, genome} <- load_genome_for_home(player_profile.id, target_id) do
      spec = normalize_params(params)
      lineage = build_seed_lineage(genome, state.phases)

      case BiotopeServer.recolonize(target_id, lineage,
             actor: player_profile.display_name,
             actor_player_id: player_profile.id,
             seed_name: spec.seed_name
           ) do
        {:ok, %{tick: tick}} ->
          Phoenix.PubSub.broadcast(
            Arkea.PubSub,
            "world:registry",
            {:world_changed, target_id}
          )

          {:ok, %{biotope_id: target_id, lineage_id: lineage.id, tick: tick}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      :no_home -> {:error, :no_home}
      nil -> {:error, :biotope_missing}
      {:error, _} = err -> err
    end
  end

  @doc """
  Re-inoculate the home biotope with a *modified* seed.

  The player can change every spec field except the `starter_archetype`,
  which is locked to the existing biotope's archetype (the running biotope
  has phases / zone / coords already shaped by it; allowing a change would
  effectively be a brand-new biotope, not a recolonization).

  Returns `{:ok, ...}` on success, or one of the same error atoms returned
  by `recolonize_home/1` plus `{:error, %{...}}` for spec validation
  errors and `{:error, :archetype_mismatch}` if the supplied params try to
  change the archetype.
  """
  @spec recolonize_home_with_spec(%{id: binary()} | binary(), map()) ::
          {:ok,
           %{
             biotope_id: binary(),
             lineage_id: binary(),
             tick: non_neg_integer(),
             blueprint_id: binary()
           }}
          | {:error, atom() | %{atom() => binary()}}
  def recolonize_home_with_spec(player_or_id, params, biotope_id \\ nil)
      when is_map(params) and (is_binary(biotope_id) or is_nil(biotope_id)) do
    player_profile = normalize_player_profile(player_or_id)
    spec = normalize_params(params)

    with %{biotope_id: target_id} = locked <-
           lookup_locked_seed(player_profile, biotope_id) || :no_home,
         %BiotopeState{} = state <- safe_get_state(target_id),
         :ok <- ensure_extinct(state),
         :ok <- validate(spec),
         :ok <- ensure_archetype_unchanged(spec, locked),
         {:ok, %{blueprint: blueprint, player_biotope: _}} <-
           PlayerAssets.register_home_recolonization(
             target_id,
             player_profile,
             spec,
             build_genome(spec)
           ) do
      genome = build_genome(spec)
      lineage = build_seed_lineage(genome, state.phases)

      case BiotopeServer.recolonize(target_id, lineage,
             actor: player_profile.display_name,
             actor_player_id: player_profile.id,
             seed_name: spec.seed_name,
             blueprint_id: blueprint.id,
             with_edit: true
           ) do
        {:ok, %{tick: tick}} ->
          Phoenix.PubSub.broadcast(
            Arkea.PubSub,
            "world:registry",
            {:world_changed, target_id}
          )

          {:ok,
           %{
             biotope_id: target_id,
             lineage_id: lineage.id,
             tick: tick,
             blueprint_id: blueprint.id
           }}

        {:error, reason} ->
          {:error, reason}
      end
    else
      :no_home -> {:error, :no_home}
      nil -> {:error, :biotope_missing}
      {:error, %Ecto.Changeset{}} -> {:error, :blueprint_persist_failed}
      {:error, _, _, _} -> {:error, :blueprint_persist_failed}
      {:error, _} = err -> err
    end
  end

  # When a biotope id is supplied, look up that specific home's locked seed;
  # otherwise fall back to the most-recently provisioned home (legacy
  # single-home callers).
  defp lookup_locked_seed(player_profile, nil), do: locked_seed(player_profile)

  defp lookup_locked_seed(player_profile, biotope_id) when is_binary(biotope_id) do
    locked_seed_for(player_profile, biotope_id)
  end

  defp ensure_archetype_unchanged(spec, %{params: locked_params}) do
    locked_archetype =
      locked_params
      |> Map.get("starter_archetype")
      |> normalize_archetype()

    if Atom.to_string(spec.starter_archetype) == Atom.to_string(locked_archetype) do
      :ok
    else
      {:error, :archetype_mismatch}
    end
  end

  defp normalize_archetype(nil), do: :unknown
  defp normalize_archetype(""), do: :unknown
  defp normalize_archetype(value) when is_atom(value), do: value

  defp normalize_archetype(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> :unknown
  end

  @doc """
  True when the player owns the home with the given `biotope_id` and the
  biotope is currently extinct (`total_abundance == 0`). When `biotope_id`
  is omitted, the most recently provisioned home is checked. Used by the
  UI to gate the "Recolonize home" affordance.
  """
  @spec home_extinct?(%{id: binary()} | binary(), binary() | nil) :: boolean()
  def home_extinct?(player_or_id, biotope_id \\ nil) do
    case lookup_locked_seed(normalize_player_profile(player_or_id), biotope_id) do
      %{biotope_id: id} ->
        case safe_get_state(id) do
          %BiotopeState{} = state -> BiotopeState.total_abundance(state) == 0
          _ -> false
        end

      _ ->
        false
    end
  end

  defp safe_get_state(biotope_id) do
    BiotopeServer.get_state(biotope_id)
  rescue
    _ -> nil
  end

  defp ensure_extinct(%BiotopeState{} = state) do
    if BiotopeState.total_abundance(state) == 0 do
      :ok
    else
      {:error, :not_extinct}
    end
  end

  # Load the persisted genome for a specific home biotope (per-biotope
  # blueprint, supports multi-home rosters).
  defp load_genome_for_home(player_id, biotope_id) do
    case PlayerAssets.home_for_biotope(player_id, biotope_id) do
      %PlayerBiotope{source_blueprint: %ArkeonBlueprint{} = blueprint} ->
        case ArkeonBlueprint.load_genome(blueprint.genome_binary) do
          {:ok, genome} -> {:ok, genome}
          _ -> {:error, :blueprint_unreadable}
        end

      _ ->
        {:error, :no_home}
    end
  end

  @doc """
  Provision a single biotope colonised simultaneously by 1-3 distinct
  Arkeon seeds (community mode).

  All founders share the same `starter_archetype` (they're inhabiting
  the same biotope). The first spec is the **primary**: its blueprint
  is the one bound to the `player_biotope` row and surfaced in the
  Seed Lab when the player re-opens the home. The 2nd and 3rd specs
  are persisted as auxiliary `arkeon_blueprints` rows (no
  `player_biotope` link) — they remain recoverable via the
  `:community_provisioned` audit event payload.

  Cross-feeding emerges naturally from `Metabolism.compute_byproducts`:
  each consumed substrate releases stoichiometric by-products into the
  shared `phase.metabolite_pool`, so a community whose seed cassettes
  bind complementary substrates forms a chemo-trophic network without
  any extra wiring.

  Returns `{:ok, biotope_id}` or `{:error, %{atom => String.t()}}` /
  atom on validation / persistence failure.
  """
  @spec provision_community(map() | binary(), [map()]) ::
          {:ok, binary()} | {:error, term()}
  def provision_community(player_or_id, params_list) when is_list(params_list) do
    player_profile = normalize_player_profile(player_or_id)
    specs = Enum.map(params_list, &normalize_params/1)

    cond do
      specs == [] ->
        {:error, %{starter_archetype: "Provide at least one founder seed."}}

      length(specs) > 3 ->
        {:error, %{starter_archetype: "Community mode allows at most 3 founder seeds."}}

      not all_valid?(specs) ->
        {:error, validate_first_invalid(specs)}

      not same_archetype?(specs) ->
        {:error,
         %{
           starter_archetype: "All community founders must share the same biotope archetype."
         }}

      true ->
        with :ok <- ensure_home_slot_available(player_profile.id) do
          do_provision_community(player_profile, specs)
        end
    end
  end

  defp all_valid?(specs), do: Enum.all?(specs, &(validate(&1) == :ok))

  defp validate_first_invalid(specs) do
    case Enum.find(specs, fn s -> match?({:error, _}, validate(s)) end) do
      nil -> %{}
      bad -> elem(validate(bad), 1)
    end
  end

  defp same_archetype?([]), do: true

  defp same_archetype?([first | rest]) do
    Enum.all?(rest, &(&1.starter_archetype == first.starter_archetype))
  end

  defp do_provision_community(player_profile, specs) do
    [primary_spec | _] = specs
    ecotype = starter_ecotype(primary_spec.starter_archetype)
    {x, y} = World.spawn_coords(primary_spec.starter_archetype)
    neighbors = candidate_neighbors(primary_spec.starter_archetype, {x, y})
    phases = build_seed_phases(primary_spec.starter_archetype)

    # Each founder gets its own genome and its own lineage tagged with
    # an `original_seed_id` so audit / cladistic tooling can later
    # tell the founders apart even after speciation.
    founders =
      Enum.map(specs, fn spec ->
        seed_id = Arkea.UUID.v4()
        genome = build_genome(spec)
        lineage = build_seed_lineage(genome, phases)
        lineage = %{lineage | original_seed_id: seed_id}
        %{spec: spec, genome: genome, lineage: lineage, seed_id: seed_id}
      end)

    state =
      BiotopeState.new_from_opts(
        id: Arkea.UUID.v4(),
        archetype: primary_spec.starter_archetype,
        x: x,
        y: y,
        zone: ecotype.zone,
        owner_player_id: player_profile.id,
        neighbor_ids: Enum.map(neighbors, & &1.id),
        phases: phases,
        dilution_rate: mean_dilution(phases),
        lineages: Enum.map(founders, & &1.lineage),
        metabolite_inflow: inflow_profile(primary_spec.starter_archetype)
      )

    primary = hd(founders)

    with {:ok, _pid} <- BiotopeSupervisor.start_biotope(state),
         {:ok, _changes} <-
           PlayerAssets.register_home(
             player_profile,
             primary.spec,
             primary.genome,
             state
           ),
         :ok <- persist_auxiliary_founders(player_profile, founders, state) do
      _ = persist_community_transition(state, founders, player_profile)
      Phoenix.PubSub.broadcast(Arkea.PubSub, "world:registry", {:world_changed, state.id})
      {:ok, state.id}
    else
      {:error, operation, reason, _changes} ->
        stop_started_biotope(state.id)
        {:error, home_registration_error(operation, reason)}

      {:error, reason} ->
        stop_started_biotope(state.id)

        {:error,
         %{starter_archetype: "Could not provision community biotope: #{inspect(reason)}"}}
    end
  end

  # Each non-primary founder lands as a standalone ArkeonBlueprint row
  # (player_id set, no PlayerBiotope link). Failure of any insert
  # rolls back the whole community via {:error, _}.
  defp persist_auxiliary_founders(player_profile, [_primary | rest], _state) do
    Enum.reduce_while(rest, :ok, fn founder, :ok ->
      attrs = %{
        player_id: player_profile.id,
        name: founder.spec.seed_name,
        starter_archetype: Atom.to_string(founder.spec.starter_archetype),
        phenotype_spec: PlayerAssets.public_blueprint_spec(founder.spec),
        genome_binary: ArkeonBlueprint.dump_genome!(founder.genome)
      }

      case Repo.insert(ArkeonBlueprint.changeset(%ArkeonBlueprint{}, attrs)) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp persist_auxiliary_founders(_player_profile, [], _state), do: :ok

  defp persist_community_transition(state, founders, player_profile) do
    seed_ids = Enum.map(founders, & &1.seed_id)
    seed_names = Enum.map(founders, & &1.spec.seed_name)
    founder_lineage_ids = Enum.map(founders, & &1.lineage.id)

    payload = %{
      seed_ids: seed_ids,
      seed_names: seed_names,
      founder_lineage_ids: founder_lineage_ids,
      phase_name: state.phases |> hd() |> Map.get(:name) |> Atom.to_string(),
      biotope_id: state.id,
      tick: state.tick_count,
      actor_player_id: player_profile.id,
      actor: player_profile.display_name,
      kind: "community_provisioned"
    }

    Store.persist_transition(
      state,
      [%{type: :community_provisioned, payload: payload}],
      :seed
    )
  end

  defp do_provision(player_profile, spec) do
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
        owner_player_id: player_profile.id,
        neighbor_ids: Enum.map(neighbors, & &1.id),
        phases: phases,
        dilution_rate: mean_dilution(phases),
        lineages: [lineage],
        metabolite_inflow: inflow_profile(spec.starter_archetype)
      )

    with {:ok, _pid} <- BiotopeSupervisor.start_biotope(state),
         {:ok, _changes} <-
           PlayerAssets.register_home(player_profile, spec, genome, state) do
      _ = persist_seed_transition(state, lineage, spec, player_profile)
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

  defp persist_seed_transition(state, lineage, spec, player_profile) do
    Store.persist_transition(
      state,
      [
        %{
          type: :intervention,
          payload: %{
            lineage_id: lineage.id,
            seed_name: spec.seed_name,
            starter_archetype: Atom.to_string(spec.starter_archetype),
            actor: player_profile.display_name,
            actor_player_id: player_profile.id,
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
        :starter_archetype,
        not spec.starter_selected?,
        "Choose the first biotope to colonize."
      )
      |> maybe_put_error(
        :seed_name,
        String.length(spec.seed_name) > 40,
        "Seed name must stay within 40 characters."
      )

    if map_size(errors) == 0, do: :ok, else: {:error, errors}
  end

  defp ensure_home_slot_available(player_id) do
    if can_provision_home?(player_id) do
      :ok
    else
      {:error, %{starter_archetype: "This player already owns a home biotope."}}
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

  defp locked_preview(%ArkeonBlueprint{} = blueprint, params, player_profile) do
    spec = normalize_params(params)

    case ArkeonBlueprint.load_genome(blueprint.genome_binary) do
      {:ok, genome} -> build_preview(spec, genome, player_profile)
      _ -> build_preview(spec, build_genome(spec), player_profile)
    end
  end

  defp build_preview(spec, %Genome{} = genome, player_profile) do
    ecotype = starter_ecotype(spec.starter_archetype)
    phenotype = Phenotype.from_genome(genome)
    {x, y} = World.spawn_coords(spec.starter_archetype)
    neighbors = candidate_neighbors(spec.starter_archetype, {x, y})
    phase_names = spec.starter_archetype |> Biotope.default_phases() |> Enum.map(& &1.name)

    %{
      spec: spec,
      player: player_profile,
      ecotype: ecotype,
      phenotype: phenotype,
      genome: genome,
      gene_count: Genome.gene_count(genome),
      chromosome_gene_count: length(genome.chromosome),
      custom_gene_count: length(spec.custom_genes),
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

  defp normalize_player_profile(%{id: id, display_name: display_name, email: email})
       when is_binary(id) and is_binary(display_name) and is_binary(email) do
    %{id: id, display_name: display_name, email: email}
  end

  defp normalize_player_profile(player_id) when is_binary(player_id) do
    %{id: player_id, display_name: "Player", email: "player@arkea.local"}
  end

  defp player_id(%{id: id}) when is_binary(id), do: id
  defp player_id(id) when is_binary(id), do: id

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

    genome =
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

    genome
    |> append_custom_genes(spec.custom_genes)
    |> append_custom_plasmid(Map.get(spec, :custom_plasmid_genes, []))
  end

  defp append_custom_genes(%Genome{} = genome, []), do: genome

  defp append_custom_genes(%Genome{} = genome, custom_genes) when is_list(custom_genes) do
    extra_genes = Enum.map(custom_genes, &build_custom_gene/1)

    Genome.new(genome.chromosome ++ extra_genes,
      plasmids: genome.plasmids,
      prophages: genome.prophages
    )
  end

  defp append_custom_plasmid(%Genome{} = genome, []), do: genome
  defp append_custom_plasmid(%Genome{} = genome, nil), do: genome

  defp append_custom_plasmid(%Genome{} = genome, custom_plasmid_genes)
       when is_list(custom_plasmid_genes) do
    plasmid_genes = Enum.map(custom_plasmid_genes, &build_custom_gene/1)

    if plasmid_genes == [] do
      genome
    else
      Genome.add_plasmid(genome, plasmid_genes)
    end
  end

  defp build_custom_gene(spec) when is_map(spec) do
    domains =
      spec
      |> Map.get(:domains, [])
      |> Enum.map(&template_domain/1)

    intergenic_blocks =
      spec
      |> Map.get(:intergenic, %{})
      |> normalize_intergenic_blocks()

    Gene.from_domains(domains)
    |> Map.put(:intergenic_blocks, intergenic_blocks)
  end

  # Two wire shapes are accepted for a custom-gene domain entry:
  #
  #   - bare string `"substrate_binding"` (legacy) — every codon
  #     stays at the default template value;
  #   - map `%{type: "substrate_binding", params: %{...}}` — the
  #     `Arkea.Game.SeedLab.DomainEditor` overrides the relevant
  #     codons so the user-selected param materialises in the
  #     simulation (target_metabolite for substrate binding,
  #     reaction_class for catalytic site, etc.).
  defp template_domain(type_id) when is_binary(type_id) do
    template_domain(%{type: type_id, params: %{}})
  end

  defp template_domain(%{type: type_id} = entry) when is_binary(type_id) do
    type = domain_type_from_id(type_id)
    index = Enum.find_index(DomainType.all(), &(&1 == type))
    type_tag = [0, 0, index]

    default_codons = default_codons_for(type)
    params = entry |> Map.get(:params, %{}) |> stringify_string_keys()

    parameter_codons =
      Arkea.Game.SeedLab.DomainEditor.override_codons(type_id, default_codons, params)

    Domain.new(type_tag, parameter_codons)
  end

  defp default_codons_for(type) do
    case type do
      :substrate_binding -> [0 | List.duplicate(4, 19)]
      :catalytic_site -> List.duplicate(9, 20)
      :transmembrane_anchor -> List.duplicate(7, 20)
      :channel_pore -> List.duplicate(6, 20)
      :energy_coupling -> List.duplicate(5, 20)
      :dna_binding -> List.duplicate(10, 20)
      :regulator_output -> List.duplicate(8, 20)
      :ligand_sensor -> List.duplicate(11, 20)
      :structural_fold -> List.duplicate(12, 20)
      :surface_tag -> List.duplicate(13, 20)
      :repair_fidelity -> List.duplicate(9, 20)
    end
  end

  defp stringify_string_keys(params) when is_map(params) do
    Map.new(params, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp stringify_string_keys(_), do: %{}

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
      |> Enum.map(fn {plasmid, index} ->
        %{
          scope: "Plasmid",
          label: "Mobile plasmid #{index}",
          domains:
            plasmid.genes
            |> List.flatten()
            |> Enum.flat_map(&Enum.map(&1.domains, fn d -> domain_label(d.type) end))
        }
      end)

    prophages =
      Enum.with_index(genome.prophages, 1)
      |> Enum.map(fn {prophage, index} ->
        %{
          scope: "Prophage",
          label: "Latent cassette #{index}",
          domains:
            prophage.genes
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

  # Note (calibration, 2026-05-05): the new "extreme" archetypes are
  # biologically dominated by sulphur / iron / hydrogen chemistry, but
  # the default `balanced` / `thrifty` / `bloom` substrate-binding
  # cassettes only target glucose. Until the metabolism profiles get
  # extended to chemolithotrophic substrates, every preset needs at
  # least a baseline level of glucose + acetate + N + P so a default
  # founder colony can survive long enough to reveal the archetype's
  # selective pressures. The "flavour" metabolites (H₂, H₂S, Fe, SO₄)
  # remain dominant — they're just no longer the only food on the
  # menu.
  defp starting_pool(:saline_estuary) do
    %{glucose: 10.0, acetate: 3.0, oxygen: 7.0, nh3: 2.0, no3: 1.5, so4: 4.0, po4: 1.0}
  end

  defp starting_pool(:marine_sediment) do
    %{
      glucose: 6.0,
      acetate: 4.0,
      h2: 1.5,
      oxygen: 1.0,
      so4: 8.0,
      h2s: 2.0,
      iron: 0.5,
      co2: 4.0,
      nh3: 1.5,
      po4: 0.6
    }
  end

  defp starting_pool(:methanogenic_bog) do
    %{
      glucose: 5.0,
      acetate: 5.0,
      h2: 3.0,
      co2: 6.0,
      ch4: 1.0,
      nh3: 1.5,
      oxygen: 0.5,
      po4: 0.5
    }
  end

  defp starting_pool(:hydrothermal_vent) do
    %{
      glucose: 4.0,
      acetate: 2.0,
      h2: 4.0,
      h2s: 3.0,
      co2: 5.0,
      iron: 1.5,
      so4: 4.0,
      oxygen: 0.5,
      nh3: 1.0,
      po4: 0.4
    }
  end

  defp starting_pool(:acid_mine_drainage) do
    %{
      glucose: 6.0,
      acetate: 2.0,
      iron: 4.0,
      so4: 6.0,
      oxygen: 4.0,
      co2: 3.0,
      h2s: 0.5,
      nh3: 1.2,
      po4: 0.5
    }
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

  defp inflow_profile(:saline_estuary) do
    %{glucose: 5.0, acetate: 1.5, oxygen: 3.5, nh3: 1.0, no3: 0.8, so4: 2.0, po4: 0.6}
  end

  defp inflow_profile(:marine_sediment) do
    %{
      glucose: 2.0,
      acetate: 1.5,
      h2: 0.8,
      so4: 3.0,
      oxygen: 0.3,
      iron: 0.2,
      nh3: 0.6,
      po4: 0.3
    }
  end

  defp inflow_profile(:methanogenic_bog) do
    %{
      glucose: 1.5,
      acetate: 1.8,
      h2: 1.2,
      co2: 2.5,
      nh3: 0.7,
      oxygen: 0.1,
      po4: 0.2
    }
  end

  defp inflow_profile(:hydrothermal_vent) do
    %{
      glucose: 1.2,
      acetate: 0.8,
      h2: 2.0,
      h2s: 1.5,
      co2: 2.0,
      iron: 0.7,
      so4: 1.5,
      nh3: 0.5,
      po4: 0.2
    }
  end

  defp inflow_profile(:acid_mine_drainage) do
    %{
      glucose: 2.0,
      acetate: 0.8,
      iron: 1.8,
      so4: 2.5,
      oxygen: 1.5,
      co2: 1.0,
      nh3: 0.5,
      po4: 0.2
    }
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
  # Marine_layer (osmolarity 1100) is too harsh for a founder colony
  # without a salinity-tuned envelope — putting cells there at tick 0
  # collapses the seed via osmotic-shock lysis before any selection
  # can happen. The founder is now seeded only in freshwater + mixing
  # phases; cells reach the marine layer naturally via inter-phase
  # migration once the population has stabilised.
  defp phase_seed_weight(:marine_layer), do: 0.0
  defp phase_seed_weight(_phase_name), do: 0.85

  defp starter_ecotype(archetype) when is_atom(archetype) do
    Enum.find(@starter_ecotypes, &(&1.archetype == archetype))
  end

  defp starter_ecotype(archetype) when is_binary(archetype) do
    Enum.find(@starter_ecotypes, &(&1.id == archetype))
  end

  defp domain_label(:dna_binding), do: "DNA Binding"

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
    spec = blueprint.phenotype_spec || %{}

    form_defaults()
    |> Map.merge(Map.new(spec))
    |> Map.merge(%{
      "seed_name" => blueprint.name,
      "starter_archetype" => blueprint.starter_archetype,
      "custom_gene_payload" => spec |> Map.get("custom_genes", []) |> Jason.encode!(),
      "custom_plasmid_payload" => spec |> Map.get("custom_plasmid_genes", []) |> Jason.encode!()
    })
  end

  defp decode_custom_gene_payload(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, decoded} when is_list(decoded) ->
        Enum.map(decoded, &normalize_custom_gene_spec/1)

      _ ->
        []
    end
  end

  defp decode_custom_gene_payload(payload) when is_list(payload) do
    Enum.map(payload, &normalize_custom_gene_spec/1)
  end

  defp decode_custom_gene_payload(_payload), do: []

  defp normalize_custom_gene_spec(spec) when is_map(spec) do
    %{
      domains:
        spec
        |> Map.get("domains", Map.get(spec, :domains, []))
        |> Enum.map(&normalize_domain_entry/1)
        |> Enum.filter(&domain_entry_valid?/1)
        |> Enum.take(9),
      intergenic:
        spec
        |> Map.get("intergenic", Map.get(spec, :intergenic, %{}))
        |> normalize_intergenic_blocks()
    }
  end

  defp normalize_custom_gene_spec(_other),
    do: %{domains: [], intergenic: normalize_intergenic_blocks(%{})}

  # Accept both wire shapes: bare string `"substrate_binding"` (legacy)
  # and full map `%{"type" => "substrate_binding", "params" => %{...}}`.
  defp normalize_domain_entry(entry) when is_binary(entry) do
    %{type: entry, params: %{}}
  end

  defp normalize_domain_entry(entry) when is_atom(entry) do
    %{type: Atom.to_string(entry), params: %{}}
  end

  defp normalize_domain_entry(%{} = entry) do
    type =
      entry
      |> Map.get("type", Map.get(entry, :type))
      |> to_string()

    raw_params =
      entry
      |> Map.get("params", Map.get(entry, :params, %{}))
      |> case do
        %{} = p -> p
        _ -> %{}
      end

    %{type: type, params: Arkea.Game.SeedLab.DomainEditor.sanitize(type, raw_params)}
  end

  defp normalize_domain_entry(_other), do: %{type: "", params: %{}}

  defp domain_entry_valid?(%{type: type}), do: valid_domain_id?(type)
  defp domain_entry_valid?(_), do: false

  defp normalize_intergenic_blocks(blocks) when is_map(blocks) do
    %{
      expression: normalize_intergenic_family(blocks, "expression", :expression),
      transfer: normalize_intergenic_family(blocks, "transfer", :transfer),
      duplication: normalize_intergenic_family(blocks, "duplication", :duplication)
    }
  end

  defp normalize_intergenic_blocks(_other) do
    %{expression: [], transfer: [], duplication: []}
  end

  defp normalize_intergenic_family(blocks, string_key, atom_key) do
    valid_ids =
      @intergenic_palette
      |> Map.fetch!(atom_key)
      |> Enum.map(& &1.id)

    blocks
    |> Map.get(string_key, Map.get(blocks, atom_key, []))
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.filter(&(&1 in valid_ids))
    |> Enum.uniq()
  end

  defp valid_domain_id?(domain_id) when is_binary(domain_id) do
    Enum.any?(@domain_palette, &(&1.id == domain_id))
  end

  defp domain_type_from_id(domain_id) when is_binary(domain_id) do
    type = String.to_existing_atom(domain_id)

    if type in DomainType.all() do
      type
    else
      :substrate_binding
    end
  rescue
    ArgumentError -> :substrate_binding
  end

  defp normalize_params(params) do
    merged = Map.merge(@defaults, Map.new(params))
    starter = safe_option_id(merged["starter_archetype"], @starter_ecotypes, "")
    starter_selected? = starter != ""
    preview_starter = if starter_selected?, do: starter, else: "eutrophic_pond"
    metabolism = safe_option_id(merged["metabolism_profile"], @metabolism_profiles, "balanced")
    membrane = safe_option_id(merged["membrane_profile"], @membrane_profiles, "porous")
    regulation = safe_option_id(merged["regulation_profile"], @regulation_profiles, "responsive")
    mobile = safe_option_id(merged["mobile_module"], @mobile_modules, "none")

    custom_genes =
      merged
      |> Map.get("custom_gene_payload", "[]")
      |> decode_custom_gene_payload()
      |> Enum.reject(&(&1.domains == []))

    custom_plasmid_genes =
      merged
      |> Map.get("custom_plasmid_payload", "[]")
      |> decode_custom_gene_payload()
      |> Enum.reject(&(&1.domains == []))

    %{
      seed_name: merged["seed_name"] |> to_string() |> String.trim(),
      starter_archetype: preview_starter |> starter_ecotype() |> Map.fetch!(:archetype),
      starter_choice_id: starter,
      starter_selected?: starter_selected?,
      metabolism_profile: metabolism,
      membrane_profile: membrane,
      regulation_profile: regulation,
      mobile_module: mobile,
      custom_genes: custom_genes,
      custom_plasmid_genes: custom_plasmid_genes
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
