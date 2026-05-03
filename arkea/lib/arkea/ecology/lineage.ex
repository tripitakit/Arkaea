defmodule Arkea.Ecology.Lineage do
  @moduledoc """
  A lineage is the atomic unit of evolution: one distinct genotype + its
  per-phase abundance (DESIGN.md Block 4 — lineage-based modeling, cap 1.000
  per biotope at production scale, 100 in prototype).

  ## Identity and ancestry

  - `id` — UUID v4, stable across the lineage's lifetime.
  - `parent_id` — UUID of the parent lineage, or `nil` for clade founders.
  - `clade_ref_id` — UUID of the clade's reference genome. Founders have
    `clade_ref_id == id`. Used in Phase 4 to locate the genome from which
    the `delta` is computed.

  ## Genome and delta

  - `genome` — explicit genome (Phase 1: always populated). In Phase 4,
    descendants may have `genome: nil` and rely on `delta` applied to the
    clade's reference genome (delta-encoding optimisation).
  - `delta` — list of mutation events (`Arkea.Genome.Mutation.t()`).
    Empty in Phase 1 (no mutator yet). Populated in Phase 4.

  ## Population

  - `abundance_by_phase` — map `phase_name => non_neg_integer()` giving
    an **abundance index** (cell-equivalent count) for this lineage in
    each phase of its biotope. The integer is *not* a literal cell count
    — real bacterial densities (10⁹–10¹² cells/L; Whitman 1998) are 6–9
    orders of magnitude above the simulated cap. The index preserves the
    ratios that matter for selection and migration; absolute values are
    a model-internal scale.
    The integer (not fraction) preserves information for migration
    calculations: cell-equivalents added to a destination phase exactly
    match cell-equivalents removed from the source.
  - `fitness_cache` — last computed fitness, `nil` if invalidated.
    Phase 5+ cache.
  - `biomass` — Phase 14: continuous structural integrity index split
    across `:membrane`, `:wall`, `:dna`, each in `0.0..1.0`. Defaults
    to `1.0` (intact founder cell). Each tick, biosynthetic enzymes
    in the genome push biomass up while stress (osmotic shock,
    elemental shortage, toxicity, mutational load) pushes it down. A
    component below its critical threshold drives `step_lysis/1` to
    kill cells stochastically. Phase 17 will use the same field as the
    substrate for error-catastrophe accounting.

  ## Bookkeeping

  - `created_at_tick` — tick number of birth. Used for monotonicity
    invariants (a child's `created_at_tick` is always strictly greater
    than its parent's).
  """

  use TypedStruct

  alias Arkea.Genome
  alias Arkea.Genome.Mutation

  @typedoc """
  Continuous biomass index for a lineage (Phase 14).

  Three components, each in `0.0..1.0`. Founder cells start fully
  intact at `1.0`. Stress drives values down; biosynthesis pushes them
  back up. Below per-component critical thresholds the lineage suffers
  stochastic lysis (`step_lysis/1`).
  """
  @type biomass :: %{
          membrane: float(),
          wall: float(),
          dna: float()
        }

  @full_biomass %{membrane: 1.0, wall: 1.0, dna: 1.0}

  typedstruct enforce: true do
    field :id, binary()
    field :parent_id, binary() | nil
    field :clade_ref_id, binary()
    field :genome, Genome.t() | nil
    field :delta, [Mutation.t()], default: []
    field :abundance_by_phase, %{atom() => non_neg_integer()}
    field :fitness_cache, float() | nil, default: nil
    field :created_at_tick, non_neg_integer()
    field :biomass, biomass(), default: %{membrane: 1.0, wall: 1.0, dna: 1.0}
  end

  @doc "Default fully-intact biomass. Used when seeding founders and children."
  @spec full_biomass() :: biomass()
  def full_biomass, do: @full_biomass

  @doc """
  Build a founder lineage (no parent, clade reference is itself).

  Pure. Validates the genome and abundances.
  """
  @spec new_founder(Genome.t(), %{atom() => non_neg_integer()}, non_neg_integer()) :: t()
  def new_founder(%Genome{} = genome, abundances, tick)
      when is_map(abundances) and is_integer(tick) and tick >= 0 do
    unless Genome.valid?(genome) do
      raise ArgumentError, "genome must be valid"
    end

    unless valid_abundances?(abundances) do
      raise ArgumentError, "abundances must be a map of atom => non_neg_integer"
    end

    id = Arkea.UUID.v4()

    %__MODULE__{
      id: id,
      parent_id: nil,
      clade_ref_id: id,
      genome: genome,
      delta: [],
      abundance_by_phase: abundances,
      fitness_cache: nil,
      created_at_tick: tick,
      biomass: @full_biomass
    }
  end

  @doc """
  Build a child lineage from a parent.

  In Phase 1 the child carries an explicit `genome`. In Phase 4 the same
  signature accepts a `genome: nil` child with a non-empty `delta` and the
  parent's `clade_ref_id` is propagated.

  Pure.
  """
  @spec new_child(t(), Genome.t(), %{atom() => non_neg_integer()}, non_neg_integer()) :: t()
  def new_child(%__MODULE__{} = parent, %Genome{} = genome, abundances, tick)
      when is_map(abundances) and is_integer(tick) and tick >= 0 do
    unless Genome.valid?(genome) do
      raise ArgumentError, "genome must be valid"
    end

    unless valid_abundances?(abundances) do
      raise ArgumentError, "abundances must be a map of atom => non_neg_integer"
    end

    if tick <= parent.created_at_tick do
      raise ArgumentError,
            "child tick (#{tick}) must be strictly greater than parent's (#{parent.created_at_tick})"
    end

    %__MODULE__{
      id: Arkea.UUID.v4(),
      parent_id: parent.id,
      clade_ref_id: parent.clade_ref_id,
      genome: genome,
      delta: [],
      abundance_by_phase: abundances,
      fitness_cache: nil,
      created_at_tick: tick,
      biomass: @full_biomass
    }
  end

  @doc "Sum of abundances across all phases."
  @spec total_abundance(t()) :: non_neg_integer()
  def total_abundance(%__MODULE__{abundance_by_phase: abundances}) do
    abundances |> Map.values() |> Enum.sum()
  end

  @doc "Abundance in a specific phase, 0 if the phase is not present in the map."
  @spec abundance_in(t(), atom()) :: non_neg_integer()
  def abundance_in(%__MODULE__{abundance_by_phase: abundances}, phase_name)
      when is_atom(phase_name) do
    Map.get(abundances, phase_name, 0)
  end

  @doc "True for clade founders (parent_id == nil)."
  @spec founder?(t()) :: boolean()
  def founder?(%__MODULE__{parent_id: nil}), do: true
  def founder?(%__MODULE__{}), do: false

  @doc """
  Apply growth deltas (positive or negative) to abundance per phase.

  Returns a new lineage with `abundance_by_phase` updated and
  `fitness_cache` reset to `nil` (a population change typically invalidates
  the fitness — cheap and safe to invalidate eagerly).

  **Invariant**: no resulting per-phase count is ever negative (clamped at 0).
  Pure.
  """
  @spec apply_growth(t(), %{atom() => integer()}) :: t()
  def apply_growth(%__MODULE__{abundance_by_phase: abundances} = lineage, deltas)
      when is_map(deltas) do
    new_abundances =
      Enum.reduce(deltas, abundances, fn {phase_name, delta}, acc
                                         when is_atom(phase_name) and is_integer(delta) ->
        current = Map.get(acc, phase_name, 0)
        new_value = max(current + delta, 0)
        Map.put(acc, phase_name, new_value)
      end)

    %{lineage | abundance_by_phase: new_abundances, fitness_cache: nil}
  end

  @doc "Invalidate the fitness cache (set to `nil`). Pure."
  @spec invalidate_fitness(t()) :: t()
  def invalidate_fitness(%__MODULE__{} = lineage), do: %{lineage | fitness_cache: nil}

  @doc "True when the lineage satisfies its structural invariants."
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = lineage), do: validate(lineage) == :ok
  def valid?(_), do: false

  @doc "Validation with reason."
  @spec validate(t()) :: :ok | {:error, atom()}
  def validate(%__MODULE__{} = lineage) do
    Enum.find_value(validation_checks(lineage), :ok, fn {check, error_atom} ->
      if check.(), do: false, else: {:error, error_atom}
    end)
  end

  def validate(_), do: {:error, :not_a_lineage}

  # Each entry is `{thunk, error_atom}`. Walked in order; first failure wins.
  # Splitting the validation into named predicates keeps cyclomatic complexity
  # of `validate/1` flat and makes each invariant individually testable.
  defp validation_checks(lineage) do
    [
      {fn -> is_binary(lineage.id) end, :invalid_id},
      {fn -> lineage.parent_id == nil or is_binary(lineage.parent_id) end, :invalid_parent_id},
      {fn -> is_binary(lineage.clade_ref_id) end, :invalid_clade_ref_id},
      {fn -> founder_clade_consistent?(lineage.parent_id, lineage.clade_ref_id, lineage.id) end,
       :clade_ref_inconsistent},
      {fn -> valid_tick?(lineage.created_at_tick) end, :invalid_tick},
      {fn -> lineage.genome == nil or Genome.valid?(lineage.genome) end, :invalid_genome},
      {fn -> Enum.all?(lineage.delta, &Mutation.valid?/1) end, :invalid_delta},
      {fn -> valid_abundances?(lineage.abundance_by_phase) end, :invalid_abundances},
      {fn -> valid_fitness?(lineage.fitness_cache) end, :invalid_fitness},
      {fn -> valid_biomass?(lineage.biomass) end, :invalid_biomass}
    ]
  end

  defp valid_tick?(tick), do: is_integer(tick) and tick >= 0

  defp valid_fitness?(nil), do: true
  defp valid_fitness?(fitness) when is_float(fitness) and fitness >= 0.0, do: true
  defp valid_fitness?(_), do: false

  defp valid_biomass?(%{membrane: m, wall: w, dna: d})
       when is_float(m) and is_float(w) and is_float(d) and
              m >= 0.0 and m <= 1.0 and
              w >= 0.0 and w <= 1.0 and
              d >= 0.0 and d <= 1.0,
       do: true

  defp valid_biomass?(_), do: false

  # ----------------------------------------------------------------------
  # Private helpers

  defp founder_clade_consistent?(nil, clade_ref_id, id), do: clade_ref_id == id
  defp founder_clade_consistent?(_parent_id, _clade_ref_id, _id), do: true

  defp valid_abundances?(abundances) when is_map(abundances) do
    Enum.all?(abundances, fn {k, v} ->
      is_atom(k) and is_integer(v) and v >= 0
    end)
  end

  defp valid_abundances?(_), do: false
end
