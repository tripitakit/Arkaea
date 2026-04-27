defmodule Arkea.Genome.Mutation.Duplication do
  @moduledoc """
  Duplication: a codon range is copied within the same gene, the copy
  inserted at `insert_at`. The originals remain in place; the gene grows
  by `range_end - range_start` codons (or zero if the range is empty).
  """

  use TypedStruct

  typedstruct enforce: true do
    field :gene_id, binary()
    field :range_start, non_neg_integer()
    field :range_end, non_neg_integer()
    field :insert_at, non_neg_integer()
  end

  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{
        gene_id: id,
        range_start: rs,
        range_end: re,
        insert_at: at
      })
      when is_binary(id) and is_integer(rs) and is_integer(re) and is_integer(at) and
             rs >= 0 and re >= rs and at >= 0 do
    true
  end

  def valid?(_), do: false
end
