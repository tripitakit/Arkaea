defmodule Arkea.Genome.Mutation.Translocation do
  @moduledoc """
  Translocation: a codon range is moved from a source gene to a destination
  gene at `dest_position`.

  Translocation is the principal driver of "composed innovation" — fusing
  domains from two genes into a chimeric protein with a genuinely new
  function (DESIGN.md Block 7).
  """

  use TypedStruct

  typedstruct enforce: true do
    field :source_gene_id, binary()
    field :dest_gene_id, binary()
    field :source_range, {non_neg_integer(), non_neg_integer()}
    field :dest_position, non_neg_integer()
  end

  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{
        source_gene_id: src,
        dest_gene_id: dest,
        source_range: {rs, re},
        dest_position: at
      })
      when is_binary(src) and is_binary(dest) and is_integer(rs) and is_integer(re) and
             is_integer(at) and rs >= 0 and re >= rs and at >= 0 do
    src != dest
  end

  def valid?(_), do: false
end
