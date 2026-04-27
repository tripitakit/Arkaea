defmodule Arkea.Genome.Mutation.Inversion do
  @moduledoc "Inversion: a codon range is reversed in place within the same gene."

  use TypedStruct

  typedstruct enforce: true do
    field :gene_id, binary()
    field :range_start, non_neg_integer()
    field :range_end, non_neg_integer()
  end

  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{gene_id: id, range_start: rs, range_end: re})
      when is_binary(id) and is_integer(rs) and is_integer(re) and rs >= 0 and re >= rs do
    true
  end

  def valid?(_), do: false
end
