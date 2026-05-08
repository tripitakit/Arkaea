defmodule Arkea.Views.MetabolicMap do
  @moduledoc """
  Pure view-model for the SimLive "Chemistry" tab metabolic map
  (Phase 22 / 2.4 — mappa metabolica del biotopo).

  Given a `BiotopeState`, builds a heatmap matrix of *concentration*
  for the 13 canonical metabolites (rows) across the biotope's
  phases (columns). The same shape carries the per-cell raw value,
  the per-cell normalised intensity (`0.0..1.0`, used by the chart
  to drive a colour scale), and the row-max so a sparse phase
  doesn't blow out the colour mapping.

  ## Why per-row normalisation

  Metabolites in Arkea live on *very different concentration
  scales*: `glucose` peaks around `200..500` units in inflow;
  `iron` and `h2s` typically sit `0..30`. Normalising column-wise
  (per phase) would wash out the sulfur-cycle metabolites because
  glucose dominates; normalising globally is even worse. Per-row
  normalisation keeps every metabolite legible: the cell with the
  highest concentration of `h2s` is always cyan-saturated, even if
  glucose elsewhere is 100x larger.

  ## Pure

  No DB access. The caller is `SimLive.chemistry_panel`, which
  passes in the live `BiotopeState`.
  """

  alias Arkea.Ecology.Phase
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Metabolism

  # Order chosen to group biologically related cycles together so
  # the heatmap reads top-to-bottom as carbon → reduced one-carbons
  # → electron acceptors / donors → N → S → micronutrients.
  @canonical_metabolites [
    :glucose,
    :acetate,
    :lactate,
    :co2,
    :ch4,
    :h2,
    :oxygen,
    :nh3,
    :no3,
    :h2s,
    :so4,
    :iron,
    :po4
  ]

  @type cell :: %{
          metabolite: atom(),
          phase: atom(),
          value: float(),
          intensity: float()
        }

  @type row :: %{
          metabolite: atom(),
          max: float(),
          cells: [cell()]
        }

  @type t :: %{
          phases: [atom()],
          metabolites: [atom()],
          rows: [row()],
          biotope_max: float()
        }

  @doc "Canonical metabolite ordering used by the heatmap rows."
  @spec metabolite_order() :: [atom()]
  def metabolite_order, do: @canonical_metabolites

  @doc """
  Build the heatmap from a `BiotopeState`.

  Returns a `t()` with one row per canonical metabolite and one
  column per phase. Empty phases (no `metabolite_pool`) still get
  zero-valued cells so the user sees the phase column with the
  correct heading even when sparse.
  """
  @spec build(BiotopeState.t()) :: t()
  def build(%BiotopeState{} = state) do
    phase_names = Enum.map(state.phases, & &1.name)
    pools_by_phase = Map.new(state.phases, fn %Phase{name: n, metabolite_pool: p} -> {n, p} end)

    rows =
      Enum.map(@canonical_metabolites, fn metabolite ->
        cells =
          Enum.map(phase_names, fn phase_name ->
            value = pool_value(pools_by_phase, phase_name, metabolite)
            %{metabolite: metabolite, phase: phase_name, value: value, intensity: 0.0}
          end)

        row_max =
          cells |> Enum.map(& &1.value) |> Enum.max(fn -> 0.0 end)

        %{
          metabolite: metabolite,
          max: row_max,
          cells: Enum.map(cells, fn c -> %{c | intensity: intensity_for(c.value, row_max)} end)
        }
      end)

    biotope_max =
      rows |> Enum.map(& &1.max) |> Enum.max(fn -> 0.0 end)

    %{
      phases: phase_names,
      metabolites: @canonical_metabolites,
      rows: rows,
      biotope_max: biotope_max
    }
  end

  defp pool_value(pools_by_phase, phase_name, metabolite) do
    case Map.get(pools_by_phase, phase_name) do
      nil ->
        0.0

      pool when is_map(pool) ->
        pool
        |> Map.get(metabolite, 0.0)
        |> safe_float()
    end
  end

  defp safe_float(v) when is_float(v), do: max(v, 0.0)
  defp safe_float(v) when is_integer(v), do: max(v * 1.0, 0.0)
  defp safe_float(_), do: 0.0

  defp intensity_for(_value, max) when max <= 0.0, do: 0.0
  defp intensity_for(value, _max) when value <= 0.0, do: 0.0
  defp intensity_for(value, max), do: min(value / max, 1.0)

  @doc """
  Pretty label for a metabolite atom, used as row header in the
  heatmap. Falls back to the atom's string form for unknown values.
  """
  @spec metabolite_label(atom()) :: String.t()
  def metabolite_label(:glucose), do: "Glucose"
  def metabolite_label(:acetate), do: "Acetate"
  def metabolite_label(:lactate), do: "Lactate"
  def metabolite_label(:co2), do: "CO₂"
  def metabolite_label(:ch4), do: "CH₄"
  def metabolite_label(:h2), do: "H₂"
  def metabolite_label(:oxygen), do: "O₂"
  def metabolite_label(:nh3), do: "NH₃"
  def metabolite_label(:no3), do: "NO₃⁻"
  def metabolite_label(:h2s), do: "H₂S"
  def metabolite_label(:so4), do: "SO₄²⁻"
  def metabolite_label(:iron), do: "Fe²⁺/³⁺"
  def metabolite_label(:po4), do: "PO₄³⁻"
  def metabolite_label(other), do: Atom.to_string(other)

  @doc """
  Sanity check that the canonical list still matches
  `Arkea.Sim.Metabolism`. Used by tests to detect drift.
  """
  @spec canonical_matches_metabolism?() :: boolean()
  def canonical_matches_metabolism? do
    canonical = MapSet.new(@canonical_metabolites)
    metabolism_set = MapSet.new(0..12, &Metabolism.metabolite_atom/1)
    MapSet.equal?(canonical, metabolism_set)
  end
end
