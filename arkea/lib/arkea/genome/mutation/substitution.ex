defmodule Arkea.Genome.Mutation.Substitution do
  @moduledoc "Point mutation: one codon replaced at a specific position within a gene."

  use TypedStruct

  alias Arkea.Genome.Codon

  typedstruct enforce: true do
    field :gene_id, binary()
    field :position, non_neg_integer()
    field :old_codon, Codon.t()
    field :new_codon, Codon.t()
  end

  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{
        gene_id: id,
        position: pos,
        old_codon: old,
        new_codon: new
      })
      when is_binary(id) and is_integer(pos) and pos >= 0 do
    Codon.valid?(old) and Codon.valid?(new) and old != new
  end

  def valid?(_), do: false
end
