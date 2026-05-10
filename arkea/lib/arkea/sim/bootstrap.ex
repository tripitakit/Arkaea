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
    # first_codon pinned at 0 → glucose (id 0); the remaining 19
    # codons vary around the original `2` so the seed displays a
    # heterogeneous codon strip while keeping km / specificity in
    # the same band.
    substrate = Domain.new([0, 0, 0], [0 | varied_codons(2, 19, 11)])

    # Catalytic_site hydrolysis: first 4 codons feed
    # `reaction_class` (sum_first_3 mod 6) AND `signal_key`
    # (first 4 joined as a string) — pin them so the QS / reaction
    # class don't drift; vary positions 4..19.
    catalytic = Domain.new([0, 0, 1], [10, 10, 10, 10] ++ varied_codons(10, 16, 12))

    # dna_binding — no categorical pin needed (params depend on
    # halves' norms, not on a specific position). Full diversification.
    dna_binding = Domain.new([0, 0, 5], varied_codons(10, 20, 13))

    # repair_fidelity: `repair_class = rem(first_codon, 3)`, so
    # pin position 0 to keep the same class; vary the rest around
    # `2` (low → high mutation rate as before).
    repair = Domain.new([0, 1, 9], [2 | varied_codons(2, 19, 14)])

    # energy_coupling — atp_cost / pmf_coupling depend on norms,
    # no positional pin needed.
    energy = Domain.new([0, 1, 3], varied_codons(5, 20, 15))

    metabolic_gene = Gene.from_domains([substrate, catalytic, dna_binding, repair, energy])

    # Ribosome-like proxy gene (Phase 29 translation_efficiency hook).
    # `:structural_fold`'s `multimerization_n` depends on
    # `sum(last_3) mod 8 + 1`, so pin the trailing [3,3,5] tail
    # (multimer_n = (3+3+5) mod 8 + 1 = 4 → tetramer); vary the
    # leading 17 stability-driving codons.
    ribo_fold = Domain.new([0, 0, 8], varied_codons(10, 17, 16) ++ [3, 3, 5])

    # `:catalytic_site` ribozyme proxy: pin first 4 (reaction_class
    # + signal_key); vary the trailing 16 codons.
    ribo_catalytic = Domain.new([0, 0, 1], [4, 0, 0, 10] ++ varied_codons(10, 16, 17))

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

    # Per-seed offset so each chain seed (A/B/C) gets a distinct
    # codon variation pattern instead of three carbon copies.
    offset = target_id * 7 + 23

    # substrate_binding: pin position 0 to `target_id` (controls
    # which metabolite the seed eats); diversify the rest around 8.
    substrate = Domain.new([0, 0, 0], [target_id | varied_codons(8, 19, offset)])

    # catalytic_site: same hydrolysis class across the chain — pin
    # first 4 (reaction_class + signal_key); diversify positions 4..19.
    catalytic = Domain.new([0, 0, 1], [10, 10, 10, 10] ++ varied_codons(10, 16, offset + 1))

    dna_binding = Domain.new([0, 0, 5], varied_codons(10, 20, offset + 2))

    # repair_fidelity HIGHER than wild seeds — community seeds
    # need to persist long enough for the chain to establish
    # before mutational drift breaks them. Pin position 0 (=12 →
    # repair_class fixed); vary the rest around 12 (efficiency
    # ≈ 0.6 → moderate mutation rate).
    repair = Domain.new([0, 1, 9], [12 | varied_codons(12, 19, offset + 3)])

    energy = Domain.new([0, 1, 3], varied_codons(5, 20, offset + 4))

    metabolic_gene = Gene.from_domains([substrate, catalytic, dna_binding, repair, energy])

    # Ribosome-like proxy (Phase 29 translation_efficiency hook):
    # pin the [3,3,5] tail of structural_fold and the [4,0,0,10]
    # head of catalytic to keep multimer_n + reaction_class stable.
    ribo_fold = Domain.new([0, 0, 8], varied_codons(10, 17, offset + 5) ++ [3, 3, 5])

    ribo_catalytic =
      Domain.new([0, 0, 1], [4, 0, 0, 10] ++ varied_codons(10, 16, offset + 6))

    ribosome_gene = Gene.from_domains([ribo_fold, ribo_catalytic])

    Genome.new([metabolic_gene, ribosome_gene])
  end

  # ---------------------------------------------------------------------------
  # Shared helpers
  # ---------------------------------------------------------------------------

  defp mean_dilution(phases) do
    Enum.sum(Enum.map(phases, & &1.dilution_rate)) / max(length(phases), 1)
  end

  # Deterministic codon diversification.
  #
  # Returns `n` codon values clustered around `target` with a
  # ±3 spread, generated by a small reproducible LCG seeded by
  # `seed`. The result is a list of valid `0..19` codons that
  # *displays* as a diverse strip but stays close enough to the
  # original uniform target that the derived weighted_sum (and
  # therefore all phenotype magnitudes) remain in the same band
  # as the unsubstituted seed.
  #
  # This is purely a *display* improvement: the simulation
  # mechanics (mutation rate, kcat, σ) are unchanged within
  # rounding noise. Categorical decisions (target_metabolite_id,
  # reaction_class, multimer_n, repair_class) depend on specific
  # positions and are pinned by the caller — see `build_*_genome`.
  @spec varied_codons(0..19, pos_integer(), non_neg_integer()) :: [0..19]
  defp varied_codons(target, n, seed)
       when is_integer(target) and target in 0..19 and is_integer(n) and n > 0 do
    Enum.map_reduce(1..n, seed, fn _i, state ->
      next = rem(state * 1_103_515_245 + 12_345, 2_147_483_648)
      delta = rem(div(next, 65_536), 7) - 3
      codon = max(0, min(19, target + delta))
      {codon, next}
    end)
    |> elem(0)
  end
end
