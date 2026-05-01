defmodule Arkea.Sim.SeedScenario do
  @moduledoc """
  Bootstraps the default simulation scenario on application start.

  Provides a single public function `start_default/0` that starts a
  deterministic, fixed-ID eutrophic-pond biotope with one seed lineage.
  The fixed biotope id ensures that the scenario survives application restarts
  without changing identity — the LiveView always subscribes to the same
  PubSub topic and the same `Biotope.Server` registry key.

  ## Seed genome composition

  The seed genome encodes four functional domains (DESIGN.md Block 7):

    - `:substrate_binding` — targets glucose (low Km ≈ 5, high affinity)
    - `:catalytic_site` — moderate kcat; also seeds the QS signal pool
    - `:repair_fidelity` — low efficiency (high mutation rate, drives diversity)
    - `:energy_coupling` — low atp_cost (sustainable at chemostat inflow)

  Phase 5 requires a `:substrate_binding` domain for any metabolite uptake;
  without it `atp_yield = 0.0` every tick and the lineage starves.  The low
  energy cost ensures positive growth even when glucose is scarce (pool ≈
  inflow / dilution_rate).  High mutation rate generates visible phenotypic
  diversity within a few dozen ticks at the 2-second dev tick interval.

  ## Idempotency

  If a `Biotope.Server` for the fixed id is already registered (e.g. after a
  LiveView hot-reload), the function returns `{:error, :already_running}`
  without starting a second server. The Application start-up `Task` ignores
  this error silently.
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

  # Symbolic fixed UUID — stable across restarts so the LiveView PubSub
  # subscription and Registry lookup always find the same process.
  @default_biotope_id "00000000-0000-0000-0000-000000000001"

  @doc """
  Start the default simulation scenario.

  Returns `{:ok, biotope_id}` when a new `Biotope.Server` is started, or
  `{:error, :already_running}` when a server for the fixed id is already live.
  """
  @spec start_default() :: {:ok, binary()} | {:error, :already_running}
  def start_default do
    if already_running?(@default_biotope_id) do
      Logger.debug("SeedScenario: biotope #{@default_biotope_id} already running, skipping")
      {:error, :already_running}
    else
      do_start()
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers

  defp already_running?(id) do
    case Registry.lookup(Arkea.Sim.Registry, {:biotope, id}) do
      [] -> false
      [_ | _] -> true
    end
  end

  defp do_start do
    biotope_state = build_biotope_state()

    case BiotopeSupervisor.start_biotope(biotope_state) do
      {:ok, _pid} ->
        Logger.info("SeedScenario: started default biotope #{@default_biotope_id}")
        {:ok, @default_biotope_id}

      {:error, reason} ->
        Logger.warning("SeedScenario: failed to start biotope: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Phase 5 metabolite inflow: continuous replenishment per tick (chemostat).
  # Values are dimensionless concentration units consistent with the initial
  # pool values set by `initialize_metabolites/1`.
  @metabolite_inflow %{
    glucose: 10.0,
    oxygen: 5.0,
    nh3: 2.0,
    po4: 1.0
  }

  defp build_biotope_state do
    # Build the eutrophic_pond biotope to get its canonical phases.
    # We cannot use Biotope.new/3 directly because it generates a random UUID;
    # instead we use BiotopeState.new_from_opts/1 with the fixed id and the
    # default phases from Biotope, bypassing the Biotope struct requirement.
    base_phases = Biotope.default_phases(:eutrophic_pond)
    phases = Enum.map(base_phases, &initialize_metabolites/1)
    seed_lineage = build_seed_lineage()

    BiotopeState.new_from_opts(
      id: @default_biotope_id,
      archetype: :eutrophic_pond,
      phases: phases,
      dilution_rate: mean_dilution(phases),
      lineages: [seed_lineage],
      metabolite_inflow: @metabolite_inflow
    )
  end

  # Initialize Phase 5 metabolite concentrations using Phase.update_metabolite/3.
  # Starting concentrations approximate the chemostat steady state without
  # consumers: glucose ≈ inflow/dilution_rate = 10/0.04 = 250.  We seed at
  # 20.0 (below equilibrium) so the lineage sees scarcity from tick 1 and
  # the initial burst is limited.  Other substrates are seeded proportionally.
  defp initialize_metabolites(%Phase{} = phase) do
    phase
    |> Phase.update_metabolite(:glucose, 20.0)
    |> Phase.update_metabolite(:oxygen, 10.0)
    |> Phase.update_metabolite(:nh3, 4.0)
    |> Phase.update_metabolite(:po4, 2.0)
    |> Phase.update_metabolite(:co2, 5.0)
  end

  defp build_seed_lineage do
    genome = build_seed_genome()

    # Seed abundance distributed across the three eutrophic_pond phases.
    # Surface and water_column get most of the population; sediment gets a
    # small fraction. This matches the expected distribution for a plankton-
    # like aerobic heterotroph at inoculation time (DESIGN.md Block 12).
    abundances = %{surface: 200, water_column: 250, sediment: 50}

    Lineage.new_founder(genome, abundances, 0)
  end

  defp build_seed_genome do
    # substrate_binding: type_tag sum rem 11 == 0  → [0, 0, 0]
    # first codon = 0  → target_metabolite_id = rem(0, 13) = 0 → :glucose
    # remaining codons at 2  → weighted_sum ≈ 24, norm ≈ 0.049, km ≈ 4.9
    # (low Km = high affinity; kcat defaults to 1.0 in Phenotype aggregation)
    substrate = Domain.new([0, 0, 0], [0 | List.duplicate(2, 19)])

    # catalytic_site: type_tag sum rem 11 == 1  → [0, 0, 1]
    # parameter_codons: 20 codons at value 10 (moderate kcat ≈ 5.0)
    catalytic = Domain.new([0, 0, 1], List.duplicate(10, 20))

    # repair_fidelity: type_tag sum rem 11 == 10 → [0, 1, 9]
    # parameter_codons: 20 codons at value 2 (efficiency ≈ 0.05 = high mutability)
    repair = Domain.new([0, 1, 9], List.duplicate(2, 20))

    # energy_coupling: type_tag sum rem 11 == 4  → [0, 1, 3]
    # parameter_codons: 20 codons at value 5 → weighted_sum ≈ 87, atp_cost ≈ 0.87
    # Low cost sustains positive delta even when glucose pool = inflow (≈10 units).
    # Break-even: atp_yield > atp_cost × 5.0 = 4.35; inflow gives atp_yield ≈ 20.
    energy = Domain.new([0, 1, 3], List.duplicate(5, 20))

    gene = Gene.from_domains([substrate, catalytic, repair, energy])
    Genome.new([gene])
  end

  defp mean_dilution(phases) do
    total = Enum.sum(Enum.map(phases, & &1.dilution_rate))
    total / length(phases)
  end
end
