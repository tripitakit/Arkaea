defmodule Arkea.Genome.Mutation.Indel do
  @moduledoc "Insertion or deletion of one or more codons at a specific position within a gene."

  use TypedStruct

  alias Arkea.Genome.Codon

  @type kind :: :insertion | :deletion

  typedstruct enforce: true do
    field :gene_id, binary()
    field :position, non_neg_integer()
    field :kind, kind()
    field :codons, [Codon.t()]
  end

  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{
        gene_id: id,
        position: pos,
        kind: kind,
        codons: codons
      })
      when is_binary(id) and is_integer(pos) and pos >= 0 and kind in [:insertion, :deletion] and
             is_list(codons) do
    codons != [] and Enum.all?(codons, &Codon.valid?/1)
  end

  def valid?(_), do: false
end
