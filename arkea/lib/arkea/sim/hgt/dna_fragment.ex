defmodule Arkea.Sim.HGT.DnaFragment do
  @moduledoc """
  Free DNA fragment persisting in a `Phase.dna_pool` (Phase 13 — DESIGN.md
  Block 8).

  A fragment is the unit of substrate for natural transformation: produced
  by lysis events (phage lytic burst, lysis-on-division in Phase 14, or
  routine dilution death) it carries one or more donor genes that a
  competent recipient can take up via `HGT.Channel.Transformation`.

  ## Field semantics

  - `id` — biotope-stable fragment identifier (used as map key in
    `Phase.dna_pool`).
  - `genes` — donor chromosomal genes carried by the fragment. Treated
    as immutable across the fragment lifetime. The Phase 13 model
    deposits the *first* chromosomal gene as a representative locus for
    allelic replacement; richer fragments come with Phase 16.
  - `abundance` — number of equivalent fragment copies (≥ 0). Decay via
    phase dilution and uptake by competent recipients. Pruned when the
    count reaches 0.
  - `methylation_profile` — methylase signal_keys carried over from the
    donor cell. Used by `HGT.Defense.restriction_check/3` to bypass
    recipient restriction enzymes that share the same recognition site.
  - `origin_lineage_id` — id of the lineage whose lysis produced this
    fragment (audit-log handle, Block 13).
  - `created_at_tick` — tick of birth.
  - `decay_age` — number of ticks the fragment has been free.
  """

  use TypedStruct

  alias Arkea.Genome.Gene

  typedstruct enforce: true do
    field :id, binary()
    field :genes, [Gene.t()]
    field :abundance, non_neg_integer()
    field :methylation_profile, [binary()], default: []
    field :origin_lineage_id, binary() | nil
    field :created_at_tick, non_neg_integer()
    field :decay_age, non_neg_integer(), default: 0
  end

  @doc """
  Build a DNA fragment from a freshly lysed donor.

  Pure. Raises if `genes` is empty or any gene is invalid.
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    genes = Keyword.fetch!(opts, :genes)
    abundance = Keyword.fetch!(opts, :abundance)
    created_at_tick = Keyword.fetch!(opts, :created_at_tick)

    unless is_list(genes) and genes != [] and Enum.all?(genes, &Gene.valid?/1) do
      raise ArgumentError, "DnaFragment genes must be a non-empty list of valid Gene structs"
    end

    unless is_integer(abundance) and abundance >= 0 do
      raise ArgumentError, "DnaFragment abundance must be a non-negative integer"
    end

    %__MODULE__{
      id: Keyword.get_lazy(opts, :id, fn -> Arkea.UUID.v4() end),
      genes: genes,
      abundance: abundance,
      methylation_profile: Keyword.get(opts, :methylation_profile, []),
      origin_lineage_id: Keyword.get(opts, :origin_lineage_id),
      created_at_tick: created_at_tick,
      decay_age: Keyword.get(opts, :decay_age, 0)
    }
  end

  @doc "True when the fragment satisfies its structural invariants."
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{
        id: id,
        genes: genes,
        abundance: abundance,
        decay_age: decay_age,
        created_at_tick: tick
      }) do
    is_binary(id) and is_list(genes) and genes != [] and
      Enum.all?(genes, &Gene.valid?/1) and
      is_integer(abundance) and abundance >= 0 and
      is_integer(decay_age) and decay_age >= 0 and
      is_integer(tick) and tick >= 0
  end

  def valid?(_), do: false

  @doc "Return a fragment with abundance updated to `new_abundance` (clamped at 0)."
  @spec set_abundance(t(), integer()) :: t()
  def set_abundance(%__MODULE__{} = fragment, new_abundance) do
    %{fragment | abundance: max(new_abundance, 0)}
  end
end
