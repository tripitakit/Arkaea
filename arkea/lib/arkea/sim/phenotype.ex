defmodule Arkea.Sim.Phenotype do
  @moduledoc """
  Emergent phenotype derived from a genome by aggregating functional domain
  parameters (Phase 3 — IMPLEMENTATION-PLAN.md §6).

  This module is **strictly pure**: no OTP, no I/O, no side effects.

  ## Design

  The phenotype is the bridge between the genotype (a `Genome.t()` with its
  typed functional domains) and the simulation tick (`Ark.Sim.Tick`). It
  aggregates raw domain parameters into biological properties that feed
  `step_expression/1`.

  ### Phase 3 scope

  Only the properties needed for the growth-delta calculation in
  `step_expression/1` are computed here. Metabolic fluxes (Phase 5) and
  quorum-sensing / signalling cascades (Phase 6) will extend this struct
  without breaking callers.

  ### Aggregation rules (Phase 3)

  - `base_growth_rate` — mean of `:kcat` from all `:catalytic_site` domains,
    clamped to `0.0..1.0`. Default `0.1` when no catalytic domains are present
    (minimal basal metabolism).

  - `substrate_affinities` — map `metabolite_id => %{km: float, kcat: float}`
    built from all `:substrate_binding` domains. When multiple domains bind the
    same metabolite_id, the **last** one encountered in gene-order wins (simple
    override rule; Phase 5 will switch to highest-affinity selection).

  - `energy_cost` — sum of `:atp_cost` from all `:energy_coupling` domains,
    clamped to `0.0..5.0`.

  - `surface_tags` — list of `:tag_class` atoms from all `:surface_tag`
    domains. Duplicates are preserved (copy-number effect for Phase 6 HGT).

  - `repair_efficiency` — mean of `:efficiency` from all `:repair_fidelity`
    domains, clamped to `0.0..1.0`. Default `0.5` (wild-type baseline).

  - `structural_stability` — mean of `:stability` from all `:structural_fold`
    domains, clamped to `0.0..1.0`. Default `0.5`.

  - `n_transmembrane` — count of `:transmembrane_anchor` domains. Used in
    Phase 6 to determine HGT competence (membrane complexity proxy).
  """

  use TypedStruct

  alias Arkea.Genome
  alias Arkea.Genome.Domain

  typedstruct enforce: true do
    field :base_growth_rate, float()
    field :substrate_affinities, map()
    field :energy_cost, float()
    field :surface_tags, [atom()]
    field :repair_efficiency, float()
    field :structural_stability, float()
    field :n_transmembrane, non_neg_integer()
  end

  @doc """
  Derive an emergent phenotype from a genome.

  Iterates all domains across chromosome + plasmids + prophages exactly once,
  accumulating type-specific parameters into the phenotype fields.

  Pure and deterministic: the same genome always produces the same phenotype.
  """
  @spec from_genome(Genome.t()) :: t()
  def from_genome(%Genome{} = genome) do
    domains = Genome.all_domains(genome)
    aggregate(domains)
  end

  # ---------------------------------------------------------------------------
  # Private aggregation

  defp aggregate(domains) do
    acc = empty_accumulator()

    acc =
      Enum.reduce(domains, acc, fn %Domain{type: type, params: params}, a ->
        aggregate_domain(type, params, a)
      end)

    build_phenotype(acc)
  end

  defp empty_accumulator do
    %{
      kcat_values: [],
      substrate_affinities: %{},
      atp_costs: [],
      surface_tags: [],
      repair_efficiencies: [],
      stability_values: [],
      n_transmembrane: 0
    }
  end

  defp aggregate_domain(:catalytic_site, %{kcat: kcat}, acc) do
    %{acc | kcat_values: [kcat | acc.kcat_values]}
  end

  defp aggregate_domain(:substrate_binding, %{target_metabolite_id: mid, km: km} = p, acc) do
    # Pull kcat from catalytic context if available; substrate_binding domains
    # carry km but not kcat. We record km only here; the Michaelis-Menten
    # model in Phase 5 will pair it with a kcat from co-expressed catalytic
    # domains. For now, store km and set kcat to 1.0 as a neutral placeholder.
    kcat = Map.get(p, :kcat, 1.0)
    entry = %{km: km, kcat: kcat}
    %{acc | substrate_affinities: Map.put(acc.substrate_affinities, mid, entry)}
  end

  defp aggregate_domain(:energy_coupling, %{atp_cost: cost}, acc) do
    %{acc | atp_costs: [cost | acc.atp_costs]}
  end

  defp aggregate_domain(:surface_tag, %{tag_class: tag}, acc) do
    %{acc | surface_tags: [tag | acc.surface_tags]}
  end

  defp aggregate_domain(:repair_fidelity, %{efficiency: eff}, acc) do
    %{acc | repair_efficiencies: [eff | acc.repair_efficiencies]}
  end

  defp aggregate_domain(:structural_fold, %{stability: stab}, acc) do
    %{acc | stability_values: [stab | acc.stability_values]}
  end

  defp aggregate_domain(:transmembrane_anchor, _params, acc) do
    %{acc | n_transmembrane: acc.n_transmembrane + 1}
  end

  # All other domain types (dna_binding, regulator_output, ligand_sensor,
  # channel_pore) are parsed but not yet aggregated into the Phase 3 phenotype.
  # Phase 5+ will use them for metabolic regulation and signal integration.
  defp aggregate_domain(_type, _params, acc), do: acc

  defp build_phenotype(acc) do
    %__MODULE__{
      base_growth_rate: mean_or_default(acc.kcat_values, 0.1) |> clamp(0.0, 1.0),
      substrate_affinities: acc.substrate_affinities,
      energy_cost: Enum.sum(acc.atp_costs) |> clamp(0.0, 5.0),
      surface_tags: Enum.reverse(acc.surface_tags),
      repair_efficiency: mean_or_default(acc.repair_efficiencies, 0.5) |> clamp(0.0, 1.0),
      structural_stability: mean_or_default(acc.stability_values, 0.5) |> clamp(0.0, 1.0),
      n_transmembrane: acc.n_transmembrane
    }
  end

  defp mean_or_default([], default), do: default

  defp mean_or_default(values, _default) do
    Enum.sum(values) / length(values)
  end

  defp clamp(value, lo, hi), do: value |> max(lo) |> min(hi)
end
