defmodule Arkea.Genome do
  @moduledoc """
  Container of the complete genetic material of a cell line:
  chromosome + plasmids + integrated prophages (DESIGN.md Block 4 / Block 5).

  Phase 1: only `chromosome` is populated. `plasmids` and `prophages` are
  empty lists, but already typed and structurally present.

  ## Field semantics

  - `chromosome` — the canonical, vertically inherited list of genes. Must
    be non-empty.
  - `plasmids` — list of plasmid structs (Phase 16 — see `plasmid()` type).
    Each plasmid carries its genes plus three regulatory traits derived
    from the genes themselves: `inc_group` (incompatibility hash that
    drives co-residence displacement, Novick 1987), `copy_number`
    (replication burden vs. gene-dosage benefit trade-off, San Millán
    & MacLean 2018) and `oriT_present` (origin-of-transfer flag for
    conjugative mobilisation).
  - `prophages` — list of prophage cassettes integrated into the genome
    (Phase 12 — see `prophage()` type). Each cassette carries its viral
    genes plus an explicit `state` (`:lysogenic | :induced`) and a
    `repressor_strength` (0.0..1.0) controlling how easily the lysogenic
    repressor is overridden by stress / SOS-driven induction.
  - `gene_count` — cached total count of genes across chromosome + all
    plasmids + all prophages. Used by Phase 6 plasmid-cost calculations.
  """

  use TypedStruct

  alias Arkea.Genome.Gene

  @typedoc """
  An integrated prophage cassette.

  - `genes` — viral genes (receptor, lysogenic repressor, viral
    polymerase, capsid subunits, lysis genes).
  - `state` — `:lysogenic` (silent, replicates with the chromosome) or
    `:induced` (committed to the lytic cycle this tick).
  - `repressor_strength` — 0.0..1.0; the higher the value, the harder it
    is to flip from `:lysogenic` to `:induced` under stress.
  """
  @type prophage :: %{
          genes: [Gene.t()],
          state: :lysogenic | :induced,
          repressor_strength: float()
        }

  @typedoc """
  An extra-chromosomal plasmid (Phase 16 — DESIGN.md Block 8).

  - `genes` — vertically inherited gene set carried by the plasmid.
  - `inc_group` — `0..@inc_group_modulus-1` integer derived from the
    plasmid's gene composition. Two plasmids with the same
    `inc_group` cannot stably co-reside in the same lineage —
    `Arkea.Sim.HGT` resolves the conflict by displacing the older
    one (Novick 1987 incompatibility model, simplified).
  - `copy_number` — `1..@max_copy_number` replication burden /
    gene-dosage exponent. Derived from the count of `:dna_binding`
    domains in the plasmid's genes (proxy for replication-control
    repressor binding sites): more sites → tighter control → higher
    copy number, since stringent repression is what limits low-copy
    plasmids in vivo (San Millán & MacLean 2018).
  - `oriT_present` — `true` when at least one plasmid gene carries an
    `orit_site` intergenic block; required for conjugative
    mobilisation, as `Arkea.Sim.Intergenic.transfer_probability_multiplier/3`
    already biases transfer rate on this annotation.
  """
  @type plasmid :: %{
          genes: [Gene.t()],
          inc_group: non_neg_integer(),
          copy_number: pos_integer(),
          oriT_present: boolean()
        }

  @inc_group_modulus 7
  @max_copy_number 10

  typedstruct enforce: true do
    field :chromosome, [Gene.t()]
    field :plasmids, [plasmid()], default: []
    field :prophages, [prophage()], default: []
    field :gene_count, non_neg_integer()
  end

  @doc """
  Build a genome from a non-empty chromosome.

  Optional keyword args: `:plasmids`, `:prophages`. Computes `gene_count`.
  Pure. Raises if `chromosome` is empty or any gene is invalid.

  Accepts both:
    - `:plasmids` as a list of gene-lists (legacy / convenience) — each
      gene list is wrapped via `normalize_plasmid/1` (Phase 16 derives
      `inc_group`, `copy_number`, `oriT_present` from the genes);
    - `:plasmids` as a list of `plasmid()` maps — used as-is.
    - `:prophages` analogous: accepts either gene-lists or `prophage()`
      maps.
  """
  @spec new([Gene.t()], keyword()) :: t()
  def new(chromosome, opts \\ [])

  def new([], _opts), do: raise(ArgumentError, "chromosome must not be empty")

  def new(chromosome, opts) when is_list(chromosome) do
    plasmids = opts |> Keyword.get(:plasmids, []) |> Enum.map(&normalize_plasmid/1)
    prophages = opts |> Keyword.get(:prophages, []) |> Enum.map(&normalize_prophage/1)

    unless valid_gene_list?(chromosome) and
             Enum.all?(plasmids, &valid_plasmid?/1) and
             Enum.all?(prophages, &valid_prophage?/1) do
      raise ArgumentError, "all genes in chromosome, plasmids, and prophages must be valid"
    end

    %__MODULE__{
      chromosome: chromosome,
      plasmids: plasmids,
      prophages: prophages,
      gene_count: count_genes(chromosome, plasmids, prophages)
    }
  end

  @doc """
  Concatenation of all genes across chromosome, plasmids, and prophages.
  Order: chromosome first, then plasmids in order, then prophages in order.
  """
  @spec all_genes(t()) :: [Gene.t()]
  def all_genes(%__MODULE__{chromosome: c, plasmids: p, prophages: pr}) do
    c ++ Enum.flat_map(p, & &1.genes) ++ Enum.flat_map(pr, & &1.genes)
  end

  @doc """
  Concatenation of all `Domain.t()` structs across every gene in the genome.

  Traverses chromosome, plasmids, and prophages in order (same as `all_genes/1`).
  Each gene's `domains` list is flattened in gene order.

  Used by `Arkea.Sim.Phenotype.from_genome/1` to aggregate functional domains
  into the emergent phenotype without coupling Phenotype to Gene internals.
  """
  @spec all_domains(t()) :: [Arkea.Genome.Domain.t()]
  def all_domains(%__MODULE__{} = genome) do
    genome
    |> all_genes()
    |> Enum.flat_map(& &1.domains)
  end

  @doc "Cached total gene count (O(1))."
  @spec gene_count(t()) :: non_neg_integer()
  def gene_count(%__MODULE__{gene_count: n}), do: n

  @doc """
  Add a plasmid. Recomputes `gene_count`. Pure.

  Accepts either:
    - a `[Gene.t()]` gene-list (legacy / convenience) — wrapped via
      `normalize_plasmid/1`;
    - a `plasmid()` map for explicit control of inc_group / copy_number /
      oriT_present.

  Phase 16: when adding a plasmid whose `inc_group` collides with one
  already resident in the genome, the resident is *displaced* — the new
  plasmid takes its slot. This implements the simplified Novick (1987)
  incompatibility rule used by `Arkea.Sim.HGT` for transconjugant
  resolution. Use `set_plasmids/2` if you need to keep both (only
  meaningful for ephemeral states like the planning side of migration).
  """
  @spec add_plasmid(t(), [Gene.t()] | plasmid()) :: t()
  def add_plasmid(%__MODULE__{} = genome, plasmid_or_genes) do
    incoming = normalize_plasmid(plasmid_or_genes)

    unless valid_plasmid?(incoming) do
      raise ArgumentError, "plasmid genes must all be valid"
    end

    new_plasmids =
      Enum.reject(genome.plasmids, fn p -> p.inc_group == incoming.inc_group end) ++ [incoming]

    %{
      genome
      | plasmids: new_plasmids,
        gene_count: count_genes(genome.chromosome, new_plasmids, genome.prophages)
    }
  end

  @doc """
  Replace the plasmid list wholesale. Recomputes `gene_count`. Pure.

  Used by HGT channels (transformation, transduction) and migration
  planning when the displacement semantics of `add_plasmid/2` are the
  wrong default.
  """
  @spec set_plasmids(t(), [[Gene.t()] | plasmid()]) :: t()
  def set_plasmids(%__MODULE__{} = genome, new_plasmids) when is_list(new_plasmids) do
    normalised = Enum.map(new_plasmids, &normalize_plasmid/1)

    unless Enum.all?(normalised, &valid_plasmid?/1) do
      raise ArgumentError, "all plasmid entries must be valid"
    end

    %{
      genome
      | plasmids: normalised,
        gene_count: count_genes(genome.chromosome, normalised, genome.prophages)
    }
  end

  @doc """
  Integrate a prophage cassette. Recomputes `gene_count`. Pure.

  Accepts either:
    - a `[Gene.t()]` cassette (wrapped with `state: :lysogenic` and
      default `repressor_strength: 0.5`);
    - a `prophage()` map for explicit control of state / repressor.

  See the `prophage()` type for field semantics.
  """
  @spec integrate_prophage(t(), [Gene.t()] | prophage()) :: t()
  def integrate_prophage(%__MODULE__{} = genome, cassette_or_prophage) do
    prophage = normalize_prophage(cassette_or_prophage)

    unless valid_prophage?(prophage) do
      raise ArgumentError, "prophage cassette genes must all be valid"
    end

    new_prophages = genome.prophages ++ [prophage]

    %{
      genome
      | prophages: new_prophages,
        gene_count: count_genes(genome.chromosome, genome.plasmids, new_prophages)
    }
  end

  @doc """
  Replace the prophage list wholesale. Recomputes `gene_count`. Pure.

  Used by the lytic burst pipeline (Phase 12) to remove a cassette from the
  genome of a lysed lineage and by SOS-induction to flip a `state` field.
  """
  @spec set_prophages(t(), [prophage()]) :: t()
  def set_prophages(%__MODULE__{} = genome, new_prophages) when is_list(new_prophages) do
    unless Enum.all?(new_prophages, &valid_prophage?/1) do
      raise ArgumentError, "all prophage cassettes must be valid"
    end

    %{
      genome
      | prophages: new_prophages,
        gene_count: count_genes(genome.chromosome, genome.plasmids, new_prophages)
    }
  end

  @doc "True when the genome satisfies its structural invariants."
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{
        chromosome: chromosome,
        plasmids: plasmids,
        prophages: prophages,
        gene_count: gene_count
      }) do
    chromosome != [] and
      valid_gene_list?(chromosome) and
      Enum.all?(plasmids, &valid_plasmid?/1) and
      Enum.all?(prophages, &valid_prophage?/1) and
      gene_count == count_genes(chromosome, plasmids, prophages)
  end

  def valid?(_), do: false

  @doc "Validation with reason."
  @spec validate(t()) :: :ok | {:error, atom()}
  def validate(%__MODULE__{} = genome) do
    cond do
      genome.chromosome == [] ->
        {:error, :chromosome_empty}

      not valid_gene_list?(genome.chromosome) ->
        {:error, :invalid_gene_in_chromosome}

      not Enum.all?(genome.plasmids, &valid_plasmid?/1) ->
        {:error, :invalid_gene_in_plasmid}

      not Enum.all?(genome.prophages, &valid_prophage?/1) ->
        {:error, :invalid_gene_in_prophage}

      genome.gene_count != count_genes(genome.chromosome, genome.plasmids, genome.prophages) ->
        {:error, :gene_count_inconsistent}

      true ->
        :ok
    end
  end

  def validate(_), do: {:error, :not_a_genome}

  # ----------------------------------------------------------------------
  # Public helpers for the prophage shape

  @doc """
  Wrap a raw gene-list cassette into a prophage map with default lysogenic
  state and `repressor_strength: 0.5`. Idempotent on already-shaped maps.
  """
  @spec normalize_prophage([Gene.t()] | prophage()) :: prophage()
  def normalize_prophage(%{genes: genes} = prophage) when is_list(genes) do
    %{
      genes: genes,
      state: Map.get(prophage, :state, :lysogenic),
      repressor_strength: Map.get(prophage, :repressor_strength, 0.5)
    }
  end

  def normalize_prophage(genes) when is_list(genes) do
    %{genes: genes, state: :lysogenic, repressor_strength: 0.5}
  end

  @doc """
  Wrap a raw gene-list plasmid into a `plasmid()` map by deriving
  `inc_group`, `copy_number`, and `oriT_present` from the genes
  themselves (Phase 16 — DESIGN.md Block 8).

  Idempotent on already-shaped maps: passes through `:inc_group` and
  `:copy_number` if the caller supplied them, only filling in defaults
  for missing keys.

  ## Derivation rules

  - `inc_group = rem(hash(joined_codons), @inc_group_modulus)` — same
    plasmid genes always hash to the same group; mutation can flip the
    group as a side-effect, mirroring the natural variability of Rep
    families.
  - `copy_number = clamp(1 + count(:dna_binding domains in plasmid), 1,
    @max_copy_number)`. Tighter repressor binding ⇒ stricter
    replication control ⇒ higher steady-state copy number.
  - `oriT_present = true` iff at least one plasmid gene carries an
    `orit_site` intergenic block.
  """
  @spec normalize_plasmid([Gene.t()] | plasmid()) :: plasmid()
  def normalize_plasmid(%{genes: genes} = plasmid) when is_list(genes) do
    %{
      genes: genes,
      inc_group: Map.get(plasmid, :inc_group, derive_inc_group(genes)),
      copy_number: Map.get(plasmid, :copy_number, derive_copy_number(genes)),
      oriT_present: Map.get(plasmid, :oriT_present, derive_orit_present(genes))
    }
  end

  def normalize_plasmid(genes) when is_list(genes) do
    %{
      genes: genes,
      inc_group: derive_inc_group(genes),
      copy_number: derive_copy_number(genes),
      oriT_present: derive_orit_present(genes)
    }
  end

  @doc "Phase-16 incompatibility-group modulus (number of distinct inc groups)."
  @spec inc_group_modulus() :: pos_integer()
  def inc_group_modulus, do: @inc_group_modulus

  @doc "Phase-16 ceiling on `copy_number`."
  @spec max_copy_number() :: pos_integer()
  def max_copy_number, do: @max_copy_number

  defp derive_inc_group([]), do: 0

  defp derive_inc_group(genes) do
    genes
    |> Enum.flat_map(fn gene -> gene.codons end)
    |> :erlang.phash2(@inc_group_modulus)
  end

  defp derive_copy_number(genes) do
    n_dna_binding =
      genes
      |> Enum.flat_map(fn gene -> gene.domains end)
      |> Enum.count(fn d -> d.type == :dna_binding end)

    (1 + n_dna_binding) |> max(1) |> min(@max_copy_number)
  end

  defp derive_orit_present(genes) do
    Enum.any?(genes, fn gene ->
      blocks = Map.get(gene, :intergenic_blocks, %{})
      transfer = Map.get(blocks, :transfer, Map.get(blocks, "transfer", []))
      "orit_site" in List.wrap(transfer)
    end)
  end

  # ----------------------------------------------------------------------
  # Private helpers

  defp valid_gene_list?(genes) when is_list(genes) do
    Enum.all?(genes, &Gene.valid?/1)
  end

  defp valid_gene_list?(_), do: false

  defp valid_prophage?(%{genes: genes, state: state, repressor_strength: rs})
       when is_list(genes) and is_float(rs) and rs >= 0.0 and rs <= 1.0 do
    state in [:lysogenic, :induced] and valid_gene_list?(genes)
  end

  defp valid_prophage?(_), do: false

  defp valid_plasmid?(%{
         genes: genes,
         inc_group: inc_group,
         copy_number: copy_number,
         oriT_present: oriT_present
       })
       when is_list(genes) and is_integer(inc_group) and inc_group >= 0 and
              is_integer(copy_number) and copy_number >= 1 and
              is_boolean(oriT_present) do
    valid_gene_list?(genes)
  end

  defp valid_plasmid?(_), do: false

  defp count_genes(chromosome, plasmids, prophages) do
    length(chromosome) +
      Enum.sum(Enum.map(plasmids, fn p -> length(p.genes) end)) +
      Enum.sum(Enum.map(prophages, fn p -> length(p.genes) end))
  end
end
