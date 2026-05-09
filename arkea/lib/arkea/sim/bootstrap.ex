defmodule Arkea.Sim.Bootstrap do
  @moduledoc """
  Startup-time world bootstrap (Phase 33).

  Idempotently seeds the default Arkea world on application start:

    * **3 wild biotopes** — solo-seeded with a high-mutability
      genome that drives observable evolution within a few hundred
      ticks. Each biotope uses a distinct archetype
      (`:eutrophic_pond`, `:mesophilic_soil`, `:marine_sediment`)
      so the player sees different environmental contexts (pH,
      osmolarity, dilution) drive divergent selection.
    * **1 community biotope** — co-inoculated with a 3-seed
      *chemotrophic chain* on `:methanogenic_bog`:
        - **A** consumes glucose → produces acetate + CO₂ + H₂
        - **B** consumes acetate → produces CO₂
        - **C** consumes CO₂ → produces CH₄ (methanogen)
      The mass-action coupling between substrates and byproducts
      drives natural variability and abundance cycles: as A
      drains the glucose pool, B's substrate (acetate) climbs and
      then drops once A starves; C's substrate (CO₂) accumulates
      from both A and B before being reduced to methane.

  ## Idempotency

  Each biotope uses a fixed UUID so the function is safe to call
  on every application start. If a `Biotope.Server` for that id
  is already registered (e.g. after recovery from persistence,
  or a hot reload), the bootstrap skips it silently.

  ## Disabling the bootstrap

  In test / CI environments the application config can disable
  the bootstrap entirely via:

      config :arkea, :startup_bootstrap, false

  This keeps the test suite isolated from the demo world and
  preserves the existing `start_supervised!(BiotopeSupervisor)`
  pattern.
  """

  require Logger

  alias Arkea.Ecology.Biotope
  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Sim.Biotope.Supervisor, as: BiotopeSupervisor
  alias Arkea.Sim.BiotopeState

  # Stable biotope ids — survive restarts so the LiveView /
  # PubSub subscription path always finds the same processes.
  @wild_biotopes [
    %{id: "00000000-0000-0000-0000-000000000010", archetype: :eutrophic_pond, label: "wild-pond"},
    %{
      id: "00000000-0000-0000-0000-000000000011",
      archetype: :mesophilic_soil,
      label: "wild-soil"
    },
    %{
      id: "00000000-0000-0000-0000-000000000012",
      archetype: :marine_sediment,
      label: "wild-sediment"
    }
  ]

  @community_biotope_id "00000000-0000-0000-0000-000000000020"
  @community_archetype :methanogenic_bog

  @doc """
  Public ids for the bootstrapped biotopes (consumed by tests +
  UI surfaces that want to flag them as "demo / starter
  biotopes").
  """
  @spec wild_biotope_ids() :: [String.t()]
  def wild_biotope_ids, do: Enum.map(@wild_biotopes, & &1.id)

  @doc "Public id for the bootstrapped community-chain biotope."
  @spec community_biotope_id() :: String.t()
  def community_biotope_id, do: @community_biotope_id

  @doc """
  Run the full default-world bootstrap. Idempotent: existing
  biotopes (recovered from persistence, hot-reloaded, etc.) are
  skipped; missing ones are started under the
  `Arkea.Sim.Biotope.Supervisor`.

  Returns `{:ok, %{started: started, skipped: skipped}}`.
  """
  @spec bootstrap_default_world() ::
          {:ok, %{started: non_neg_integer(), skipped: non_neg_integer()}}
  def bootstrap_default_world do
    if enabled?() do
      result =
        @wild_biotopes
        |> Enum.map(&build_wild_state/1)
        |> Enum.concat([build_community_state()])
        |> Enum.reduce(%{started: 0, skipped: 0}, &start_or_skip/2)

      Logger.info(
        "Bootstrap.bootstrap_default_world: started=#{result.started} skipped=#{result.skipped}"
      )

      {:ok, result}
    else
      {:ok, %{started: 0, skipped: 0}}
    end
  end

  defp enabled? do
    Application.get_env(:arkea, :startup_bootstrap, true)
  end

  defp start_or_skip(%BiotopeState{id: id} = state, acc) do
    if already_running?(id) do
      %{acc | skipped: acc.skipped + 1}
    else
      case BiotopeSupervisor.start_biotope(state) do
        {:ok, _pid} ->
          %{acc | started: acc.started + 1}

        {:error, {:already_started, _pid}} ->
          %{acc | skipped: acc.skipped + 1}

        {:error, reason} ->
          Logger.warning("Bootstrap: failed to start biotope #{id}: #{inspect(reason)}")
          acc
      end
    end
  end

  defp already_running?(id) do
    case Registry.lookup(Arkea.Sim.Registry, {:biotope, id}) do
      [] -> false
      [_ | _] -> true
    end
  end

  # ---------------------------------------------------------------------------
  # Wild biotope construction
  # ---------------------------------------------------------------------------

  defp build_wild_state(%{id: id, archetype: archetype, label: _label}) do
    base_phases = Biotope.default_phases(archetype)
    phases = Enum.map(base_phases, &seed_wild_metabolites/1)
    seed = build_wild_seed_lineage(phases, id)

    BiotopeState.new_from_opts(
      id: id,
      archetype: archetype,
      phases: phases,
      dilution_rate: mean_dilution(phases),
      lineages: [seed],
      metabolite_inflow: wild_metabolite_inflow()
    )
  end

  # Generous metabolite pool — enough substrate to sustain a
  # population of several hundred cells while still seeing
  # scarcity-driven selection when mutants compete for the same
  # niche. Inflow continues feeding the chemostat so the
  # equilibrium concentration is non-trivial.
  defp seed_wild_metabolites(%Phase{} = phase) do
    phase
    |> Phase.update_metabolite(:glucose, 60.0)
    |> Phase.update_metabolite(:oxygen, 20.0)
    |> Phase.update_metabolite(:nh3, 8.0)
    |> Phase.update_metabolite(:po4, 4.0)
    |> Phase.update_metabolite(:co2, 5.0)
  end

  defp wild_metabolite_inflow do
    %{glucose: 12.0, oxygen: 5.0, nh3: 2.0, po4: 1.0}
  end

  # The wild seed is deliberately *highly mutable* (low
  # repair_efficiency) so the player sees:domain_flips,
  # :gene_chimera_birth events, mutator_emergence events,
  # and visible phenotypic diversification within ~100 ticks.
  # Composition (Block 7 / Phase 1):
  #   - substrate_binding(glucose) → uptake hook
  #   - catalytic_site (kcat ≈ 5) → moderate ATP yield
  #   - dna_binding → contributes to σ
  #   - repair_fidelity (low ≈ 0.1) → high mutation rate
  #   - energy_coupling (low cost) → sustainable growth
  #   - structural_fold (multimer ≥ 4) + catalytic ligation
  #     → ribosome_like proxy (Phase 29 translation_efficiency)
  defp build_wild_seed_lineage(phases, biotope_id) do
    genome = build_wild_seed_genome()

    abundances =
      phases
      |> Enum.with_index()
      |> Enum.map(fn {phase, idx} ->
        # Front-load the surface phase, taper deeper.
        count = max(div(300, idx + 1), 30)
        {phase.name, count}
      end)
      |> Map.new()

    Lineage.new_founder(genome, abundances, 0,
      original_seed_id: "wild-seed-#{biotope_id |> String.slice(0, 8)}"
    )
  end

  defp build_wild_seed_genome do
    # Glucose uptake: target_metabolite_id = rem(first_codon, 13).
    # first_codon = 0 → glucose (id 0).
    substrate = Domain.new([0, 0, 0], [0 | List.duplicate(2, 19)])

    # Catalytic_site hydrolysis (rem(sum_first_3, 6) = 0 with first_3 [0,0,0]).
    # Param = 10 yields kcat ≈ 5. Co-located with substrate_binding +
    # dna_binding so the phenotype derivation produces a clean σ contribution.
    catalytic = Domain.new([0, 0, 1], List.duplicate(10, 20))

    # dna_binding (sum 5 mod 11 = 5 → :dna_binding).
    dna_binding = Domain.new([0, 0, 5], List.duplicate(10, 20))

    # repair_fidelity (sum 10 mod 11 = 10 → :repair_fidelity).
    # Param 2 → low efficiency ≈ 0.1 → high mutation rate.
    repair = Domain.new([0, 1, 9], List.duplicate(2, 20))

    # energy_coupling (sum 4 mod 11 = 4). Param 5 → moderate atp_cost ≈ 0.5.
    energy = Domain.new([0, 1, 3], List.duplicate(5, 20))

    metabolic_gene = Gene.from_domains([substrate, catalytic, dna_binding, repair, energy])

    # Ribosome-like proxy gene (Phase 29 translation_efficiency hook).
    ribo_fold = Domain.new([0, 0, 8], List.duplicate(10, 17) ++ [3, 3, 5])

    ribo_catalytic =
      Domain.new([0, 0, 1], [4, 0, 0] ++ List.duplicate(10, 17))

    ribosome_gene = Gene.from_domains([ribo_fold, ribo_catalytic])

    Genome.new([metabolic_gene, ribosome_gene])
  end

  # ---------------------------------------------------------------------------
  # Community biotope construction
  # ---------------------------------------------------------------------------

  defp build_community_state do
    base_phases = Biotope.default_phases(@community_archetype)
    phases = Enum.map(base_phases, &seed_community_metabolites/1)

    lineages = [
      build_community_lineage(phases, "community-seed-A-glucose-fermenter", :glucose),
      build_community_lineage(phases, "community-seed-B-acetate-oxidizer", :acetate),
      build_community_lineage(phases, "community-seed-C-methanogen", :co2)
    ]

    BiotopeState.new_from_opts(
      id: @community_biotope_id,
      archetype: @community_archetype,
      phases: phases,
      dilution_rate: mean_dilution(phases),
      lineages: lineages,
      metabolite_inflow: community_metabolite_inflow()
    )
  end

  # The community biotope's `:methanogenic_bog` archetype is
  # naturally low-dilution (peat core ≈ 0.001/tick) so byproducts
  # accumulate visibly. We seed a glucose pool (food for A) and
  # nitrogen / phosphate floors (so growth isn't bottle-necked
  # by the elemental_floor check).
  defp seed_community_metabolites(%Phase{} = phase) do
    phase
    |> Phase.update_metabolite(:glucose, 80.0)
    |> Phase.update_metabolite(:acetate, 5.0)
    |> Phase.update_metabolite(:co2, 5.0)
    |> Phase.update_metabolite(:h2, 2.0)
    |> Phase.update_metabolite(:nh3, 8.0)
    |> Phase.update_metabolite(:po4, 4.0)
    |> Phase.update_metabolite(:oxygen, 6.0)
  end

  # Inflow keeps glucose flowing in (A's substrate) but does NOT
  # feed acetate or h2 or co2 — those have to come from the chain
  # itself. That's what produces the cycles: B's substrate is
  # entirely dependent on A's productivity, C's on B + A.
  defp community_metabolite_inflow do
    %{glucose: 6.0, oxygen: 2.0, nh3: 1.5, po4: 0.6}
  end

  # `target_metabolite` argument selects the substrate the lineage
  # will eat:
  #   :glucose → seed A (target_metabolite_id 0)
  #   :acetate → seed B (target_metabolite_id 1)
  #   :co2     → seed C (target_metabolite_id 3)
  defp build_community_lineage(phases, seed_id, target_metabolite) do
    genome = build_community_genome(target_metabolite)

    abundances =
      phases
      |> Enum.with_index()
      |> Enum.map(fn {phase, idx} ->
        # Smaller starting populations than the wild biotopes so
        # the cycle dynamics are visible (large founder
        # populations damp out the oscillations).
        count = max(div(150, idx + 1), 20)
        {phase.name, count}
      end)
      |> Map.new()

    Lineage.new_founder(genome, abundances, 0, original_seed_id: seed_id)
  end

  defp build_community_genome(target_metabolite) do
    target_id =
      case target_metabolite do
        :glucose -> 0
        :acetate -> 1
        :co2 -> 3
      end

    # substrate_binding: first_codon = target_id → metabolite atom mapping.
    substrate = Domain.new([0, 0, 0], [target_id | List.duplicate(8, 19)])

    # catalytic_site: moderate kcat. Same hydrolysis class for all
    # three seeds; reaction-class differentiation isn't needed
    # for the mass-action chain to run.
    catalytic = Domain.new([0, 0, 1], List.duplicate(10, 20))

    # dna_binding for σ contribution.
    dna_binding = Domain.new([0, 0, 5], List.duplicate(10, 20))

    # repair_fidelity HIGHER than the wild seeds — community seeds
    # need to persist long enough for the chain to establish
    # before mutational drift breaks them. param 12 → efficiency
    # ≈ 0.6 → moderate mutation rate.
    repair = Domain.new([0, 1, 9], List.duplicate(12, 20))

    # energy_coupling — keep cost low so all three seeds can
    # sustain growth on their preferred substrate.
    energy = Domain.new([0, 1, 3], List.duplicate(5, 20))

    metabolic_gene = Gene.from_domains([substrate, catalytic, dna_binding, repair, energy])

    # Ribosome-like proxy (Phase 29 translation_efficiency hook).
    ribo_fold = Domain.new([0, 0, 8], List.duplicate(10, 17) ++ [3, 3, 5])

    ribo_catalytic =
      Domain.new([0, 0, 1], [4, 0, 0] ++ List.duplicate(10, 17))

    ribosome_gene = Gene.from_domains([ribo_fold, ribo_catalytic])

    Genome.new([metabolic_gene, ribosome_gene])
  end

  # ---------------------------------------------------------------------------
  # Shared helpers
  # ---------------------------------------------------------------------------

  defp mean_dilution(phases) do
    Enum.sum(Enum.map(phases, & &1.dilution_rate)) / max(length(phases), 1)
  end
end
