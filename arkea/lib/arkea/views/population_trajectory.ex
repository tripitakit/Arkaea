defmodule Arkea.Views.PopulationTrajectory do
  @moduledoc """
  Pure view-model for the SimLive "Trends" tab (UI Phase C).

  Given a list of `TimeSeriesSample` rows of kind `"abundance"` plus
  the audit log entries for the same biotope, builds:

  - A list of per-lineage time series of total abundance (one
    `{lineage_id, [{tick, count}, …]}` pair per lineage).
  - A list of vertical-marker events with their tick coordinates,
    ready for `Chart.event_markers`.
  - A `tick_domain` `{min_tick, max_tick}` covering everything.

  This module reads no DB and renders no SVG. It only shapes data; the
  Phoenix component then maps to coordinates with `Arkea.Views.Chart`.
  """

  alias Arkea.Persistence.AuditLog
  alias Arkea.Persistence.TimeSeriesSample

  @marker_event_types ~w(intervention mass_lysis mutation_notable phage_burst colonization
                         sos_active mutator_emergence biofilm_formation biofilm_dispersal)

  # Phase 21 Top 5 #4 — traits exposed by `kind: "phenotype_trait"`
  # samples. Keep this in sync with `Arkea.Persistence.TimeSeries.
  # trait_payload/1`.
  @trait_keys ~w(base_growth_rate repair_efficiency energy_cost
                 dna_binding_affinity competence_score hydrolase_capacity
                 efflux_capacity structural_stability n_transmembrane
                 biofilm_capable)

  @type lineage_series :: %{
          id: String.t(),
          points: [{integer(), integer()}],
          peak: integer()
        }

  @type trait_lineage_series :: %{
          id: String.t(),
          points: [{integer(), float()}],
          min: float(),
          max: float()
        }

  @type marker :: %{
          tick: integer(),
          type: String.t(),
          payload: map()
        }

  @type t :: %{
          tick_domain: {integer(), integer()},
          population_domain: {integer(), integer()},
          lineages: [lineage_series()],
          markers: [marker()]
        }

  @type trait_t :: %{
          trait: String.t(),
          tick_domain: {integer(), integer()},
          value_domain: {float(), float()},
          lineages: [trait_lineage_series()],
          markers: [marker()]
        }

  @doc """
  Build the view-model from a list of abundance samples and audit
  entries. Both lists may be empty; the result will then have
  degenerate domains `{0, 0}` and empty series — callers should
  render a "no data yet" placeholder instead of an SVG.
  """
  @spec build([TimeSeriesSample.t()], [AuditLog.t()]) :: t()
  def build(samples, audit) when is_list(samples) and is_list(audit) do
    abundance_samples = Enum.filter(samples, fn s -> s.kind == "abundance" end)

    lineages = lineage_series(abundance_samples)
    {min_t, max_t} = tick_domain_for(abundance_samples)
    {min_y, max_y} = population_domain_for(lineages)
    markers = audit |> Enum.filter(&marker?/1) |> Enum.map(&marker_for/1)

    %{
      tick_domain: {min_t, max_t},
      population_domain: {min_y, max_y},
      lineages: lineages,
      markers: markers
    }
  end

  defp lineage_series(samples) do
    samples
    |> Enum.group_by(& &1.scope_id)
    |> Enum.map(fn {lineage_id, group} ->
      points =
        group
        |> Enum.map(fn s ->
          total = (s.payload && s.payload["total"]) || 0
          {s.tick, total}
        end)
        |> Enum.sort_by(&elem(&1, 0))

      peak =
        case points do
          [] -> 0
          ps -> ps |> Enum.map(&elem(&1, 1)) |> Enum.max()
        end

      %{id: lineage_id, points: points, peak: peak}
    end)
    |> Enum.sort_by(& &1.peak, :desc)
  end

  defp tick_domain_for([]), do: {0, 0}

  defp tick_domain_for(samples) do
    ticks = Enum.map(samples, & &1.tick)
    {Enum.min(ticks), Enum.max(ticks)}
  end

  defp population_domain_for([]), do: {0, 0}

  defp population_domain_for(lineages) do
    max_y =
      lineages
      |> Enum.map(& &1.peak)
      |> Enum.max(fn -> 0 end)

    {0, max_y}
  end

  defp marker?(%AuditLog{event_type: type}), do: type in @marker_event_types
  defp marker?(_), do: false

  defp marker_for(%AuditLog{} = entry) do
    %{
      tick: entry.occurred_at_tick,
      type: entry.event_type,
      payload: entry.payload || %{}
    }
  end

  # ---------------------------------------------------------------------------
  # Phase 21 Top 5 #4 — trait tracker

  @doc """
  Canonical list of trait keys exposed by `kind: "phenotype_trait"`
  samples — for the Trends-tab trait selector.
  """
  @spec trait_keys() :: [String.t()]
  def trait_keys, do: @trait_keys

  @doc """
  Build a per-lineage trait-trajectory view from `kind:
  "phenotype_trait"` samples.

  Slices a single trait out of each sample's payload and groups by
  lineage, exposing the same shape consumed by the Chart component
  but with `value_domain :: {float, float}` (instead of population's
  integer count). `markers` carries the same audit-event vertical
  bars as `build/2` so the user can correlate trait shifts with
  speciation, mass lysis, SOS activation, etc.
  """
  @spec build_trait([TimeSeriesSample.t()], [AuditLog.t()], String.t()) :: trait_t()
  def build_trait(samples, audit, trait)
      when is_list(samples) and is_list(audit) and is_binary(trait) do
    trait_samples = Enum.filter(samples, fn s -> s.kind == "phenotype_trait" end)

    lineages = trait_lineage_series(trait_samples, trait)
    {min_t, max_t} = trait_tick_domain(trait_samples)
    {min_y, max_y} = trait_value_domain(lineages)
    markers = audit |> Enum.filter(&marker?/1) |> Enum.map(&marker_for/1)

    %{
      trait: trait,
      tick_domain: {min_t, max_t},
      value_domain: {min_y, max_y},
      lineages: lineages,
      markers: markers
    }
  end

  defp trait_lineage_series(samples, trait) do
    samples
    |> Enum.group_by(& &1.scope_id)
    |> Enum.map(fn {lineage_id, group} ->
      points =
        group
        |> Enum.map(fn s -> {s.tick, trait_value(s.payload, trait)} end)
        |> Enum.reject(fn {_, v} -> is_nil(v) end)
        |> Enum.sort_by(&elem(&1, 0))

      {min_y, max_y} =
        case points do
          [] -> {0.0, 0.0}
          ps -> ps |> Enum.map(&elem(&1, 1)) |> Enum.min_max()
        end

      %{id: lineage_id, points: points, min: min_y, max: max_y}
    end)
    |> Enum.reject(fn series -> series.points == [] end)
    # Stable lineage ordering keeps the chart legend deterministic
    # across renders (no shuffle on equal max). Sort by max desc, then
    # by id asc as tie-breaker.
    |> Enum.sort(fn a, b ->
      cond do
        a.max > b.max -> true
        a.max < b.max -> false
        true -> a.id <= b.id
      end
    end)
  end

  # Booleans become 0.0/1.0 so they plot as a step trace (false=0, true=1)
  # — this keeps `biofilm_capable` charteable on the same axis as the
  # numeric traits.
  defp trait_value(payload, _trait) when not is_map(payload), do: nil

  defp trait_value(payload, trait) do
    case Map.get(payload, trait) do
      nil -> nil
      true -> 1.0
      false -> 0.0
      v when is_number(v) -> v * 1.0
      _ -> nil
    end
  end

  defp trait_tick_domain([]), do: {0, 0}

  defp trait_tick_domain(samples) do
    ticks = Enum.map(samples, & &1.tick)
    {Enum.min(ticks), Enum.max(ticks)}
  end

  defp trait_value_domain([]), do: {0.0, 0.0}

  defp trait_value_domain(lineages) do
    mins = Enum.map(lineages, & &1.min)
    maxs = Enum.map(lineages, & &1.max)
    {Enum.min(mins), Enum.max(maxs)}
  end
end
