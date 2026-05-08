defmodule Arkea.Views.GenomeDiff do
  @moduledoc """
  Pure view-model for the macro-level genome diff between two
  lineages (Phase 22 / 2.3a).

  Given two `Genome.t()` (call them A and B), computes:

  - **Chromosome genes** — the set of genes shared between A and B
    (same canonical `codons` sequence) plus the genes unique to A
    or unique to B.
  - **Plasmids** — same partitioning, with plasmid identity =
    `{inc_group, sorted gene signatures}`. `copy_number` and
    `oriT_present` are reported alongside but not part of the
    identity (a plasmid that mutated copy_number is "still the
    same plasmid").
  - **Prophages** — partitioning by sorted gene signatures only;
    `state` and `repressor_strength` reported as side data.
  - **Phenotype delta** — round-tripped through
    `Arkea.Sim.Phenotype.from_genome/1` to surface the headline
    scalars (`base_growth_rate`, `repair_efficiency`,
    `energy_cost`, `n_transmembrane`, `dna_binding_affinity`,
    `hydrolase_capacity`, `efflux_capacity`, `biofilm_capable?`).

  Identity is computed on the *canonical codon sequence*, not on
  `Gene.id` (which is a fresh UUIDv4 at construction; two
  identically-coded genes carry different ids). The signature is
  `:erlang.phash2(gene.codons)` — a 27-bit fast hash deterministic
  on Erlang/OTP for any term, so it survives marshalling and is
  cheaper than a full equality compare on long codon lists.

  Codon-level diff (per-position substitution / indel / inversion /
  duplication enumeration) is *out of scope* here — that is Phase 26
  (`:domain_flip`, `:gene_chimera_birth` audit events + the codon
  viewer). The macro view answers "*what's different*" at the gene
  granularity; the codon viewer will answer "*how it differs* inside
  one shared gene's pair of variants".
  """

  alias Arkea.Genome
  alias Arkea.Genome.Gene
  alias Arkea.Sim.Phenotype

  @type gene_summary :: %{
          id: String.t(),
          signature: integer(),
          codon_count: non_neg_integer(),
          domain_count: non_neg_integer(),
          domain_types: [atom()]
        }

  @type plasmid_summary :: %{
          identity: {non_neg_integer(), [integer()]},
          inc_group: non_neg_integer(),
          copy_number: pos_integer(),
          oriT_present: boolean(),
          gene_count: non_neg_integer()
        }

  @type prophage_summary :: %{
          identity: [integer()],
          state: atom(),
          repressor_strength: float(),
          gene_count: non_neg_integer()
        }

  @type chromosome_diff :: %{
          shared: [gene_summary()],
          a_only: [gene_summary()],
          b_only: [gene_summary()]
        }

  @type plasmid_diff :: %{
          shared: [plasmid_summary()],
          a_only: [plasmid_summary()],
          b_only: [plasmid_summary()]
        }

  @type prophage_diff :: %{
          shared: [prophage_summary()],
          a_only: [prophage_summary()],
          b_only: [prophage_summary()]
        }

  @type phenotype_delta :: %{
          base_growth_rate: float(),
          repair_efficiency: float(),
          energy_cost: float(),
          n_transmembrane: integer(),
          dna_binding_affinity: float(),
          hydrolase_capacity: float(),
          efflux_capacity: float(),
          biofilm_capable_changed: boolean()
        }

  @type t :: %{
          chromosome: chromosome_diff(),
          plasmids: plasmid_diff(),
          prophages: prophage_diff(),
          phenotype_delta: phenotype_delta(),
          identical?: boolean()
        }

  @doc """
  Build the diff. Genomes can be `nil` (delta-encoded descendants
  that haven't been materialised yet); a `nil` side is treated as
  an empty genome. Returns `identical?: true` when both sides
  partition into entirely-shared sets.
  """
  @spec build(Genome.t() | nil, Genome.t() | nil) :: t()
  def build(genome_a, genome_b) do
    chromosome = chromosome_diff(genes_of(genome_a), genes_of(genome_b))
    plasmids = plasmid_diff(plasmids_of(genome_a), plasmids_of(genome_b))
    prophages = prophage_diff(prophages_of(genome_a), prophages_of(genome_b))
    phenotype_delta = phenotype_delta(genome_a, genome_b)

    identical? =
      chromosome.a_only == [] and chromosome.b_only == [] and
        plasmids.a_only == [] and plasmids.b_only == [] and
        prophages.a_only == [] and prophages.b_only == []

    %{
      chromosome: chromosome,
      plasmids: plasmids,
      prophages: prophages,
      phenotype_delta: phenotype_delta,
      identical?: identical?
    }
  end

  defp genes_of(nil), do: []
  defp genes_of(%Genome{chromosome: c}), do: c

  defp plasmids_of(nil), do: []
  defp plasmids_of(%Genome{plasmids: p}), do: p

  defp prophages_of(nil), do: []
  defp prophages_of(%Genome{prophages: p}), do: p

  defp chromosome_diff(genes_a, genes_b) do
    by_sig_a = Map.new(genes_a, fn g -> {gene_signature(g), gene_summary(g)} end)
    by_sig_b = Map.new(genes_b, fn g -> {gene_signature(g), gene_summary(g)} end)

    sigs_a = MapSet.new(Map.keys(by_sig_a))
    sigs_b = MapSet.new(Map.keys(by_sig_b))

    shared_sigs = MapSet.intersection(sigs_a, sigs_b)

    %{
      shared: shared_sigs |> Enum.map(&Map.fetch!(by_sig_a, &1)) |> Enum.sort_by(& &1.signature),
      a_only:
        sigs_a
        |> MapSet.difference(sigs_b)
        |> Enum.map(&Map.fetch!(by_sig_a, &1))
        |> Enum.sort_by(& &1.signature),
      b_only:
        sigs_b
        |> MapSet.difference(sigs_a)
        |> Enum.map(&Map.fetch!(by_sig_b, &1))
        |> Enum.sort_by(& &1.signature)
    }
  end

  defp plasmid_diff(plasmids_a, plasmids_b) do
    by_id_a = Map.new(plasmids_a, fn p -> {plasmid_identity(p), plasmid_summary(p)} end)
    by_id_b = Map.new(plasmids_b, fn p -> {plasmid_identity(p), plasmid_summary(p)} end)

    ids_a = MapSet.new(Map.keys(by_id_a))
    ids_b = MapSet.new(Map.keys(by_id_b))
    shared_ids = MapSet.intersection(ids_a, ids_b)

    %{
      shared: shared_ids |> Enum.map(&Map.fetch!(by_id_a, &1)) |> sort_plasmids(),
      a_only:
        ids_a
        |> MapSet.difference(ids_b)
        |> Enum.map(&Map.fetch!(by_id_a, &1))
        |> sort_plasmids(),
      b_only:
        ids_b
        |> MapSet.difference(ids_a)
        |> Enum.map(&Map.fetch!(by_id_b, &1))
        |> sort_plasmids()
    }
  end

  defp prophage_diff(prophages_a, prophages_b) do
    by_id_a = Map.new(prophages_a, fn p -> {prophage_identity(p), prophage_summary(p)} end)
    by_id_b = Map.new(prophages_b, fn p -> {prophage_identity(p), prophage_summary(p)} end)

    ids_a = MapSet.new(Map.keys(by_id_a))
    ids_b = MapSet.new(Map.keys(by_id_b))
    shared_ids = MapSet.intersection(ids_a, ids_b)

    %{
      shared: shared_ids |> Enum.map(&Map.fetch!(by_id_a, &1)) |> sort_prophages(),
      a_only:
        ids_a
        |> MapSet.difference(ids_b)
        |> Enum.map(&Map.fetch!(by_id_a, &1))
        |> sort_prophages(),
      b_only:
        ids_b
        |> MapSet.difference(ids_a)
        |> Enum.map(&Map.fetch!(by_id_b, &1))
        |> sort_prophages()
    }
  end

  defp gene_signature(%Gene{codons: codons}), do: :erlang.phash2(codons)

  defp gene_summary(%Gene{} = gene) do
    %{
      id: gene.id,
      signature: gene_signature(gene),
      codon_count: length(gene.codons),
      domain_count: length(gene.domains),
      domain_types: Enum.map(gene.domains, & &1.type)
    }
  end

  defp plasmid_identity(%{inc_group: inc, genes: genes}) do
    {inc, genes |> Enum.map(&gene_signature/1) |> Enum.sort()}
  end

  defp plasmid_summary(%{inc_group: inc, copy_number: cn, oriT_present: orit, genes: genes} = p) do
    %{
      identity: plasmid_identity(p),
      inc_group: inc,
      copy_number: cn,
      oriT_present: orit,
      gene_count: length(genes)
    }
  end

  defp prophage_identity(%{genes: genes}) do
    genes |> Enum.map(&gene_signature/1) |> Enum.sort()
  end

  defp prophage_summary(%{state: state, repressor_strength: r, genes: genes} = p) do
    %{
      identity: prophage_identity(p),
      state: state,
      repressor_strength: r,
      gene_count: length(genes)
    }
  end

  defp sort_plasmids(list), do: Enum.sort_by(list, &{&1.inc_group, &1.gene_count})
  defp sort_prophages(list), do: Enum.sort_by(list, & &1.gene_count)

  defp phenotype_delta(nil, _), do: zero_phenotype_delta()
  defp phenotype_delta(_, nil), do: zero_phenotype_delta()

  defp phenotype_delta(%Genome{} = ga, %Genome{} = gb) do
    pa = Phenotype.from_genome(ga)
    pb = Phenotype.from_genome(gb)

    %{
      base_growth_rate: round_delta(pb.base_growth_rate - pa.base_growth_rate),
      repair_efficiency: round_delta(pb.repair_efficiency - pa.repair_efficiency),
      energy_cost: round_delta(pb.energy_cost - pa.energy_cost),
      n_transmembrane: pb.n_transmembrane - pa.n_transmembrane,
      dna_binding_affinity: round_delta(pb.dna_binding_affinity - pa.dna_binding_affinity),
      hydrolase_capacity: round_delta(pb.hydrolase_capacity - pa.hydrolase_capacity),
      efflux_capacity: round_delta(pb.efflux_capacity - pa.efflux_capacity),
      biofilm_capable_changed: pa.biofilm_capable? != pb.biofilm_capable?
    }
  end

  defp zero_phenotype_delta do
    %{
      base_growth_rate: 0.0,
      repair_efficiency: 0.0,
      energy_cost: 0.0,
      n_transmembrane: 0,
      dna_binding_affinity: 0.0,
      hydrolase_capacity: 0.0,
      efflux_capacity: 0.0,
      biofilm_capable_changed: false
    }
  end

  defp round_delta(v), do: Float.round(v * 1.0, 4)
end
