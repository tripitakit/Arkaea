defmodule Arkea.Sim.SeedScenario do
  @moduledoc """
  Bootstraps the default simulation scenario on application start.

  Provides a single public function `start_default/0` that starts a
  deterministic, fixed-ID eutrophic-pond biotope with one seed lineage.
  The fixed biotope id ensures that the scenario survives application restarts
  without changing identity — the LiveView always subscribes to the same
  PubSub topic and the same `Biotope.Server` registry key.

  ## Seed genome composition

  The seed genome encodes three functional domains (DESIGN.md Block 7):

    - `:catalytic_site` — moderate kcat (growth potential)
    - `:repair_fidelity` — low efficiency (high mutation rate, drives diversity)
    - `:energy_coupling` — moderate atp_cost (sustainable growth)

  This combination produces a lineage that grows steadily, mutates frequently,
  and generates visible phenotypic diversity within a few dozen ticks at the
  2-second dev tick interval.

  ## Idempotency

  If a `Biotope.Server` for the fixed id is already registered (e.g. after a
  LiveView hot-reload), the function returns `{:error, :already_running}`
  without starting a second server. The Application start-up `Task` ignores
  this error silently.
  """

  require Logger

  alias Arkea.Ecology.Biotope
  alias Arkea.Ecology.Lineage
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

  defp build_biotope_state do
    # Build the eutrophic_pond biotope to get its canonical phases.
    # We cannot use Biotope.new/3 directly because it generates a random UUID;
    # instead we use BiotopeState.new_from_opts/1 with the fixed id and the
    # default phases from Biotope, bypassing the Biotope struct requirement.
    phases = Biotope.default_phases(:eutrophic_pond)
    seed_lineage = build_seed_lineage()

    BiotopeState.new_from_opts(
      id: @default_biotope_id,
      archetype: :eutrophic_pond,
      phases: phases,
      dilution_rate: mean_dilution(phases),
      lineages: [seed_lineage]
    )
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
    # catalytic_site: type_tag sum rem 11 == 1  → [0, 0, 1]
    # parameter_codons: 20 codons at value 10 (moderate kcat)
    catalytic = Domain.new([0, 0, 1], List.duplicate(10, 20))

    # repair_fidelity: type_tag sum rem 11 == 10 → [0, 1, 9]
    # parameter_codons: 20 codons at value 2 (low efficiency = high mutability)
    repair = Domain.new([0, 1, 9], List.duplicate(2, 20))

    # energy_coupling: type_tag sum rem 11 == 4  → [0, 1, 3]
    # parameter_codons: 20 codons at value 8 (moderate atp_cost)
    energy = Domain.new([0, 1, 3], List.duplicate(8, 20))

    gene = Gene.from_domains([catalytic, repair, energy])
    Genome.new([gene])
  end

  defp mean_dilution(phases) do
    total = Enum.sum(Enum.map(phases, & &1.dilution_rate))
    total / length(phases)
  end
end
