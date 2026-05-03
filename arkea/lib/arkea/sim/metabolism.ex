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

  # Phase 14 — Metabolite toxicity profile (DESIGN.md Block 8.A.2).
  #
  # Each entry maps a metabolite id to `{threshold, scale}`:
  #
  # - `threshold` — concentration above which the metabolite begins to
  #   damage cells. Below threshold there is no toxicity.
  # - `scale` — concentration delta that produces a 100% knock-out of
  #   metabolic activity. The toxicity contribution is
  #   `min(1.0, max(0.0, (concentration - threshold) / scale))`.
  #
  # Lineages owning a *detoxify* enzyme for a given metabolite (a
  # `:catalytic_site(reaction_class: :reduction)` whose substrate-binding
  # targets that metabolite — proxy for catalase, sulfide-quinone
  # oxidoreductase, lactate dehydrogenase, etc.) bypass the toxicity for
  # that specific metabolite. See `toxicity_factor/2`.
  #
  # The numerical thresholds are deliberately conservative: the goal of
  # Phase 14 is to surface a *qualitative* selective pressure (anaerobes
  # die in aerobic phases unless they encode catalase-like protection),
  # not to fit a specific kinetic curve. Phase 17 will refine these
  # against published K_i values for cytochrome inhibition (Cooper &
  # Brown 2008 for H₂S; Imlay 2008 for O₂).
  #
  # Concentration scale: Arkea metabolite pools use arbitrary
  # dimensionless units; typical aerobic biotopes seed oxygen around
  # 50–100, so the threshold sits well above the mean to avoid
  # triggering on background levels. Toxicity bites only at
  # concentrations associated with rapid radical chemistry (oxidative
  # stress) or metal-protein cytochrome poisoning.
  @toxicity_profile %{
    oxygen: {200.0, 800.0},
    h2s: {20.0, 80.0},
    lactate: {30.0, 100.0}
  }

  # Phase 18 — Cross-feeding closure (DESIGN.md Block 8 Phase 18).
  #
  # Each metabolite consumed produces stoichiometric by-products that
  # are returned to `Phase.metabolite_pool`. The map below collapses
  # several real microbial pathways into a single per-substrate
  # coefficient table — coarse but sufficient to close the C, N, S,
  # Fe, H₂ cycles emergently:
  #
  # - **Carbon**: glucose → acetate + CO₂ + H₂ (mixed-acid fermentation
  #   baseline); acetate → CO₂ (acetate respiration); lactate → acetate
  #   + CO₂ + H₂ (syntrophic fermentation); CH₄ → CO₂ (methanotrophy);
  #   CO₂ → CH₄ (autotrophic methanogenesis, rare).
  # - **Sulfur**: SO₄²⁻ → H₂S (sulfate reduction); H₂S → SO₄²⁻ (sulfide
  #   oxidation).
  # - **Nitrogen**: NH₃ → NO₃⁻ (nitrification); NO₃⁻ → NH₃ + CO₂
  #   (denitrification → ammonification).
  # - **Hydrogen**: H₂ is consumed without by-product (terminal electron
  #   donor), but lactate fermentation and acetate-respiration fluxes
  #   re-introduce H₂ into the pool — the syntrophic loop.
  # - **Iron / O₂**: cycle internally through redox couples, no
  #   metabolite by-product.
  #
  # Coefficients are **fractional** (yield per unit of substrate
  # consumed). They sum to ≤ 1.0 per substrate in mass-equivalent
  # terms — Phase 18 does not enforce strict mass conservation; the
  # goal is the qualitative closure of the C/N/S/Fe cycles, not a
  # fitted thermodynamic model.
  @byproducts %{
    glucose: %{acetate: 0.5, co2: 0.3, h2: 0.2},
    acetate: %{co2: 0.8},
    lactate: %{acetate: 0.4, co2: 0.4, h2: 0.2},
    ch4: %{co2: 0.9},
    co2: %{ch4: 0.1},
    so4: %{h2s: 0.7},
    h2s: %{so4: 0.7},
    nh3: %{no3: 0.7},
    no3: %{nh3: 0.5, co2: 0.3}
  }

  # Phase 14 — Elemental floors (DESIGN.md Block 8.A.3).
  #
  # Each elemental nutrient (P, N, Fe, S) must be taken up at a minimum
  # per-cell rate. Below the floor the cell cannot synthesise its
  # corresponding biomass component (P → DNA, N → membrane/wall
  # proteins, Fe → cofactors, S → sulfur amino acids). The
  # `elemental_factor/2` returns a `0.0..1.0` scalar applied to ATP
  # yield; it goes to zero only when *all* nutrients are exhausted, but
  # any single deficit drags it down proportionally.
  @elemental_metabolites [:po4, :nh3, :no3, :iron, :so4, :h2s]
  @elemental_floor_per_cell 0.001

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

  @doc """
  The set of metabolite ids tracked as toxic (Phase 14).

  Used by tests and by `Arkea.Sim.Phenotype.from_genome/1` to build the
  `:detoxify_targets` MapSet from the genome.
  """
  @spec toxic_metabolites() :: [atom()]
  def toxic_metabolites, do: Map.keys(@toxicity_profile)

  @doc """
  Compute the toxicity-survival factor for a lineage in a phase.

  Returns a value in `0.0..1.0` that scales the lineage's ATP yield
  (and therefore its growth budget) based on the per-metabolite
  concentrations in `metabolite_pool` and the lineage's
  `detoxify_targets`. A lineage that encodes the matching detoxify
  enzyme is fully shielded for that metabolite (factor 1.0 contribution
  from that source); otherwise the per-metabolite contribution drops
  with the over-threshold concentration.

  Multiple toxic metabolites compose multiplicatively: surviving two
  unrelated stressors both at the threshold edge is harder than
  surviving one. Pure.

  ## Examples

      # Anaerobe (no detoxify targets) under aerobic conditions
      iex> Metabolism.toxicity_factor(%{oxygen: 1.0}, MapSet.new())
      0.5

      # Aerobic-tolerant lineage (catalase-like for O₂) is unaffected
      iex> Metabolism.toxicity_factor(%{oxygen: 1.0}, MapSet.new([:oxygen]))
      1.0
  """
  @spec toxicity_factor(%{atom() => float()}, MapSet.t(atom())) :: float()
  def toxicity_factor(metabolite_pool, detoxify_targets) when is_map(metabolite_pool) do
    Enum.reduce(@toxicity_profile, 1.0, fn {metabolite, {threshold, scale}}, acc ->
      if MapSet.member?(detoxify_targets, metabolite) do
        acc
      else
        conc = Map.get(metabolite_pool, metabolite, 0.0)
        knock = max(0.0, conc - threshold) / max(scale, 1.0e-9)
        survival = max(0.0, 1.0 - knock)
        acc * survival
      end
    end)
  end

  @doc """
  Compute the elemental-constraint factor for a lineage in a phase.

  Returns a value in `0.0..1.0` reflecting how close the lineage is to
  the elemental floor required to build new biomass.

  Only elements the lineage *attempts* to take up (i.e. for which the
  phenotype carries a `:substrate_binding` domain) participate in the
  constraint. A lineage that has no affinity for phosphate is assumed
  to satisfy its phosphorus demand from baseline cellular pools (the
  prototype does not model recycling explicitly). Specialist lineages
  that do encode an uptake transporter are accountable: when their
  preferred nutrient pool drops below the elemental floor, biosynthesis
  is throttled.

  Within the considered elements:

  - per-element score = `min(1.0, uptake_per_cell / elemental_floor)`
  - overall factor    = geometric mean of per-element scores

  Multiplicative composition (geometric mean) means a single missing
  nutrient drags down the factor without zeroing it: a P-limited cell
  still respires, but its biosynthesis is slowed.

  Pure.
  """
  @spec elemental_factor(%{atom() => float()}, %{atom() => map()}, non_neg_integer()) ::
          float()
  def elemental_factor(uptake_map, substrate_affinities, abundance)
      when is_map(uptake_map) and is_map(substrate_affinities) and is_integer(abundance) and
             abundance > 0 do
    attempted = attempted_elements(substrate_affinities)

    if attempted == [] do
      1.0
    else
      floor = @elemental_floor_per_cell * abundance

      scores =
        Enum.map(attempted, fn metabolite ->
          uptake = Map.get(uptake_map, metabolite, 0.0)
          min(1.0, uptake / max(floor, 1.0e-9))
        end)

      product = Enum.reduce(scores, 1.0, fn s, acc -> acc * max(s, 1.0e-3) end)
      :math.pow(product, 1.0 / length(scores))
    end
  end

  def elemental_factor(_uptake_map, _affinities, 0), do: 1.0

  @doc "Set of metabolites considered elemental nutrients (Phase 14)."
  @spec elemental_metabolites() :: [atom()]
  def elemental_metabolites, do: @elemental_metabolites

  @doc """
  Stoichiometric by-product coefficients for one consumed metabolite
  (Phase 18 — cross-feeding closure).

  Returns a `%{atom() => float()}` map of products → fractional yield
  per unit of `metabolite` consumed. Empty map means the metabolite
  is a terminal electron sink with no metabolite-level by-product
  (O₂, Fe, PO₄³⁻).

  Pure.
  """
  @spec byproducts(atom()) :: %{atom() => float()}
  def byproducts(metabolite), do: Map.get(@byproducts, metabolite, %{})

  @doc """
  Compute the total by-product flux for an uptake map (Phase 18).

  Sums per-substrate by-product yields across the entire uptake map.
  The return is shaped like `metabolite_pool` so the caller can
  merge it back into `Phase.metabolite_pool` after the consumption
  step.
  """
  @spec compute_byproducts(%{atom() => float()}) :: %{atom() => float()}
  def compute_byproducts(uptake_map) when is_map(uptake_map) do
    Enum.reduce(uptake_map, %{}, fn {substrate, amount}, acc ->
      Enum.reduce(byproducts(substrate), acc, fn {product, coeff}, inner ->
        delta = amount * coeff

        if delta > 0.0 do
          Map.update(inner, product, delta, &(&1 + delta))
        else
          inner
        end
      end)
    end)
  end

  defp attempted_elements(affinities) do
    @elemental_metabolites
    |> Enum.filter(fn m -> Map.has_key?(affinities, m) end)
  end
end
