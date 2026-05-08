defmodule Arkea.Views.PhenotypeDistribution do
  @moduledoc """
  Pure view-model for the SimLive "Trends" tab phenotype-distribution
  panel (Phase 22 / 2.8 — distribuzione fenotipica del biotopo).

  Given a list of `phenotype_trait` time-series samples *for one tick*
  and the live lineage abundances, builds a per-lineage scatter:

  - x-axis: the selected trait's value at that tick
  - y-axis: lineage total abundance
  - radius: ∝ √abundance (so a 100x lineage is ~10x the radius, not 100x)
  - centre-of-mass: abundance-weighted mean of the trait

  This is not a kernel-density violin plot — it's a *strip plot with
  weighted markers* plus a vertical reference line at the population-
  weighted mean. Biologically this surfaces:

    * **Polarisation / incipient speciation** — two visible clusters
      on the x-axis indicate the population is splitting on the trait.
    * **Drift** — the centre-of-mass moves between ticks.
    * **Outliers** — small lineages with extreme trait values stand
      out next to the bulk.

  ## Tick selection

  Callers pass *all* `phenotype_trait` samples; the builder picks the
  most recent tick that has at least one sample. This matches the
  user expectation "show me the distribution *now*" while staying
  pure (no DB access).

  ## Boolean traits

  Booleans (`biofilm_capable`) plot at x ∈ {0.0, 1.0} like the time-
  series tracker — the strip plot then visibly shows the
  abundance-share split between the two states.
  """

  alias Arkea.Persistence.TimeSeriesSample

  @type point :: %{
          id: String.t(),
          x: float(),
          y: non_neg_integer(),
          radius: float()
        }

  @type t :: %{
          trait: String.t(),
          tick: integer(),
          x_domain: {float(), float()},
          y_domain: {non_neg_integer(), non_neg_integer()},
          weighted_mean: float() | nil,
          total_abundance: non_neg_integer(),
          points: [point()]
        }

  @doc """
  Build the distribution view.

  Arguments:

  - `samples` — list of `TimeSeriesSample` rows; rows of kind other
    than `"phenotype_trait"` are ignored.
  - `trait` — string trait name, must match a key in
    `Arkea.Views.PopulationTrajectory.trait_keys/0`.
  - `abundances` — `%{lineage_id => total_abundance}`. Lineages
    without an abundance entry default to 0 and are excluded from the
    plot (an extinct lineage carries no marker).

  Returns a `t()` with empty domains and `[]` points when no usable
  data is available; callers should render a "no data" placeholder
  in that case.
  """
  @spec build([TimeSeriesSample.t()], String.t(), %{String.t() => non_neg_integer()}) :: t()
  def build(samples, trait, abundances)
      when is_list(samples) and is_binary(trait) and is_map(abundances) do
    trait_samples = Enum.filter(samples, fn s -> s.kind == "phenotype_trait" end)

    case latest_tick(trait_samples) do
      nil ->
        empty(trait, 0)

      tick ->
        points =
          trait_samples
          |> Enum.filter(fn s -> s.tick == tick end)
          |> Enum.map(fn s -> {s.scope_id, trait_value(s.payload, trait)} end)
          |> Enum.reject(fn {_, v} -> is_nil(v) end)
          |> Enum.map(fn {id, x} ->
            ab = Map.get(abundances, id, 0)
            %{id: id, x: x, y: ab, radius: radius_for(ab)}
          end)
          |> Enum.filter(fn p -> p.y > 0 end)
          |> Enum.sort_by(& &1.y, :desc)

        if points == [] do
          empty(trait, tick)
        else
          %{
            trait: trait,
            tick: tick,
            x_domain: domain(points, & &1.x),
            y_domain: y_domain(points),
            weighted_mean: weighted_mean(points),
            total_abundance: Enum.sum_by(points, & &1.y),
            points: points
          }
        end
    end
  end

  defp empty(trait, tick) do
    %{
      trait: trait,
      tick: tick,
      x_domain: {0.0, 0.0},
      y_domain: {0, 0},
      weighted_mean: nil,
      total_abundance: 0,
      points: []
    }
  end

  defp latest_tick([]), do: nil

  defp latest_tick(samples) do
    samples
    |> Enum.map(& &1.tick)
    |> Enum.max(fn -> nil end)
  end

  # Booleans → 0.0/1.0 (same convention as PopulationTrajectory.build_trait/3).
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

  # √abundance keeps the marker scale legible across 4-5 orders of
  # magnitude (1 → 1, 100 → 10, 10 000 → 100 — units are arbitrary
  # at this layer; the chart component scales them to viewport pixels).
  defp radius_for(abundance) when abundance >= 0, do: :math.sqrt(abundance)

  defp domain([], _f), do: {0.0, 0.0}

  defp domain(points, f) do
    values = Enum.map(points, f)
    {Enum.min(values), Enum.max(values)}
  end

  defp y_domain([]), do: {0, 0}

  defp y_domain(points) do
    ys = Enum.map(points, & &1.y)
    {0, Enum.max(ys)}
  end

  defp weighted_mean([]), do: nil

  defp weighted_mean(points) do
    total = Enum.sum_by(points, & &1.y)

    if total == 0 do
      nil
    else
      sum_xy = Enum.sum_by(points, fn p -> p.x * p.y end)
      sum_xy / total
    end
  end
end
