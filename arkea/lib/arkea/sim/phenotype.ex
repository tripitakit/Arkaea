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

  - `competence_score` — `0.0..1.0` proxy for the cell's ability to take
    up free DNA from the environment (Phase 13 — DESIGN.md Block 8).
    Naturally competent species (e.g. *Streptococcus*, *Bacillus*,
    *Haemophilus*; Johnston et al. 2014) express a coordinated set of
    machinery: a DNA channel (`:channel_pore`), membrane integration
    (`:transmembrane_anchor`), and a stress / quorum sensor that gates
    competence (`:ligand_sensor`). The score is non-zero only when all
    three categories are present and grows with the geometric mean of
    their counts, capped at `1.0`. Naïve genomes that lack any of the
    three categories sit at zero — competence is *not* the default.

  - `detoxify_targets` — set of metabolite atom ids the genome can
    detoxify (Phase 14 — DESIGN.md Block 8.A.2). A
    `:catalytic_site(reaction_class: :reduction)` co-located with a
    `:substrate_binding` whose target is one of the toxic metabolites
    (O₂, H₂S, lactate) protects the cell from that specific stressor.
    `Arkea.Sim.Metabolism.toxicity_factor/2` uses the set to bypass
    toxicity contributions for owned targets — this is how
    catalase-like, sulfide-oxidoreductase-like, and lactate-dehydrogenase-like
    activities emerge generatively.

  - `target_classes` — `%{atom() => float()}` map of cellular targets
    that xenobiotics may bind (Phase 15 — DESIGN.md Block 8). Each
    entry is a non-negative *abundance index* derived from gene
    composition:

      - `:pbp_like` — penicillin-binding-protein analogue: gene with
        co-occurring `:transmembrane_anchor` + `:catalytic_site`. Drives
        β-lactam susceptibility.
      - `:dna_polymerase_like` — gene with co-occurring `:dna_binding`
        + `:catalytic_site`. Drives susceptibility to
        polymerase-targeting drugs (rifampicin-class).
      - `:ribosome_like` — every cell has ribosomes; pinned to `1.0`
        as a baseline to model intrinsic susceptibility to
        translation-targeting drugs (aminoglycosides, tetracyclines).
      - `:membrane` — `n_transmembrane` indexed; drives
        membrane-disrupting drug susceptibility.

    Lineages without a given target class are intrinsically resistant
    to drugs that bind that class — the cleanest of the three Phase 15
    resistance pathways.

  - `hydrolase_capacity` — `0.0..∞` proxy for β-lactamase-like
    enzymatic resistance (Phase 15 — DESIGN.md Block 8). Counts genes
    that co-express `:substrate_binding` and `:catalytic_site` with
    `reaction_class: :hydrolysis`. The scalar feeds
    `Arkea.Sim.Xenobiotic.degradation_amount/3` — a hydrolase-bearing
    population shrinks the drug pool over time.

  - `efflux_capacity` — `0.0..1.0` proxy for active efflux pumping
    (Phase 15). A "pump" is a gene that co-encodes
    `:transmembrane_anchor + :channel_pore + :energy_coupling +
    :substrate_binding`; the scalar grows with the count of such genes
    capped at `1.0`. Used by
    `Arkea.Sim.Xenobiotic.intracellular_concentration/2` to scale
    effective drug exposure.

  - `biofilm_capable?` — boolean flag (Phase 18 — DESIGN.md Block 8).
    `true` when the genome encodes both an adhesion structure (any
    `:surface_tag`) and a matrix-like structural protein (any
    `:structural_fold` with `multimerization_n ≥ 2`). The two-prong
    requirement keeps the flag conservative: presence of just a
    surface tag (a single adhesin molecule) is not enough to form
    biofilm; the cell also needs the multimerising protein that
    cross-links the extracellular matrix. Biofilm-capable lineages
    enjoy a per-tick dilution discount in `Tick.step_environment/1`
    — the analogue of the protective EPS layer that shields biofilm
    members from chemostat washout.
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
    field :competence_score, float(), default: 0.0
    field :detoxify_targets, MapSet.t(atom()), default: MapSet.new()
    field :target_classes, %{atom() => float()}, default: %{}
    field :hydrolase_capacity, float(), default: 0.0
    field :efflux_capacity, float(), default: 0.0
    field :biofilm_capable?, boolean(), default: false
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
        methylation_profile: meth,
        competence_score: competence_score(domains),
        detoxify_targets: detoxify_targets(genome),
        target_classes: target_classes(genome),
        hydrolase_capacity: hydrolase_capacity(genome),
        efflux_capacity: efflux_capacity(genome),
        biofilm_capable?: biofilm_capable?(domains)
    }
  end

  @doc """
  Compute the Phase-18 biofilm capability flag for a domain list.

  The cell is biofilm-capable when it carries both a surface tag
  (adhesin / anchoring protein) and a multimerising structural
  protein (`:structural_fold` with `multimerization_n ≥ 2`, the
  matrix proxy). Single-molecule adhesins without matrix scaffolding
  do not form biofilms.
  """
  @spec biofilm_capable?([Domain.t()]) :: boolean()
  def biofilm_capable?(domains) when is_list(domains) do
    has_surface = Enum.any?(domains, fn d -> d.type == :surface_tag end)

    has_matrix =
      Enum.any?(domains, fn d ->
        d.type == :structural_fold and (d.params[:multimerization_n] || 1) >= 2
      end)

    has_surface and has_matrix
  end

  @doc """
  Compute the set of metabolites the genome can actively detoxify.

  A *detoxify activity* in Arkea is the co-occurrence within the same
  gene of:

    - a `:substrate_binding` domain whose `target_metabolite_id` maps
      to one of the toxic metabolites (O₂, H₂S, lactate); and
    - a `:catalytic_site` whose `reaction_class` is `:reduction`.

  The combination is the generative analogue of catalase
  (`:reduction` of O₂), sulfide:quinone oxidoreductase (`:reduction`
  of H₂S in this simplified model), and lactate dehydrogenase. Real
  enzymology is more nuanced (sulfide is *oxidised*, not reduced, by
  SQR), but Arkea collapses both donor- and acceptor-side enzymatic
  detoxification into one categorical pattern; the biological
  consequence — the cell stops dying — is preserved.
  """
  @spec detoxify_targets(Genome.t()) :: MapSet.t(atom())
  def detoxify_targets(%Genome{} = genome) do
    toxic_set = MapSet.new(Metabolism.toxic_metabolites())

    genome
    |> Genome.all_genes()
    |> Enum.reduce(MapSet.new(), fn gene, acc ->
      MapSet.union(acc, gene_detoxify_targets(gene, toxic_set))
    end)
  end

  defp gene_detoxify_targets(%Gene{domains: domains}, toxic_set) do
    has_reduction =
      Enum.any?(domains, fn d ->
        d.type == :catalytic_site and d.params[:reaction_class] == :reduction
      end)

    if has_reduction do
      domains
      |> Enum.filter(fn d -> d.type == :substrate_binding end)
      |> Enum.map(fn d -> Metabolism.metabolite_atom(d.params[:target_metabolite_id]) end)
      |> Enum.filter(&MapSet.member?(toxic_set, &1))
      |> MapSet.new()
    else
      MapSet.new()
    end
  end

  @doc """
  Compute the per-target-class abundance index for the genome (Phase 15).

  Walks every gene, classifies it against the four xenobiotic target
  archetypes, and returns a `%{atom() => float()}` map. Counts are
  normalised by `0.2` so a single specialised gene contributes 0.2,
  three contribute 0.6, five saturate at 1.0. Saturation matches the
  biological observation that a handful of proteins is enough to be
  fully susceptible — duplications do not deepen the susceptibility.

  `:ribosome_like` is pinned to `1.0` as a baseline: every cell has
  ribosomes, regardless of explicit gene composition. This keeps
  translation-targeting drugs from having a free pass on under-specified
  genomes.
  """
  @spec target_classes(Genome.t()) :: %{atom() => float()}
  def target_classes(%Genome{} = genome) do
    genes = Genome.all_genes(genome)

    pbp = Enum.count(genes, &pbp_like?/1)
    pol = Enum.count(genes, &polymerase_like?/1)
    membrane = count_domains_of_type(genome, :transmembrane_anchor)

    %{
      pbp_like: count_to_index(pbp),
      dna_polymerase_like: count_to_index(pol),
      ribosome_like: 1.0,
      membrane: count_to_index(membrane)
    }
  end

  @doc """
  Aggregate hydrolase capacity (Phase 15).

  A "hydrolase" gene co-encodes a `:substrate_binding` and a
  `:catalytic_site(reaction_class: :hydrolysis)`. The capacity is the
  count of such genes — unbounded above, since β-lactamases can
  duplicate freely and population-level degradation should compound.
  """
  @spec hydrolase_capacity(Genome.t()) :: float()
  def hydrolase_capacity(%Genome{} = genome) do
    genome
    |> Genome.all_genes()
    |> Enum.count(&hydrolase_like?/1)
    |> Kernel./(1.0)
  end

  @doc """
  Aggregate efflux pump capacity (Phase 15).

  An efflux gene co-encodes the four-domain pattern
  `:transmembrane_anchor + :channel_pore + :energy_coupling +
  :substrate_binding`. The scalar grows with count and saturates at
  `1.0` — a 10× pump (90% extracellular dilution) is biologically the
  upper bound for a single efflux family.
  """
  @spec efflux_capacity(Genome.t()) :: float()
  def efflux_capacity(%Genome{} = genome) do
    n =
      genome
      |> Genome.all_genes()
      |> Enum.count(&efflux_like?/1)

    min(1.0, n * 0.5)
  end

  defp pbp_like?(%Gene{domains: domains}) do
    has_type?(domains, :transmembrane_anchor) and has_type?(domains, :catalytic_site)
  end

  defp polymerase_like?(%Gene{domains: domains}) do
    has_type?(domains, :dna_binding) and has_type?(domains, :catalytic_site)
  end

  defp hydrolase_like?(%Gene{domains: domains}) do
    has_type?(domains, :substrate_binding) and
      Enum.any?(domains, fn d ->
        d.type == :catalytic_site and d.params[:reaction_class] == :hydrolysis
      end)
  end

  defp efflux_like?(%Gene{domains: domains}) do
    has_type?(domains, :transmembrane_anchor) and
      has_type?(domains, :channel_pore) and
      has_type?(domains, :energy_coupling) and
      has_type?(domains, :substrate_binding)
  end

  defp has_type?(domains, type), do: Enum.any?(domains, fn d -> d.type == type end)

  defp count_domains_of_type(%Genome{} = genome, type) do
    genome
    |> Genome.all_domains()
    |> Enum.count(fn d -> d.type == type end)
  end

  defp count_to_index(n), do: min(1.0, n * 0.2)

  @doc """
  Compute the natural-transformation competence score for a domain list.

  Three categories must all be present for any uptake to happen:

  - `:channel_pore` — the DNA-conducting pore (proxy for ComEC/ComEA);
  - `:transmembrane_anchor` — anchors the channel to the membrane
    (proxy for the type IV pilus-like uptake apparatus);
  - `:ligand_sensor` — the inducer that switches the cell into the
    competent state (proxy for ComX / cAMP-like signalling).

  When any one is absent the score is `0.0` (no competence at all).
  Otherwise the score is the geometric mean of the three counts scaled
  by `0.2`, capped at `1.0` — three of each domain is enough to nearly
  saturate the score, matching the order-of-magnitude observation that
  competence machinery does not improve indefinitely with copy number
  in vivo.
  """
  @spec competence_score([Domain.t()]) :: float()
  def competence_score(domains) when is_list(domains) do
    n_channel = Enum.count(domains, fn d -> d.type == :channel_pore end)
    n_membrane = Enum.count(domains, fn d -> d.type == :transmembrane_anchor end)
    n_sensor = Enum.count(domains, fn d -> d.type == :ligand_sensor end)

    if n_channel == 0 or n_membrane == 0 or n_sensor == 0 do
      0.0
    else
      geom_mean = :math.pow(n_channel * n_membrane * n_sensor, 1.0 / 3.0)
      min(1.0, geom_mean * 0.2)
    end
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
