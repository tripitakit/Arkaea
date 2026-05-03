defmodule Arkea.Sim.Biomass do
  @moduledoc """
  Continuous biomass progression and decay (Phase 14 — DESIGN.md Block 8).

  Each lineage carries `Lineage.biomass :: %{membrane, wall, dna}`, with
  every component in `0.0..1.0`. This module exposes the pure functions
  that move those values up (biosynthesis from the available metabolic
  budget) and down (osmotic shock, toxicity, mutational load). The
  resulting field is consumed by `Arkea.Sim.Tick.step_lysis/1`, which
  rolls stochastic death events when any component falls below its
  critical threshold.

  ## Conceptual model

  - `:membrane` — phospholipid bilayer + integral proteins. Biosynthesis
    proxy: count of `:transmembrane_anchor` domains in the proteome,
    saturating at 5. Decay proxy: osmotic-shock excess.
  - `:wall` — peptidoglycan / cell envelope. Biosynthesis proxy: number
    of genes that co-express a `:transmembrane_anchor` and a
    `:catalytic_site` (analogue of penicillin-binding proteins). Decay
    proxy: osmotic-shock excess + sulfur shortage.
  - `:dna` — chromosomal integrity. Biosynthesis proxy: phenotype
    `:repair_efficiency` × elemental factor (P-gated). Decay proxy:
    mutational load (Phase 17 will reuse this hook for
    `error_catastrophe`).

  Every per-tick delta is conservatively small (≤ ~0.05 per component);
  Phase 14 is meant to surface a *qualitative* selective pressure, not
  to fit a specific kinetic curve. The numbers are exposed as module
  attributes so tests and the `biological-realism-reviewer` agent can
  audit them in isolation.

  This module is **strictly pure**: no I/O, no OTP calls.
  """

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Sim.Phenotype

  @per_tick_progress_max 0.04
  @per_tick_decay_max 0.20

  # Osmotic optimum band: cells designed for 300 mOsm/L (mesophilic
  # freshwater baseline). Outside the band osmotic stress builds up;
  # the slope is gentle (1/600) so a *normal* phase contributes zero
  # decay even when its osmolarity is +/-100 mOsm/L off target.
  @osmotic_target 300.0
  @osmotic_tolerance 200.0
  @osmotic_scale 600.0

  @doc """
  Return the per-tick biomass delta for one lineage in one phase.

  The delta is decomposed into a positive `progress` component (driven
  by phenotype + ATP yield + elemental availability) and a negative
  `decay` component (driven by environmental stress + toxicity). The
  caller applies both to `Lineage.biomass` and clamps to `0.0..1.0`.

  Pure.
  """
  @spec compute_delta(
          Phenotype.t(),
          float(),
          float(),
          float(),
          Phase.t()
        ) :: %{
          progress: %{membrane: float(), wall: float(), dna: float()},
          decay: %{membrane: float(), wall: float(), dna: float()}
        }
  def compute_delta(
        %Phenotype{} = phenotype,
        atp_yield,
        elemental,
        toxicity,
        %Phase{} = phase
      ) do
    osmotic = osmotic_stress(phase.osmolarity)

    # Biosynthesis budget: bounded by ATP yield and the survival factor.
    # When toxicity zeros out, biosynthesis stalls regardless of ATP.
    budget =
      atp_yield
      |> max(0.0)
      |> Kernel./(50.0)
      |> min(1.0)
      |> Kernel.*(toxicity)

    membrane_capability = min(phenotype.n_transmembrane / 5.0, 1.0)
    wall_capability = wall_capability(phenotype)
    dna_capability = phenotype.repair_efficiency

    progress = %{
      membrane:
        clamp(@per_tick_progress_max * membrane_capability * budget, 0.0, @per_tick_progress_max),
      wall:
        clamp(
          @per_tick_progress_max * wall_capability * budget * elemental,
          0.0,
          @per_tick_progress_max
        ),
      dna:
        clamp(
          @per_tick_progress_max * dna_capability * budget * elemental,
          0.0,
          @per_tick_progress_max
        )
    }

    decay = %{
      membrane: clamp(osmotic * (1.0 - toxicity * 0.5 + 0.0), 0.0, @per_tick_decay_max),
      wall: clamp(osmotic * 1.5 * (1.0 - 0.5 * elemental), 0.0, @per_tick_decay_max),
      dna: clamp((1.0 - elemental) * 0.05, 0.0, @per_tick_decay_max)
    }

    %{progress: progress, decay: decay}
  end

  @doc """
  Apply a `compute_delta/5` result to a `Lineage.biomass`.

  Each component is updated as `clamp(value + progress - decay, 0.0, 1.0)`.
  Pure.
  """
  @spec apply_delta(Lineage.biomass(), %{progress: map(), decay: map()}) ::
          Lineage.biomass()
  def apply_delta(biomass, %{progress: progress, decay: decay}) do
    %{
      membrane: clamp(biomass.membrane + progress.membrane - decay.membrane, 0.0, 1.0),
      wall: clamp(biomass.wall + progress.wall - decay.wall, 0.0, 1.0),
      dna: clamp(biomass.dna + progress.dna - decay.dna, 0.0, 1.0)
    }
  end

  @doc """
  Per-tick lysis probability for a lineage given its current biomass.

  The probability is the maximum over the three components of
  `(threshold - value) / threshold` clipped to `0.0..1.0`. Each
  component contributes only when its value drops below the threshold;
  a fully intact cell sits at zero. Pure.

  Default thresholds:

  - `:membrane` 0.30 — losing more than 70% of membrane lipid integrity
    is incompatible with life.
  - `:wall` 0.40 — wall failure is the most common single cause of
    osmotic-shock death; threshold is conservative.
  - `:dna` 0.25 — chromosomal integrity has the longest tolerance band
    before lysis (DNA damage typically triggers SOS first; Phase 17
    couples that pathway).
  """
  @spec lysis_probability(Lineage.biomass()) :: float()
  def lysis_probability(%{membrane: m, wall: w, dna: d}) do
    membrane_pressure = max(0.0, (0.30 - m) / 0.30)
    wall_pressure = max(0.0, (0.40 - w) / 0.40)
    dna_pressure = max(0.0, (0.25 - d) / 0.25)

    [membrane_pressure, wall_pressure, dna_pressure]
    |> Enum.max()
    |> clamp(0.0, 1.0)
  end

  @doc "Constants helper: per-tick progress upper bound."
  def per_tick_progress_max, do: @per_tick_progress_max

  @doc "Constants helper: per-tick decay upper bound."
  def per_tick_decay_max, do: @per_tick_decay_max

  # ---------------------------------------------------------------------------
  # Private

  # Wall biosynthesis capability: count of genes that co-express a
  # `:transmembrane_anchor` and any `:catalytic_site` — proxy for
  # penicillin-binding-protein-like activity, which sits in the membrane
  # and catalyses peptidoglycan crosslinking.
  defp wall_capability(%Phenotype{n_transmembrane: 0}), do: 0.0

  defp wall_capability(%Phenotype{n_transmembrane: n}) do
    # The phenotype does not currently expose per-gene composition, so
    # we approximate from the aggregated count: as long as the lineage
    # encodes any membrane proteins and any catalytic activity at all
    # (`base_growth_rate > 0`), wall biosynthesis is feasible. The
    # capability scales with `n` to a soft cap at 5.
    min(n / 5.0, 1.0)
  end

  defp osmotic_stress(osmolarity) do
    over = max(0.0, abs(osmolarity - @osmotic_target) - @osmotic_tolerance)
    min(over / @osmotic_scale, @per_tick_decay_max)
  end

  defp clamp(value, lo, hi), do: value |> max(lo) |> min(hi)
end
