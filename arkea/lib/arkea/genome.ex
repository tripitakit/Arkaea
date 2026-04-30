defmodule Arkea.Genome do
  @moduledoc """
  Container of the complete genetic material of a cell line:
  chromosome + plasmids + integrated prophages (DESIGN.md Block 4 / Block 5).

  Phase 1: only `chromosome` is populated. `plasmids` and `prophages` are
  empty lists, but already typed and structurally present so that Phase 6
  (HGT / mobile elements) is a non-breaking extension.

  ## Field semantics

  - `chromosome` — the canonical, vertically inherited list of genes. Must
    be non-empty.
  - `plasmids` — list of plasmids; each plasmid is itself a list of genes.
    Plasmids are inheritable but with their own dynamics (replication cost,
    burden, possible loss). Empty `[]` in Phase 1.

    **Phase 6 TODO**: extend the plasmid representation with `copy_number`
    (low-copy / high-copy distinguish gene-dosage benefit from replication
    burden — San Millán & MacLean 2018) and `inc_group` (incompatibility
    group, Novick 1987 — required to model plasmid coexistence and
    displacement).
  - `prophages` — list of prophage cassettes integrated into the genome.
    Each cassette is a list of genes (receptor, lysogenic repressor, viral
    polymerase, capsid subunits, lysis genes). Empty `[]` in Phase 1.

    **Phase 6 TODO**: add an explicit `state :: :lysogenic | :induced`
    flag plus an inducer-coupling parameter so the lysogenic ↔ lytic
    switch (driven by stress / SOS) becomes part of the data model.
  - `gene_count` — cached total count of genes across chromosome + all
    plasmids + all prophages. Used by Phase 6 plasmid-cost calculations.
  """

  use TypedStruct

  alias Arkea.Genome.Gene

  typedstruct enforce: true do
    field :chromosome, [Gene.t()]
    field :plasmids, [[Gene.t()]], default: []
    field :prophages, [[Gene.t()]], default: []
    field :gene_count, non_neg_integer()
  end

  @doc """
  Build a genome from a non-empty chromosome.

  Optional keyword args: `:plasmids`, `:prophages`. Computes `gene_count`.
  Pure. Raises if `chromosome` is empty or any gene is invalid.
  """
  @spec new([Gene.t()], keyword()) :: t()
  def new(chromosome, opts \\ [])

  def new([], _opts), do: raise(ArgumentError, "chromosome must not be empty")

  def new(chromosome, opts) when is_list(chromosome) do
    plasmids = Keyword.get(opts, :plasmids, [])
    prophages = Keyword.get(opts, :prophages, [])

    unless valid_gene_list?(chromosome) and
             Enum.all?(plasmids, &valid_gene_list?/1) and
             Enum.all?(prophages, &valid_gene_list?/1) do
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
    c ++ List.flatten(p) ++ List.flatten(pr)
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

  @doc "Add a plasmid (list of genes). Recomputes `gene_count`. Pure."
  @spec add_plasmid(t(), [Gene.t()]) :: t()
  def add_plasmid(%__MODULE__{} = genome, plasmid) when is_list(plasmid) do
    unless valid_gene_list?(plasmid) do
      raise ArgumentError, "plasmid genes must all be valid"
    end

    new_plasmids = genome.plasmids ++ [plasmid]

    %{
      genome
      | plasmids: new_plasmids,
        gene_count: count_genes(genome.chromosome, new_plasmids, genome.prophages)
    }
  end

  @doc """
  Integrate a prophage cassette. Recomputes `gene_count`. Pure.

  Phase 1: stores the cassette in `prophages` (does not splice into the
  chromosome). Phase 6 may model two integration modes (chromosomal vs
  plasmid-borne) — the public API stays.
  """
  @spec integrate_prophage(t(), [Gene.t()]) :: t()
  def integrate_prophage(%__MODULE__{} = genome, cassette) when is_list(cassette) do
    unless valid_gene_list?(cassette) do
      raise ArgumentError, "prophage cassette genes must all be valid"
    end

    new_prophages = genome.prophages ++ [cassette]

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
      Enum.all?(plasmids, &valid_gene_list?/1) and
      Enum.all?(prophages, &valid_gene_list?/1) and
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

      not Enum.all?(genome.plasmids, &valid_gene_list?/1) ->
        {:error, :invalid_gene_in_plasmid}

      not Enum.all?(genome.prophages, &valid_gene_list?/1) ->
        {:error, :invalid_gene_in_prophage}

      genome.gene_count != count_genes(genome.chromosome, genome.plasmids, genome.prophages) ->
        {:error, :gene_count_inconsistent}

      true ->
        :ok
    end
  end

  def validate(_), do: {:error, :not_a_genome}

  # ----------------------------------------------------------------------
  # Private helpers

  defp valid_gene_list?(genes) when is_list(genes) do
    Enum.all?(genes, &Gene.valid?/1)
  end

  defp valid_gene_list?(_), do: false

  defp count_genes(chromosome, plasmids, prophages) do
    length(chromosome) +
      Enum.sum(Enum.map(plasmids, &length/1)) +
      Enum.sum(Enum.map(prophages, &length/1))
  end
end
