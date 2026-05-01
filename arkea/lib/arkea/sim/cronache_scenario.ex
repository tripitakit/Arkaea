defmodule Arkea.Sim.CronacheScenario do
  @moduledoc """
  End-to-end "Cronache" scenario for Phase 11 (IMPLEMENTATION-PLAN.md §5).

  Builds two connected biotopes that exercise all implemented mechanisms
  within a few dozen ticks:

  - **Pond** (`eutrophic_pond`) — nutrient-rich baseline; seed lineages grow,
    diversify by mutation, and the conjugative carrier spreads its plasmid via
    HGT to plasmid-free descendants.
  - **Estuary** (`saline_estuary`) — lower glucose inflow produces metabolic
    stress that can trigger prophage induction in lineages carrying a cassette.

  The two biotopes are neighbours in the topology graph, so the Phase 8
  `Migration.Coordinator` will gradually redistribute lineages and pool
  contents between them.

  ## Seed genomes

  **Founder** (chromosome only + prophage cassette):

    - `:substrate_binding` [0,0,0] — glucose affinity (low Km ≈ 5)
    - `:catalytic_site` [0,0,1] — QS signal producer (signal_key "10,10,10,10")
    - `:ligand_sensor` [0,3,4] — QS signal receiver (matching signal_key)
    - `:repair_fidelity` [0,1,9] — low efficiency → high mutability
    - `:energy_coupling` [0,1,3] — low cost (sustainable at chemostat inflow)
    - Prophage cassette: 1 `:structural_fold` gene [0,0,8]

  **Carrier** (founder genome + conjugative plasmid):

    - Inherits the founder chromosome and prophage
    - Extra plasmid: 1 `:transmembrane_anchor` gene [0,0,2] → pilus-like
      proxy for conjugative transfer (DESIGN.md Block 5 / Phase 6)

  Both biotopes are seeded with the founder genome. The pond additionally
  carries the conjugative carrier as a second seed lineage.
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

  # Stable UUIDs so the LiveView PubSub subscription survives restarts.
  @pond_id "00000000-0000-0000-0000-000000000002"
  @estuary_id "00000000-0000-0000-0000-000000000003"

  # Pond: nutrient-rich chemostat (same profile as SeedScenario).
  @pond_inflow %{glucose: 10.0, oxygen: 5.0, nh3: 2.0, po4: 1.0}

  # Estuary: scarcer glucose → metabolic stress → higher prophage induction.
  @estuary_inflow %{glucose: 3.0, oxygen: 3.0, nh3: 1.0, po4: 0.5}

  # Starting abundance per phase role — large enough for reliable HGT detection
  # across independent tick trials and for mutation to generate visible diversity.
  @founder_counts %{
    surface: 600,
    water_column: 800,
    sediment: 200,
    freshwater_layer: 400,
    mixing_zone: 250,
    marine_layer: 100
  }
  @carrier_counts %{surface: 200, water_column: 300, sediment: 100}
  @default_count 150

  # ---------------------------------------------------------------------------
  # Public API

  @doc """
  Start both biotopes under `Arkea.Sim.Biotope.Supervisor`.

  Returns `{:ok, {pond_id, estuary_id}}` on success, or `{:error, reason}`
  if either start fails.
  """
  @spec start() :: {:ok, {binary(), binary()}} | {:error, term()}
  def start do
    with {:ok, _} <- BiotopeSupervisor.start_biotope(build_pond_state()),
         {:ok, _} <- BiotopeSupervisor.start_biotope(build_estuary_state()) do
      Logger.info("CronacheScenario: started pond #{@pond_id} and estuary #{@estuary_id}")
      {:ok, {@pond_id, @estuary_id}}
    end
  end

  @doc "Build the eutrophic-pond `BiotopeState` for the Cronache scenario."
  @spec build_pond_state() :: BiotopeState.t()
  def build_pond_state do
    phases =
      :eutrophic_pond
      |> Biotope.default_phases()
      |> Enum.map(&init_pond_metabolites/1)

    BiotopeState.new_from_opts(
      id: @pond_id,
      archetype: :eutrophic_pond,
      phases: phases,
      dilution_rate: mean_dilution(phases),
      neighbor_ids: [@estuary_id],
      lineages: build_pond_lineages(phases),
      metabolite_inflow: @pond_inflow
    )
  end

  @doc "Build the saline-estuary `BiotopeState` for the Cronache scenario."
  @spec build_estuary_state() :: BiotopeState.t()
  def build_estuary_state do
    phases =
      :saline_estuary
      |> Biotope.default_phases()
      |> Enum.map(&init_estuary_metabolites/1)

    BiotopeState.new_from_opts(
      id: @estuary_id,
      archetype: :saline_estuary,
      phases: phases,
      dilution_rate: mean_dilution(phases),
      neighbor_ids: [@pond_id],
      lineages: [build_lineage(phases, build_founder_genome(), @founder_counts)],
      metabolite_inflow: @estuary_inflow
    )
  end

  # ---------------------------------------------------------------------------
  # Private — metabolite initialisation

  defp init_pond_metabolites(%Phase{} = phase) do
    phase
    |> Phase.update_metabolite(:glucose, 20.0)
    |> Phase.update_metabolite(:oxygen, 10.0)
    |> Phase.update_metabolite(:nh3, 4.0)
    |> Phase.update_metabolite(:po4, 2.0)
    |> Phase.update_metabolite(:co2, 5.0)
  end

  defp init_estuary_metabolites(%Phase{} = phase) do
    phase
    |> Phase.update_metabolite(:glucose, 5.0)
    |> Phase.update_metabolite(:oxygen, 5.0)
    |> Phase.update_metabolite(:nh3, 2.0)
    |> Phase.update_metabolite(:po4, 1.0)
    |> Phase.update_metabolite(:co2, 2.0)
  end

  # ---------------------------------------------------------------------------
  # Private — lineage construction

  defp build_pond_lineages(phases) do
    [
      build_lineage(phases, build_founder_genome(), @founder_counts),
      build_lineage(phases, build_carrier_genome(), @carrier_counts)
    ]
  end

  defp build_lineage(phases, genome, count_map) do
    abundances = Map.new(phases, fn p -> {p.name, Map.get(count_map, p.name, @default_count)} end)
    Lineage.new_founder(genome, abundances, 0)
  end

  # ---------------------------------------------------------------------------
  # Private — genome construction

  # Founder genome: 5-domain chromosome + 1-gene prophage cassette.
  #
  # domain encoding (type = rem(sum_of_type_tag_codons, 11)):
  #   [0,0,0] → index 0 → :substrate_binding
  #   [0,0,1] → index 1 → :catalytic_site
  #   [0,3,4] → index 7 → :ligand_sensor
  #   [0,1,9] → index 10 → :repair_fidelity
  #   [0,1,3] → index 4 → :energy_coupling
  #   [0,0,8] → index 8 → :structural_fold  (prophage cassette)
  defp build_founder_genome do
    substrate = Domain.new([0, 0, 0], [0 | List.duplicate(2, 19)])
    catalytic = Domain.new([0, 0, 1], List.duplicate(10, 20))
    sensor = Domain.new([0, 3, 4], List.duplicate(10, 20))
    repair = Domain.new([0, 1, 9], List.duplicate(2, 20))
    energy = Domain.new([0, 1, 3], List.duplicate(5, 20))

    chromosome_gene = Gene.from_domains([substrate, catalytic, sensor, repair, energy])
    prophage_gene = Gene.from_domains([Domain.new([0, 0, 8], List.duplicate(5, 20))])

    Genome.new([chromosome_gene], prophages: [[prophage_gene]])
  end

  # Carrier genome: founder + 1-gene conjugative plasmid.
  #   [0,0,2] → index 2 → :transmembrane_anchor  (pilus-like, conjugation proxy)
  defp build_carrier_genome do
    tm_domain = Domain.new([0, 0, 2], List.duplicate(8, 20))
    plasmid_gene = Gene.from_domains([tm_domain])
    Genome.add_plasmid(build_founder_genome(), [plasmid_gene])
  end

  defp mean_dilution(phases) do
    Enum.sum(Enum.map(phases, & &1.dilution_rate)) / length(phases)
  end
end
