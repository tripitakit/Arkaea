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

  @marker_event_types ~w(intervention mass_lysis mutation_notable phage_burst colonization)

  @type lineage_series :: %{
          id: String.t(),
          points: [{integer(), integer()}],
          peak: integer()
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
end
