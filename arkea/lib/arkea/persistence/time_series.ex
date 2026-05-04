defmodule Arkea.Persistence.TimeSeries do
  @moduledoc """
  Time-series sampling pipeline (UI Phase B).

  This module is the bridge between the pure simulation state and the
  Postgres-backed `time_series_samples` table. It runs as part of every
  authoritative tick transition (called from `Arkea.Persistence.Store`)
  and writes a small batch of sample rows whenever
  `tick rem @sampling_period == 0`.

  ## Sampling shape

  Five sample kinds are produced:

  - `"abundance"` — one row per lineage, payload is the
    `abundance_by_phase` map. `scope_id` is the lineage uuid.
  - `"metabolite_pool"` — one row per phase, payload is the metabolite
    map. `scope_id` is the phase name.
  - `"signal_pool"` — one row per phase, payload is the QS signal map.
  - `"biomass"` — one row per lineage, payload is `%{wall, membrane,
    dna}`. `scope_id` is the lineage uuid.
  - `"dna_damage"` — one row per lineage with non-zero damage. Payload
    is `%{value: float}`.

  Lineages with `genome: nil` (delta-encoded descendants) are skipped
  for biomass / dna_damage samples since those fields are inherited.

  ## Cadence

  - Population-shape samples (`abundance`, `metabolite_pool`,
    `signal_pool`) are taken every `@sampling_period` ticks (default 5).
  - Cellular-state samples (`biomass`, `dna_damage`) every
    `@cell_sampling_period` ticks (default 10).

  ## Cap & pruning

  When the per-biotope row count exceeds `@cap` (default 10⁵), the
  oldest samples by `inserted_at` are deleted in batches of 1000. This
  keeps the table bounded under continuous play.

  All scheduling decisions are pure (no I/O); only `persist/3` touches
  the repo. The pure half of this module can be unit-tested without a
  database.
  """

  import Ecto.Query

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Persistence.TimeSeriesSample
  alias Arkea.Sim.BiotopeState

  @sampling_period Application.compile_env(:arkea, :time_series_sampling_period, 5)
  @cell_sampling_period Application.compile_env(:arkea, :time_series_cell_sampling_period, 10)
  @cap Application.compile_env(:arkea, :time_series_cap_per_biotope, 100_000)

  @doc "Sampling period for population-shape samples (ticks)."
  @spec sampling_period() :: pos_integer()
  def sampling_period, do: @sampling_period

  @doc "Sampling period for per-lineage cellular state samples (ticks)."
  @spec cell_sampling_period() :: pos_integer()
  def cell_sampling_period, do: @cell_sampling_period

  @doc "Maximum number of samples retained per biotope before pruning kicks in."
  @spec cap() :: pos_integer()
  def cap, do: @cap

  @doc """
  Build the list of `TimeSeriesSample` attribute maps for the given state
  at the given wall-clock instant. Returns an empty list when the tick
  is not at a sampling boundary.

  Pure: no I/O.
  """
  @spec extract_samples(BiotopeState.t(), DateTime.t()) :: [map()]
  def extract_samples(%BiotopeState{tick_count: tick} = state, %DateTime{} = occurred_at) do
    pop_samples =
      if rem(tick, @sampling_period) == 0 do
        abundance_samples(state, occurred_at) ++
          metabolite_samples(state, occurred_at) ++
          signal_samples(state, occurred_at)
      else
        []
      end

    cell_samples =
      if rem(tick, @cell_sampling_period) == 0 do
        biomass_samples(state, occurred_at) ++ dna_damage_samples(state, occurred_at)
      else
        []
      end

    pop_samples ++ cell_samples
  end

  @doc """
  Insert all sample rows for one tick transition inside the caller's
  transaction. Returns `{:ok, [TimeSeriesSample.t()]}` or
  `{:error, changeset}` propagating the first insert failure.
  """
  @spec persist(Ecto.Repo.t(), BiotopeState.t(), DateTime.t()) ::
          {:ok, [TimeSeriesSample.t()]} | {:error, Ecto.Changeset.t()}
  def persist(repo, %BiotopeState{} = state, %DateTime{} = occurred_at) do
    samples = extract_samples(state, occurred_at)

    Enum.reduce_while(samples, {:ok, []}, fn attrs, {:ok, acc} ->
      case repo.insert(TimeSeriesSample.changeset(%TimeSeriesSample{}, attrs)) do
        {:ok, sample} -> {:cont, {:ok, [sample | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, inserted} -> {:ok, Enum.reverse(inserted)}
      err -> err
    end
  end

  @doc """
  Prune the oldest samples for a biotope when the row count exceeds the
  cap. Runs at most one prune per call, removing the lowest 10% of rows
  by `inserted_at`. Idempotent if the table is already under cap.

  Returns the number of rows deleted.
  """
  @spec prune(Ecto.Repo.t(), binary()) :: non_neg_integer()
  def prune(repo, biotope_id) when is_binary(biotope_id) do
    count =
      repo.aggregate(
        from(s in TimeSeriesSample, where: s.biotope_id == ^biotope_id),
        :count,
        :id
      )

    if count > @cap do
      to_delete = max(div(@cap, 10), 1)

      victim_ids =
        repo.all(
          from(s in TimeSeriesSample,
            where: s.biotope_id == ^biotope_id,
            order_by: [asc: s.inserted_at],
            limit: ^to_delete,
            select: s.id
          )
        )

      {n, _} = repo.delete_all(from(s in TimeSeriesSample, where: s.id in ^victim_ids))
      n
    else
      0
    end
  end

  @doc """
  Fetch samples in `[from_tick, to_tick]` for one biotope, optionally
  filtered by sample kind. Used by the trends viewer.
  """
  @spec list(binary(), keyword()) :: [TimeSeriesSample.t()]
  def list(biotope_id, opts \\ []) when is_binary(biotope_id) do
    from_tick = Keyword.get(opts, :from_tick, 0)
    to_tick = Keyword.get(opts, :to_tick, :max)
    kind = Keyword.get(opts, :kind)
    repo = Keyword.get(opts, :repo, Arkea.Repo)

    query =
      from s in TimeSeriesSample,
        where: s.biotope_id == ^biotope_id and s.tick >= ^from_tick,
        order_by: [asc: s.tick]

    query =
      case to_tick do
        :max -> query
        n when is_integer(n) -> from(s in query, where: s.tick <= ^n)
      end

    query =
      case kind do
        nil -> query
        k when is_binary(k) -> from(s in query, where: s.kind == ^k)
        k when is_atom(k) -> from(s in query, where: s.kind == ^Atom.to_string(k))
      end

    repo.all(query)
  end

  # ---------------------------------------------------------------------------
  # Sample builders (pure)

  defp abundance_samples(%BiotopeState{} = state, occurred_at) do
    Enum.map(state.lineages, fn %Lineage{} = lineage ->
      %{
        biotope_id: state.id,
        tick: state.tick_count,
        kind: "abundance",
        scope_id: lineage.id,
        payload: %{
          "by_phase" => stringify_keys(lineage.abundance_by_phase),
          "total" => Lineage.total_abundance(lineage)
        },
        inserted_at: occurred_at
      }
    end)
  end

  defp metabolite_samples(%BiotopeState{} = state, occurred_at) do
    Enum.map(state.phases, fn %Phase{} = phase ->
      %{
        biotope_id: state.id,
        tick: state.tick_count,
        kind: "metabolite_pool",
        scope_id: Atom.to_string(phase.name),
        payload: stringify_keys(phase.metabolite_pool),
        inserted_at: occurred_at
      }
    end)
  end

  defp signal_samples(%BiotopeState{} = state, occurred_at) do
    state.phases
    |> Enum.filter(fn %Phase{signal_pool: pool} -> map_size(pool) > 0 end)
    |> Enum.map(fn %Phase{} = phase ->
      %{
        biotope_id: state.id,
        tick: state.tick_count,
        kind: "signal_pool",
        scope_id: Atom.to_string(phase.name),
        payload: stringify_keys(phase.signal_pool),
        inserted_at: occurred_at
      }
    end)
  end

  defp biomass_samples(%BiotopeState{} = state, occurred_at) do
    state.lineages
    |> Enum.filter(fn l -> l.genome != nil end)
    |> Enum.map(fn %Lineage{} = lineage ->
      %{
        biotope_id: state.id,
        tick: state.tick_count,
        kind: "biomass",
        scope_id: lineage.id,
        payload: stringify_keys(lineage.biomass),
        inserted_at: occurred_at
      }
    end)
  end

  defp dna_damage_samples(%BiotopeState{} = state, occurred_at) do
    state.lineages
    |> Enum.filter(fn l -> l.genome != nil and l.dna_damage > 0.0 end)
    |> Enum.map(fn %Lineage{} = lineage ->
      %{
        biotope_id: state.id,
        tick: state.tick_count,
        kind: "dna_damage",
        scope_id: lineage.id,
        payload: %{"value" => lineage.dna_damage},
        inserted_at: occurred_at
      }
    end)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
