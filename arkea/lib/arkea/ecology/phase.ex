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

  ## Phase 1 simplifications

  - `metabolite_pool` and `signal_pool` are empty maps (`%{}`); their
    population starts in Phase 5 (metabolism) and Phase 7 (quorum sensing).
  - `phage_pool` is also empty in Phase 1 (mobile elements are Phase 6).
  - `lineage_ids` is a `MapSet` of UUIDs — `MapSet` gives O(log n)
    membership and is transparent to `:erlang.term_to_binary/1`.
  """

  use TypedStruct

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
    field :phage_pool, %{binary() => non_neg_integer()}, default: %{}
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
  Apply the phase's `dilution_rate` to all metabolite, signal, and phage
  pools. Each value becomes `value * (1 - dilution_rate)`.

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
        phage_pool: dilute_phage_pool(phase.phage_pool, factor)
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
    Enum.all?(pool, fn {k, v} -> is_binary(k) and is_integer(v) and v >= 0 end)
  end

  defp valid_phage_pool?(_), do: false

  defp dilute_pool(pool, factor) when is_map(pool) do
    Map.new(pool, fn {k, v} -> {k, v * factor} end)
  end

  defp dilute_phage_pool(pool, factor) when is_map(pool) do
    # Phage counts are integers; we floor the result so dilution never grows.
    Map.new(pool, fn {k, v} -> {k, trunc(v * factor)} end)
  end
end
