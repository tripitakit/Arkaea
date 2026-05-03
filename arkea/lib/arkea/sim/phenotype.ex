defmodule Arkea.Sim.Phenotype do
  @moduledoc """
  Emergent phenotype derived from a genome by aggregating functional domain
  parameters (Phase 3/5 — IMPLEMENTATION-PLAN.md §6).

  This module is **strictly pure**: no OTP, no I/O, no side effects.

  ## Design

  The phenotype is the bridge between the genotype (a `Genome.t()` with its
  typed functional domains) and the simulation tick (`Arkea.Sim.Tick`). It
  aggregates raw domain parameters into biological properties that feed
  `step_expression/1` (Phase 3) and `step_metabolism/1` (Phase 5).

  ### Aggregation rules

  - `base_growth_rate` — mean of `:kcat` from all `:catalytic_site` domains,
    clamped to `0.0..1.0`. Default `0.1` when no catalytic domains are present
    (minimal basal metabolism).

  - `substrate_affinities` — map `metabolite_atom => %{km: float, kcat: float}`
    built from all `:substrate_binding` domains. Keys are **canonical atom keys**
    (`:glucose`, `:oxygen`, …) mapped from the integer `target_metabolite_id`
    via `Arkea.Sim.Metabolism.metabolite_atom/1` (Phase 5 change). When multiple
    domains bind the same metabolite, the **last** one encountered in gene-order
    wins (simple override rule).

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

  - `dna_binding_affinity` — mean of `:binding_affinity` from all
    `:dna_binding` domains, clamped to `0.0..1.0`. Default `0.0`. Used in
    Phase 5 as a σ-factor scalar: `sigma = 0.5 + dna_binding_affinity`, in
    `0.5..1.5`. Phase 7 extends this with a QS boost term.

  - `qs_produces` — list of `{signal_key, kcat}` from all `:catalytic_site`
    domains with `kcat > 0`. Used in Phase 7 `step_signaling/1` to add signals
    to the phase signal pool. `signal_key` is the first 4 parameter codons
    joined as `"c0,c1,c2,c3"`.

  - `qs_receives` — list of `{signal_key, threshold}` from all `:ligand_sensor`
    domains. Used in Phase 7 to compute the σ-factor QS boost for `step_expression/1`.

  - `restriction_profile` — list of `signal_key`s of restriction enzymes
    encoded by the genome (Phase 12 — DESIGN.md Block 8). A gene is a
    restriction enzyme when it contains *both* a `:dna_binding` and a
    `:catalytic_site(reaction_class: :hydrolysis)` domain; the
    catalytic site's `signal_key` is the recognition site. Used by
    `Arkea.Sim.HGT.Defense.restriction_check/3` as an immunity gate
    against incoming HGT payloads.

  - `methylation_profile` — list of `signal_key`s of methylases (the M
    component of an R-M system). A gene is a methylase when it contains
    *both* a `:dna_binding` and a `:catalytic_site(reaction_class:
    :isomerization)` domain; the catalytic site's `signal_key` is the
    methylation site. Used by `Arkea.Sim.HGT.Defense.restriction_check/3`
    via the *donor methylation* the payload carries — this is the
    Arber-Dussoix host-modification mechanism: DNA replicated in a cell
    that already methylates a recognition site is no longer cleaved by
    that site's restriction enzyme.
  """

  use TypedStruct

  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Sim.Metabolism

  typedstruct enforce: true do
    field :base_growth_rate, float()
    field :substrate_affinities, %{atom() => %{km: float(), kcat: float()}}
    field :energy_cost, float()
    field :surface_tags, [atom()]
    field :repair_efficiency, float()
    field :structural_stability, float()
    field :n_transmembrane, non_neg_integer()
    field :dna_binding_affinity, float()
    field :qs_produces, [{binary(), float()}], default: []
    field :qs_receives, [{binary(), float()}], default: []
    field :restriction_profile, [binary()], default: []
    field :methylation_profile, [binary()], default: []
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
    %{restriction_profile: rest, methylation_profile: meth} = rm_profiles(genome)

    %{
      aggregate(domains)
      | restriction_profile: rest,
        methylation_profile: meth
    }
  end

  # Scan every gene for restriction-modification (R-M) signatures.
  #
  # A *restriction enzyme* is a gene with co-occurring `:dna_binding` and
  # `:catalytic_site(reaction_class: :hydrolysis)` domains: the `signal_key`
  # of the catalytic site is the cleavage recognition site.
  #
  # A *methylase* is the same construction with reaction_class
  # `:isomerization` (modify rather than cleave): the `signal_key` is the
  # protected recognition site that "imprints" host DNA.
  #
  # The two lists are independent because a gene can encode both activities,
  # but typically R-M systems split them across two adjacent genes. Either
  # split is supported here.
  @spec rm_profiles(Genome.t()) :: %{
          restriction_profile: [binary()],
          methylation_profile: [binary()]
        }
  def rm_profiles(%Genome{} = genome) do
    {rest, methyl} =
      genome
      |> Genome.all_genes()
      |> Enum.reduce({[], []}, fn gene, {rest_acc, methyl_acc} ->
        if gene_has_dna_binding?(gene) do
          gene
          |> catalytic_signal_keys_by_reaction(:hydrolysis)
          |> Enum.reduce({rest_acc, methyl_acc}, fn key, {r, m} -> {[key | r], m} end)
          |> then(fn {r, m} ->
            keys = catalytic_signal_keys_by_reaction(gene, :isomerization)
            {r, Enum.reduce(keys, m, fn key, acc -> [key | acc] end)}
          end)
        else
          {rest_acc, methyl_acc}
        end
      end)

    %{
      restriction_profile: Enum.reverse(rest),
      methylation_profile: Enum.reverse(methyl)
    }
  end

  defp gene_has_dna_binding?(%Gene{domains: domains}) do
    Enum.any?(domains, fn d -> d.type == :dna_binding end)
  end

  defp catalytic_signal_keys_by_reaction(%Gene{domains: domains}, reaction_class) do
    domains
    |> Enum.filter(fn d ->
      d.type == :catalytic_site and d.params[:reaction_class] == reaction_class
    end)
    |> Enum.map(fn d -> d.params[:signal_key] end)
    |> Enum.reject(&is_nil/1)
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
      n_transmembrane: 0,
      dna_binding_affinities: [],
      qs_produces: [],
      qs_receives: []
    }
  end

  defp aggregate_domain(:catalytic_site, %{kcat: kcat, signal_key: sig_key}, acc) do
    entry = if kcat > 0, do: [{sig_key, kcat}], else: []
    %{acc | kcat_values: [kcat | acc.kcat_values], qs_produces: entry ++ acc.qs_produces}
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

  defp aggregate_domain(:dna_binding, %{binding_affinity: affinity}, acc) do
    %{acc | dna_binding_affinities: [affinity | acc.dna_binding_affinities]}
  end

  defp aggregate_domain(:ligand_sensor, %{threshold: threshold, signal_key: sig_key}, acc) do
    %{acc | qs_receives: [{sig_key, threshold} | acc.qs_receives]}
  end

  # All other domain types (regulator_output, channel_pore, etc.)
  # are parsed but not yet aggregated into the phenotype.
  defp aggregate_domain(_type, _params, acc), do: acc

  defp build_phenotype(acc) do
    # Phase 5: convert integer target_metabolite_id keys to canonical atom keys.
    # `Metabolism.metabolite_atom/1` maps 0..12 → :glucose..:po4 (Block 6).
    atom_affinities =
      Map.new(acc.substrate_affinities, fn {int_id, entry} ->
        {Metabolism.metabolite_atom(int_id), entry}
      end)

    %__MODULE__{
      base_growth_rate: mean_or_default(acc.kcat_values, 0.1) |> clamp(0.0, 1.0),
      substrate_affinities: atom_affinities,
      energy_cost: Enum.sum(acc.atp_costs) |> clamp(0.0, 5.0),
      surface_tags: Enum.reverse(acc.surface_tags),
      repair_efficiency: mean_or_default(acc.repair_efficiencies, 0.5) |> clamp(0.0, 1.0),
      structural_stability: mean_or_default(acc.stability_values, 0.5) |> clamp(0.0, 1.0),
      n_transmembrane: acc.n_transmembrane,
      dna_binding_affinity: mean_or_default(acc.dna_binding_affinities, 0.0) |> clamp(0.0, 1.0),
      qs_produces: acc.qs_produces,
      qs_receives: acc.qs_receives
    }
  end

  defp mean_or_default([], default), do: default

  defp mean_or_default(values, _default) do
    Enum.sum(values) / length(values)
  end

  defp clamp(value, lo, hi), do: value |> max(lo) |> min(hi)
end
