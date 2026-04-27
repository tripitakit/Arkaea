defmodule Arkea.Genome.Domain.Type do
  @moduledoc """
  Closed enum of the 11 functional domain types (DESIGN.md Block 7).

  A protein domain belongs to exactly one type. Types are categorical (atoms),
  not parametric — the parametric continuous values live in the domain's
  `parameter_codons` and are derived via `Arkea.Genome.Codon.weighted_sum/1`.

  The mapping `from_type_tag/1` — converting a 3-codon "type tag" into an atom
  type — is **deterministic and uniform**: each of the 11 types occupies an
  approximately equal share of the input space (60 buckets of 11). This is
  essential for the unbiased generative system of Block 7: a point mutation
  that flips a codon in the type tag produces a categorical jump to another
  type with no a-priori preference.
  """

  alias Arkea.Genome.Codon

  @types [
    :substrate_binding,
    :catalytic_site,
    :transmembrane_anchor,
    :channel_pore,
    :energy_coupling,
    :dna_binding,
    :regulator_output,
    :ligand_sensor,
    :structural_fold,
    :surface_tag,
    :repair_fidelity
  ]

  @type_count 11

  @typedoc "The 11 functional domain types."
  @type t ::
          :substrate_binding
          | :catalytic_site
          | :transmembrane_anchor
          | :channel_pore
          | :energy_coupling
          | :dna_binding
          | :regulator_output
          | :ligand_sensor
          | :structural_fold
          | :surface_tag
          | :repair_fidelity

  @doc "All 11 types in canonical order."
  @spec all() :: [t()]
  def all, do: @types

  @doc "Number of types (always 11)."
  @spec count() :: 11
  def count, do: @type_count

  @doc "True when `atom` is one of the 11 type tags."
  @spec valid?(term()) :: boolean()
  def valid?(atom) when is_atom(atom), do: atom in @types
  def valid?(_), do: false

  @doc """
  Map a 3-codon `type_tag` to a domain type.

  The mapping is `rem(sum_of_codons, 11)` indexed into `@types`.
  Domain of input: any list of 3 codons in `0..19`. Codomain: one of the 11 type atoms.

  ## Properties

  - **Deterministic**: same input → same output.
  - **Total**: defined for every valid 3-codon list.
  - **Approximately uniform** under random codon distribution: each type
    receives ~9.09% of the probability mass.

  Raises `ArgumentError` if `type_tag` is not a 3-codon list of valid codons.
  """
  @spec from_type_tag([Codon.t()]) :: t()
  def from_type_tag([a, b, c]) when is_integer(a) and is_integer(b) and is_integer(c) do
    if Codon.valid?(a) and Codon.valid?(b) and Codon.valid?(c) do
      Enum.at(@types, rem(a + b + c, @type_count))
    else
      raise ArgumentError, "type_tag must contain three codons in 0..19"
    end
  end

  def from_type_tag(other) do
    raise ArgumentError,
          "type_tag must be a list of exactly 3 codons, got: #{inspect(other)}"
  end
end
