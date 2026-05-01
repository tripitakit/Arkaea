defmodule Arkea.Sim.BiotopeState do
  @moduledoc """
  Pure-data struct that `Arkea.Sim.Biotope.Server` holds as its in-memory state
  (IMPLEMENTATION-PLAN.md §4 — Active Record pattern).

  This is **not** a GenServer; it is the immutable value that flows through the
  pure tick pipeline `Arkea.Sim.Tick.tick/1 → {BiotopeState.t(), [event()]}`.

  ## State fields

  - `id` — UUID v4, stable for the lifetime of the biotope process.
  - `archetype` — one of the 8 archetypes (DESIGN.md Block 10).
  - `x`, `y` — planar coordinates used by the Phase 8 topology graph.
  - `zone` — coarse environmental region used to bias migration within clusters.
  - `owner_player_id` — `nil` for wild biotopes, or the owning player UUID.
  - `neighbor_ids` — directed outgoing edges in the topology graph. Symmetric
    connections are represented by reciprocal membership.
  - `phases` — list of `Arkea.Ecology.Phase.t()`. The phase `dilution_rate`
    is authoritative; `dilution_rate` on this struct is a biotope-wide fallback
    used when a phase entry is missing from `growth_delta_by_phase` or for
    lineage phases not listed in `phases` (Phase 2 simplification).
  - `lineages` — list of `Arkea.Ecology.Lineage.t()`. Lookup by id uses
    `Enum.find/2` (O(n), adequate for prototype cap of 100 lineages). Phase 4
    will replace this with a `%{id => lineage}` map once profiling justifies it.
  - `growth_delta_by_lineage` — map `lineage_id => %{phase_name => integer()}`
    giving the per-tick abundance increment for each lineage in each phase.
    Stored separately from `Arkea.Ecology.Lineage` because:
    (a) `Lineage` is a Phase 1 pure-data struct (no simulation state);
    (b) the deltas are simulation parameters that will be genome-derived in
        Phase 5 (genome → expression → kinetic rates → growth deltas).
    Phase 2: set once at `new/2` time and held constant.
    Phase 5: recomputed every tick by `step_expression/1`.
  - `tick_count` — monotonically increasing counter. Starts at 0 and is
    incremented by `Arkea.Sim.Tick.tick/1` at every call.
  - `dilution_rate` — biotope-wide fallback dilution rate. Valid range: 0.0..1.0.
    Derived from the mean of phase dilution_rates at `new/2` time.
  - `rng_seed` — reserved for deterministic RNG in Phase 4+ (mutation, HGT
    stochasticity). Stored as `nil` in Phase 2 (no stochastic steps yet).
  - `atp_yield_by_lineage` — map `lineage_id => float()` accumulated by
    `step_metabolism/1` from Michaelis-Menten kinetics across all phases.
    Read by `step_expression/1` in the same tick to derive growth deltas.
    Populated in Phase 5; empty map `%{}` in earlier phases.
  - `metabolite_inflow` — map `metabolite_atom => float()` specifying the
    per-tick replenishment added to every phase's metabolite_pool after
    dilution in `step_environment/1`. Models a chemostat: continuous inflow
    of fresh substrate keeps the biotope from starving. Empty `%{}` by
    default (no inflow).

  ## Invariants

  - `tick_count >= 0`
  - `dilution_rate in 0.0..1.0`
  - All lineages satisfy `Arkea.Ecology.Lineage.valid?/1`.
  - All phases satisfy `Arkea.Ecology.Phase.valid?/1`.
  - `archetype` is one of `Arkea.Ecology.Biotope.archetypes/0`.

  ## Phase 2 simplifications

  - `rng_seed` is `nil` — stochastic steps (mutation, HGT) are stubbed.
  - `growth_delta_by_lineage` maps use integer deltas directly (no genome-
    derived fitness calculation). Phase 5 will replace these with computed values.
  """

  use TypedStruct

  alias Arkea.Ecology.Biotope
  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Sim.Mutator

  @type archetype :: Biotope.archetype()
  @type growth_deltas :: %{binary() => %{atom() => integer()}}

  typedstruct enforce: true do
    field :id, binary()
    field :archetype, archetype()
    field :x, float(), default: 0.0
    field :y, float(), default: 0.0
    field :zone, atom(), default: :unassigned
    field :owner_player_id, binary() | nil, default: nil
    field :neighbor_ids, [binary()], default: []
    field :phases, [Phase.t()]
    field :lineages, [Lineage.t()]
    field :growth_delta_by_lineage, growth_deltas(), default: %{}
    field :tick_count, non_neg_integer(), default: 0
    field :dilution_rate, float()
    field :rng_seed, term(), default: nil
    field :atp_yield_by_lineage, %{binary() => float()}, default: %{}
    field :metabolite_inflow, %{atom() => float()}, default: %{}
  end

  @doc """
  Build a `BiotopeState` from an `Arkea.Ecology.Biotope.t()`, a list of
  seed lineages, and an optional growth-delta map.

  The biotope-wide `dilution_rate` fallback is derived from the mean of the
  phases' dilution_rates. The growth deltas are supplied externally because
  they will be computed from the genome in Phase 5 — in Phase 2 they are
  provided by the caller (test fixtures or server init).

  Pure. Raises on invalid input.
  """
  @spec new(Biotope.t(), [Lineage.t()], growth_deltas()) :: t()
  def new(%Biotope{} = biotope, lineages, growth_deltas \\ %{})
      when is_list(lineages) and is_map(growth_deltas) do
    unless Enum.all?(lineages, &Lineage.valid?/1) do
      raise ArgumentError, "all seed lineages must be valid"
    end

    %__MODULE__{
      id: biotope.id,
      archetype: biotope.archetype,
      x: biotope.x,
      y: biotope.y,
      zone: biotope.zone,
      owner_player_id: biotope.owner_player_id,
      neighbor_ids: biotope.neighbor_ids,
      phases: biotope.phases,
      lineages: lineages,
      growth_delta_by_lineage: growth_deltas,
      tick_count: 0,
      dilution_rate: mean_dilution_rate(biotope.phases),
      rng_seed: Mutator.init_seed(biotope.id)
    }
  end

  @doc """
  Build a `BiotopeState` directly from keyword options.

  Useful in tests where a full `Biotope.t()` is not needed.

  ## Required keys

    * `:id` — binary UUID
    * `:archetype` — valid archetype atom
    * `:phases` — list of `Phase.t()`
    * `:dilution_rate` — float in 0.0..1.0

  ## Optional keys

    * `:lineages` — list of `Lineage.t()`, default `[]`
    * `:growth_delta_by_lineage` — growth delta map, default `%{}`
    * `:tick_count` — non_neg_integer, default `0`
    * `:rng_seed` — any term, default `nil`

  Pure. Raises on missing required keys.
  """
  @spec new_from_opts(keyword()) :: t()
  def new_from_opts(opts) when is_list(opts) do
    %__MODULE__{
      id: Keyword.fetch!(opts, :id),
      archetype: Keyword.fetch!(opts, :archetype),
      x: Keyword.get(opts, :x, 0.0),
      y: Keyword.get(opts, :y, 0.0),
      zone: Keyword.get(opts, :zone, :unassigned),
      owner_player_id: Keyword.get(opts, :owner_player_id),
      neighbor_ids: Keyword.get(opts, :neighbor_ids, []),
      phases: Keyword.fetch!(opts, :phases),
      dilution_rate: Keyword.fetch!(opts, :dilution_rate),
      lineages: Keyword.get(opts, :lineages, []),
      growth_delta_by_lineage: Keyword.get(opts, :growth_delta_by_lineage, %{}),
      tick_count: Keyword.get(opts, :tick_count, 0),
      rng_seed: Keyword.get(opts, :rng_seed, nil),
      atp_yield_by_lineage: Keyword.get(opts, :atp_yield_by_lineage, %{}),
      metabolite_inflow: Keyword.get(opts, :metabolite_inflow, %{})
    }
  end

  @doc "Look up a lineage by id. Returns `nil` if not found."
  @spec find_lineage(t(), binary()) :: Lineage.t() | nil
  def find_lineage(%__MODULE__{lineages: lineages}, id) when is_binary(id) do
    Enum.find(lineages, fn l -> l.id == id end)
  end

  @doc "Replace a lineage in the list (matched by id). No-op if id not found."
  @spec put_lineage(t(), Lineage.t()) :: t()
  def put_lineage(%__MODULE__{lineages: lineages} = state, %Lineage{id: id} = lineage) do
    updated = Enum.map(lineages, fn l -> if l.id == id, do: lineage, else: l end)
    %{state | lineages: updated}
  end

  @doc "Total abundance across all lineages and all phases."
  @spec total_abundance(t()) :: non_neg_integer()
  def total_abundance(%__MODULE__{lineages: lineages}) do
    Enum.sum_by(lineages, &Lineage.total_abundance/1)
  end

  # ---------------------------------------------------------------------------
  # Private helpers

  defp mean_dilution_rate([]), do: 0.05

  defp mean_dilution_rate(phases) do
    total = Enum.sum_by(phases, & &1.dilution_rate)
    total / length(phases)
  end
end
