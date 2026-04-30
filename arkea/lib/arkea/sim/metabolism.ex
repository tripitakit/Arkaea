defmodule Arkea.Sim.Metabolism do
  @moduledoc """
  Pure metabolic-kinetics module for Phase 5 (IMPLEMENTATION-PLAN.md §5 — Phase 5).

  Three responsibilities:

  1. **Canonical metabolite catalogue** — maps integer ids (0..12) from the
     domain system (Block 6) to atom keys used in `Phase.metabolite_pool`.

  2. **Michaelis-Menten uptake rate** — `uptake_rate/3` computes the rate of
     substrate uptake per cell for a single metabolite. Output is bounded in
     `[0.0, kcat]`.

  3. **Lineage uptake and ATP yield** — `compute_uptake/3` aggregates uptake
     across an entire sub-population, clamped so no more substrate is consumed
     than is available. `atp_yield/1` converts those uptake fluxes to a
     dimensionless "metabolic power index" via stoichiometric coefficients
     approximated from real biochemistry (see `@atp_coefficients`).

  ## ATP coefficients

  The coefficients are first-pass biological approximations, not exact
  stoichiometries:

  - Aerobic glucose respiration yields ~32 ATP/mol, but in Phase 5 we use 2.0
    (fermentation baseline) because we do not yet model O₂-coupled upregulation.
    This underestimates aerobic heterotrophs slightly but keeps the relative
    ordering correct (glucose > acetate > h2s > iron).
  - O₂, CO₂, NO₃⁻, SO₄²⁻, PO₄³⁻ are electron acceptors or nutrients, not
    direct ATP sources; their coefficients are 0.0.
  - Scale is dimensionless and uniform across all lineages, so relative
    selection pressure is biologically correct even if absolute values are
    approximate.

  Phase 6+ will refine stoichiometry as new metabolic pathways are modelled.

  ## Discipline

  This module is **strictly pure**. No I/O, no side effects, no state.
  """

  @metabolites [
    # 0
    :glucose,
    # 1
    :acetate,
    # 2
    :lactate,
    # 3
    :co2,
    # 4
    :ch4,
    # 5
    :h2,
    # 6
    :oxygen,
    # 7
    :nh3,
    # 8
    :no3,
    # 9
    :h2s,
    # 10
    :so4,
    # 11
    :iron,
    # 12
    :po4
  ]

  # Approximate stoichiometric ATP yield per unit uptake.
  # Nature of the approximation:
  # - glucose 2.0: fermentation baseline; aerobic yield (~32 ATP) not modelled
  #   as a separate pathway yet — Phase 5 simplification.
  # - nh3 0.8: nitrification (ammonia oxidation by AOB/AOA) yields ~2–4 ATP/mol.
  # - h2s 0.6: sulfide oxidation (e.g. Beggiatoa); low but positive yield.
  # - iron 0.3: Fe²⁺ oxidation (e.g. Acidithiobacillus ferrooxidans); very low
  #   yield per oxidation event (0.1–1 ATP/mol, here mid-range).
  # - Electron acceptors (oxygen, no3, so4) and nutrients (co2, po4):
  #   contribute no direct ATP; yield comes from the electron donor side.
  @atp_coefficients %{
    glucose: 2.0,
    acetate: 1.0,
    lactate: 0.5,
    h2: 1.0,
    ch4: 1.5,
    nh3: 0.8,
    h2s: 0.6,
    iron: 0.3,
    oxygen: 0.0,
    co2: 0.0,
    no3: 0.0,
    so4: 0.0,
    po4: 0.0
  }

  @doc """
  Return the canonical atom key for a metabolite integer id.

  Used by `Arkea.Sim.Phenotype.from_genome/1` to convert the integer
  `target_metabolite_id` produced by `Domain.compute_params/1` into the
  atom keys expected by `Phase.metabolite_pool`.

  ## Examples

      iex> Arkea.Sim.Metabolism.metabolite_atom(0)
      :glucose
      iex> Arkea.Sim.Metabolism.metabolite_atom(8)
      :no3
  """
  @spec metabolite_atom(integer()) :: atom()
  def metabolite_atom(id) when id in 0..12, do: Enum.at(@metabolites, id)

  @doc """
  Return the ordered list of all 13 canonical metabolite atoms.

  Ordering matches the integer id convention (index 0 = `:glucose`, … ,
  index 12 = `:po4`), which corresponds to the canonical metabolite table in
  DESIGN.md Block 6.
  """
  @spec canonical_metabolites() :: [atom()]
  def canonical_metabolites, do: @metabolites

  @doc """
  Michaelis-Menten uptake rate for a single cell.

  Returns the instantaneous uptake rate `v` for a substrate at concentration
  `concentration` given the catalytic constant `kcat` and the Michaelis
  constant `km`:

      v = kcat × S / (Km + S)

  Boundary behaviours:
  - `concentration == 0.0` → `0.0` (no substrate, no uptake).
  - `concentration >> km` → approaches `kcat` (saturation).
  - `concentration << km` → approaches `kcat × concentration / km` (linear).

  ## Preconditions

  - `kcat >= 0.0`
  - `km > 0.0`
  - `concentration >= 0.0`

  Returns a value in `[0.0, kcat]`. Pure.
  """
  @spec uptake_rate(float(), float(), float()) :: float()
  def uptake_rate(_kcat, _km, concentration) when concentration == 0.0, do: 0.0

  def uptake_rate(kcat, km, concentration)
      when is_float(concentration) and concentration >= 0.0 and is_float(km) and km > 0.0 do
    kcat * concentration / (km + concentration)
  end

  @doc """
  Compute the total substrate uptake for a lineage in a single phase.

  For each metabolite atom present in `affinities`:
  1. Fetch the current concentration from `metabolite_pool` (default 0.0).
  2. Compute per-cell rate via `uptake_rate/3`.
  3. Multiply by `abundance` to get the population-level total.
  4. Clamp: `min(total, concentration)` — cannot consume more than present.

  Returns a map `%{metabolite_atom => total_uptake_consumed}`.
  Metabolites with zero concentration (absent from pool or pool concentration
  zero) have zero uptake and are omitted from the returned map.

  Pure.
  """
  @spec compute_uptake(
          %{atom() => %{km: float(), kcat: float()}},
          %{atom() => float()},
          non_neg_integer()
        ) :: %{atom() => float()}
  def compute_uptake(affinities, metabolite_pool, abundance)
      when is_map(affinities) and is_map(metabolite_pool) and is_integer(abundance) and
             abundance >= 0 do
    Enum.reduce(affinities, %{}, fn {metabolite, %{km: km, kcat: kcat}}, acc ->
      conc = Map.get(metabolite_pool, metabolite, 0.0)

      if conc > 0.0 do
        total = abundance * uptake_rate(kcat, km, conc)
        consumed = min(total, conc)
        Map.put(acc, metabolite, consumed)
      else
        acc
      end
    end)
  end

  @doc """
  Compute the dimensionless ATP-yield index from a map of uptake fluxes.

  Sums `uptake[m] * coefficient[m]` for all metabolites with non-zero uptake.
  Metabolites absent from the uptake map contribute 0.0. Metabolites not in
  `@atp_coefficients` (which covers all 13 canonical metabolites) also
  contribute 0.0.

  The returned value is a **dimensionless index** proportional to metabolic
  power per tick — not a physical ATP count. It scales uniformly across all
  lineages, so relative selection pressure is correct even though absolute
  values are approximate (see module docs for coefficient justification).

  Pure.
  """
  @spec atp_yield(%{atom() => float()}) :: float()
  def atp_yield(uptake_map) when is_map(uptake_map) do
    Enum.reduce(uptake_map, 0.0, fn {metabolite, amount}, acc ->
      coeff = Map.get(@atp_coefficients, metabolite, 0.0)
      acc + amount * coeff
    end)
  end
end
