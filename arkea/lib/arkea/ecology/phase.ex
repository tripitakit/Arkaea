defmodule Arkea.Ecology.Phase do
  @moduledoc """
  A phase is a sub-environment of a biotope (DESIGN.md Block 12).

  Each biotope has 2–3 phases (e.g. `:surface`, `:water_column`, `:sediment`)
  with their own metabolite pools, signal pools, free-phage abundances, and
  physical parameters (temperature, pH, osmolarity, dilution rate).

  ## Authoritative vs visualization

  Block 12 makes the **phase** the unit of authoritative state for the
  simulation: lineage abundances, metabolite concentrations and signals are
  all per-phase. The 2D positions of cells in the WebGL view are purely
  rendering — derived from these per-phase aggregates.

  ## Phase 12 additions

  - `phage_pool` is now `%{phage_id => Virion.t()}` (was `=> integer`):
    each free phage particle carries cassette genes, surface signature and
    a methylation profile so `Phage.infection_step/3` and
    `HGT.Defense.restriction_check/3` can run on it.

  ## Phase 13 additions

  - `dna_pool :: %{fragment_id => DnaFragment.t()}` — free DNA fragments
    released by lytic bursts and lysis-on-division. Each fragment carries
    donor genes plus a methylation profile so the R-M gate can run on
    it; consumed by `HGT.Channel.Transformation` when a competent
    recipient takes up the cassette.

  ## Phase 15 additions

  - `xenobiotic_pool :: %{xeno_id => float()}` — environmental
    concentration of each xenobiotic in `Arkea.Sim.Xenobiotic.catalog/0`.
    Player interventions inject drug into the pool; lineages with
    matching hydrolase capacity remove drug from the pool over time.
    Independent from `metabolite_pool` because xenobiotics use their
    own catalog (target_class, Kd, mode) rather than the 13-metabolite
    metabolic taxonomy.
  """

  use TypedStruct

  alias Arkea.Sim.HGT.DnaFragment
  alias Arkea.Sim.HGT.Virion

  @ph_min 0.0
  @ph_max 14.0
  @temperature_min -50.0
  @temperature_max 150.0
  @osmolarity_min 0.0
  @osmolarity_max 5_000.0

  typedstruct enforce: true do
    field :name, atom()
    field :temperature, float()
    field :ph, float()
    field :osmolarity, float()
    field :dilution_rate, float()
    field :metabolite_pool, %{atom() => float()}, default: %{}
    field :signal_pool, %{binary() => float()}, default: %{}
    field :phage_pool, %{binary() => Virion.t()}, default: %{}
    field :dna_pool, %{binary() => DnaFragment.t()}, default: %{}
    field :xenobiotic_pool, %{atom() => float()}, default: %{}
    field :lineage_ids, MapSet.t(binary()), default: MapSet.new()
  end

  @doc """
  Build a phase. Required: `:name`. Optional environmental params have
  conservative defaults (mesophilic, neutral, freshwater).

  ## Options

    * `:temperature` — °C, default `25.0`
    * `:ph` — default `7.0`
    * `:osmolarity` — mOsm/L, default `300.0`
    * `:dilution_rate` — fraction per tick, default `0.05`

  Pure. Raises if any provided value is out of range.
  """
  @spec new(atom(), keyword()) :: t()
  def new(name, opts \\ []) when is_atom(name) do
    phase = %__MODULE__{
      name: name,
      temperature: Keyword.get(opts, :temperature, 25.0),
      ph: Keyword.get(opts, :ph, 7.0),
      osmolarity: Keyword.get(opts, :osmolarity, 300.0),
      dilution_rate: Keyword.get(opts, :dilution_rate, 0.05),
      metabolite_pool: %{},
      signal_pool: %{},
      phage_pool: %{},
      dna_pool: %{},
      xenobiotic_pool: %{},
      lineage_ids: MapSet.new()
    }

    case validate(phase) do
      :ok -> phase
      {:error, reason} -> raise ArgumentError, "invalid phase: #{reason}"
    end
  end

  @doc "Add a lineage UUID to the phase. Pure."
  @spec add_lineage(t(), binary()) :: t()
  def add_lineage(%__MODULE__{lineage_ids: ids} = phase, lineage_id) when is_binary(lineage_id) do
    %{phase | lineage_ids: MapSet.put(ids, lineage_id)}
  end

  @doc "Remove a lineage UUID from the phase. Pure."
  @spec remove_lineage(t(), binary()) :: t()
  def remove_lineage(%__MODULE__{lineage_ids: ids} = phase, lineage_id)
      when is_binary(lineage_id) do
    %{phase | lineage_ids: MapSet.delete(ids, lineage_id)}
  end

  @doc "Membership check."
  @spec has_lineage?(t(), binary()) :: boolean()
  def has_lineage?(%__MODULE__{lineage_ids: ids}, lineage_id) when is_binary(lineage_id) do
    MapSet.member?(ids, lineage_id)
  end

  @doc "Number of lineages currently tracked in the phase."
  @spec lineage_count(t()) :: non_neg_integer()
  def lineage_count(%__MODULE__{lineage_ids: ids}), do: MapSet.size(ids)

  @doc """
  Set or update a metabolite concentration. Concentration must be ≥ 0.0.
  Pure. Raises on negative input.
  """
  @spec update_metabolite(t(), atom(), float()) :: t()
  def update_metabolite(%__MODULE__{metabolite_pool: pool} = phase, id, conc)
      when is_atom(id) and is_float(conc) and conc >= 0.0 do
    %{phase | metabolite_pool: Map.put(pool, id, conc)}
  end

  @doc """
  Set or update a signal concentration. Key must be a binary string. Must be ≥ 0.0. Pure.
  """
  @spec update_signal(t(), binary(), float()) :: t()
  def update_signal(%__MODULE__{signal_pool: pool} = phase, id, conc)
      when is_binary(id) and is_float(conc) and conc >= 0.0 do
    %{phase | signal_pool: Map.put(pool, id, conc)}
  end

  @doc """
  Set or update a xenobiotic concentration. Concentration must be ≥ 0.0.
  Pure. Raises on negative input.
  """
  @spec update_xenobiotic(t(), atom(), float()) :: t()
  def update_xenobiotic(%__MODULE__{xenobiotic_pool: pool} = phase, id, conc)
      when is_atom(id) and is_float(conc) and conc >= 0.0 do
    %{phase | xenobiotic_pool: Map.put(pool, id, conc)}
  end

  @doc "Inject `amount` (≥ 0) of a xenobiotic into the phase pool. Pure."
  @spec add_xenobiotic(t(), atom(), float()) :: t()
  def add_xenobiotic(%__MODULE__{xenobiotic_pool: pool} = phase, id, amount)
      when is_atom(id) and is_float(amount) and amount >= 0.0 do
    %{phase | xenobiotic_pool: Map.update(pool, id, amount, &(&1 + amount))}
  end

  @doc "Sum of virion abundances across the entire phage_pool. O(n)."
  @spec phage_total(t()) :: non_neg_integer()
  def phage_total(%__MODULE__{phage_pool: pool}) do
    pool |> Map.values() |> Enum.reduce(0, fn v, acc -> acc + v.abundance end)
  end

  @doc "Sum of DNA fragment abundances across the entire dna_pool. O(n)."
  @spec dna_total(t()) :: non_neg_integer()
  def dna_total(%__MODULE__{dna_pool: pool}) do
    pool |> Map.values() |> Enum.reduce(0, fn f, acc -> acc + f.abundance end)
  end

  @doc """
  Add a virion to the pool. Existing entries (same id) accumulate abundance
  while preserving their metadata; new ids store the supplied virion as-is.
  Pure.
  """
  @spec add_virion(t(), Virion.t()) :: t()
  def add_virion(%__MODULE__{phage_pool: pool} = phase, %Virion{} = virion) do
    new_pool =
      Map.update(pool, virion.id, virion, fn existing ->
        %{existing | abundance: existing.abundance + virion.abundance}
      end)

    %{phase | phage_pool: new_pool}
  end

  @doc """
  Add a DNA fragment to the pool. Existing entries (same id) accumulate
  abundance while preserving their metadata; new ids store the supplied
  fragment as-is. Pure.
  """
  @spec add_dna_fragment(t(), DnaFragment.t()) :: t()
  def add_dna_fragment(%__MODULE__{dna_pool: pool} = phase, %DnaFragment{} = fragment) do
    new_pool =
      Map.update(pool, fragment.id, fragment, fn existing ->
        %{existing | abundance: existing.abundance + fragment.abundance}
      end)

    %{phase | dna_pool: new_pool}
  end

  @doc """
  Apply the phase's `dilution_rate` to all metabolite, signal, phage, and
  DNA pools. Each value becomes `value * (1 - dilution_rate)`; integer
  pools floor the result.

  **Invariant**: every concentration after `dilute/1` is ≤ its previous
  value (monotonic decrease). Pure.
  """
  @spec dilute(t()) :: t()
  def dilute(%__MODULE__{dilution_rate: rate} = phase) do
    factor = 1.0 - rate

    %{
      phase
      | metabolite_pool: dilute_pool(phase.metabolite_pool, factor),
        signal_pool: dilute_pool(phase.signal_pool, factor),
        phage_pool: dilute_phage_pool(phase.phage_pool, factor),
        dna_pool: dilute_dna_pool(phase.dna_pool, factor),
        xenobiotic_pool: dilute_pool(phase.xenobiotic_pool, factor)
    }
  end

  @doc "True when the phase satisfies its structural invariants."
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = phase), do: validate(phase) == :ok
  def valid?(_), do: false

  @doc "Validation with reason."
  @spec validate(t()) :: :ok | {:error, atom()}
  def validate(%__MODULE__{} = phase) do
    Enum.find_value(validation_checks(phase), :ok, fn {check, error_atom} ->
      if check.(), do: false, else: {:error, error_atom}
    end)
  end

  def validate(_), do: {:error, :not_a_phase}

  # ----------------------------------------------------------------------
  # Private helpers

  defp validation_checks(phase) do
    [
      {fn -> is_atom(phase.name) end, :invalid_name},
      {fn -> in_range?(phase.temperature, @temperature_min, @temperature_max) end,
       :temperature_out_of_range},
      {fn -> in_range?(phase.ph, @ph_min, @ph_max) end, :ph_out_of_range},
      {fn -> in_range?(phase.osmolarity, @osmolarity_min, @osmolarity_max) end,
       :osmolarity_out_of_range},
      {fn -> in_range?(phase.dilution_rate, 0.0, 1.0) end, :dilution_rate_out_of_range},
      {fn -> valid_pool?(phase.metabolite_pool) end, :invalid_metabolite_pool},
      {fn -> valid_signal_pool?(phase.signal_pool) end, :invalid_signal_pool},
      {fn -> valid_phage_pool?(phase.phage_pool) end, :invalid_phage_pool},
      {fn -> valid_dna_pool?(phase.dna_pool) end, :invalid_dna_pool},
      {fn -> valid_pool?(phase.xenobiotic_pool) end, :invalid_xenobiotic_pool},
      {fn -> match?(%MapSet{}, phase.lineage_ids) end, :invalid_lineage_ids}
    ]
  end

  defp in_range?(value, lo, hi) when is_float(value), do: value >= lo and value <= hi
  defp in_range?(_, _, _), do: false

  defp valid_pool?(pool) when is_map(pool) do
    Enum.all?(pool, fn {k, v} -> is_atom(k) and is_float(v) and v >= 0.0 end)
  end

  defp valid_pool?(_), do: false

  defp valid_signal_pool?(pool) when is_map(pool) do
    Enum.all?(pool, fn {k, v} -> is_binary(k) and is_float(v) and v >= 0.0 end)
  end

  defp valid_signal_pool?(_), do: false

  defp valid_phage_pool?(pool) when is_map(pool) do
    Enum.all?(pool, fn {k, v} -> is_binary(k) and Virion.valid?(v) and v.id == k end)
  end

  defp valid_phage_pool?(_), do: false

  defp valid_dna_pool?(pool) when is_map(pool) do
    Enum.all?(pool, fn {k, v} -> is_binary(k) and DnaFragment.valid?(v) and v.id == k end)
  end

  defp valid_dna_pool?(_), do: false

  defp dilute_pool(pool, factor) when is_map(pool) do
    Map.new(pool, fn {k, v} -> {k, v * factor} end)
  end

  defp dilute_phage_pool(pool, factor) when is_map(pool) do
    pool
    |> Enum.map(fn {k, %Virion{abundance: a} = v} ->
      {k, %{v | abundance: trunc(a * factor)}}
    end)
    |> Map.new()
  end

  defp dilute_dna_pool(pool, factor) when is_map(pool) do
    pool
    |> Enum.map(fn {k, %DnaFragment{abundance: a} = f} ->
      {k, %{f | abundance: trunc(a * factor)}}
    end)
    |> Map.new()
  end
end
