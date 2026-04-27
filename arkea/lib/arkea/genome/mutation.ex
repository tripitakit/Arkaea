defmodule Arkea.Genome.Mutation do
  @moduledoc """
  Tagged union of all mutation events that can be appended to a lineage's
  `delta` (DESIGN.md Block 5 / Block 7).

  Phase 1 declares the structs only; the application logic (`apply/2`) and
  generation logic (`Mutator`) arrive in Phase 4.

  ## Variants

  - `Substitution` — single codon replaced (point mutation)
  - `Indel` — codons inserted or deleted at a position
  - `Duplication` — codon range copied to another position within the same gene
  - `Inversion` — codon range reversed in place
  - `Translocation` — codon range moved between two genes (the principal
    driver of "composed innovation" per Block 7)
  """

  alias Arkea.Genome.Mutation.Duplication
  alias Arkea.Genome.Mutation.Indel
  alias Arkea.Genome.Mutation.Inversion
  alias Arkea.Genome.Mutation.Substitution
  alias Arkea.Genome.Mutation.Translocation

  @type t ::
          Substitution.t()
          | Indel.t()
          | Duplication.t()
          | Inversion.t()
          | Translocation.t()

  @doc "True when `value` is one of the five mutation event structs and is internally valid."
  @spec valid?(term()) :: boolean()
  def valid?(%Substitution{} = m), do: Substitution.valid?(m)
  def valid?(%Indel{} = m), do: Indel.valid?(m)
  def valid?(%Duplication{} = m), do: Duplication.valid?(m)
  def valid?(%Inversion{} = m), do: Inversion.valid?(m)
  def valid?(%Translocation{} = m), do: Translocation.valid?(m)
  def valid?(_), do: false
end
