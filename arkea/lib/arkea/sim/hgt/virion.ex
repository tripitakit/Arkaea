defmodule Arkea.Sim.HGT.Virion do
  @moduledoc """
  Free phage particle persisting in a `Phase.phage_pool` (Phase 12 — DESIGN.md
  Block 8).

  A virion is the unit of inheritance for the phage cycle: produced by a
  `lytic_burst` from a lysed lineage carrying an integrated prophage, it
  carries the cassette genes ready for re-integration in a recipient cell
  (lysogeny) or for an immediate lytic round.

  ## Field semantics

  - `id` — biotope-stable virion identifier, used as map key in
    `Phase.phage_pool`.
  - `genes` — cassette genes (receptor, lysogenic repressor, viral
    polymerase, capsid subunits, lysis genes) carried by the particle.
    Treated as immutable across the virion lifetime.
  - `abundance` — number of free particles (≥ 0). Decay via dilution and
    `Phage.decay_step/2`; pruning when the count reaches 0.
  - `surface_signature` — the recognition signal_key of the phage tail /
    receptor (derived from a `:surface_tag` or `:catalytic_site` domain in
    the cassette). Matches against the recipient's surface_tag set during
    `Phage.infection_step/3`.
  - `methylation_profile` — list of methylase signal_keys carried over from
    the donor cell where the lytic burst happened. Used by
    `HGT.Defense.restriction_check/3` to bypass restriction enzymes that
    share the same recognition site (Arber-Dussoix host modification).
  - `origin_lineage_id` — id of the lineage whose lytic burst produced this
    virion. Audit-log handle (Block 13).
  - `created_at_tick` — tick of birth.
  - `decay_age` — number of ticks the virion has been free. Used by
    `Phage.decay_step/2` to scale the per-tick decay probability.
  """

  use TypedStruct

  alias Arkea.Genome.Gene

  typedstruct enforce: true do
    field :id, binary()
    field :genes, [Gene.t()]
    field :abundance, non_neg_integer()
    field :surface_signature, binary() | nil
    field :methylation_profile, [binary()], default: []
    field :origin_lineage_id, binary() | nil
    field :created_at_tick, non_neg_integer()
    field :decay_age, non_neg_integer(), default: 0
  end

  @doc """
  Build a virion from a freshly burst prophage cassette.

  Pure. Raises if `genes` is empty or any gene is invalid.
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    genes = Keyword.fetch!(opts, :genes)
    abundance = Keyword.fetch!(opts, :abundance)
    created_at_tick = Keyword.fetch!(opts, :created_at_tick)

    unless is_list(genes) and genes != [] and Enum.all?(genes, &Gene.valid?/1) do
      raise ArgumentError, "virion genes must be a non-empty list of valid Gene structs"
    end

    unless is_integer(abundance) and abundance >= 0 do
      raise ArgumentError, "virion abundance must be a non-negative integer"
    end

    %__MODULE__{
      id: Keyword.get_lazy(opts, :id, fn -> Arkea.UUID.v4() end),
      genes: genes,
      abundance: abundance,
      surface_signature: Keyword.get(opts, :surface_signature),
      methylation_profile: Keyword.get(opts, :methylation_profile, []),
      origin_lineage_id: Keyword.get(opts, :origin_lineage_id),
      created_at_tick: created_at_tick,
      decay_age: Keyword.get(opts, :decay_age, 0)
    }
  end

  @doc "True when the virion satisfies its structural invariants."
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

  @doc "Return a virion with abundance updated to `new_abundance` (clamped at 0)."
  @spec set_abundance(t(), integer()) :: t()
  def set_abundance(%__MODULE__{} = virion, new_abundance) do
    %{virion | abundance: max(new_abundance, 0)}
  end

  @doc "Return a virion with decay_age incremented by 1."
  @spec age_one_tick(t()) :: t()
  def age_one_tick(%__MODULE__{decay_age: age} = virion) do
    %{virion | decay_age: age + 1}
  end
end
