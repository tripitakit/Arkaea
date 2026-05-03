defmodule Arkea.Sim.Xenobiotic do
  @moduledoc """
  Xenobiotic catalog and target-class taxonomy (Phase 15 — DESIGN.md Block 8).

  Xenobiotics are environmental chemicals (antibiotics, biocides, mutagens)
  that interact with cellular machinery. In Arkea every xenobiotic is
  defined by:

  - `:target_class` — the cellular component the drug binds. The matching
    target abundance comes from `Phenotype.target_classes`, derived
    generatively from gene composition.
  - `:kd` — dissociation constant in the same dimensionless concentration
    scale used by `Phase.metabolite_pool`. Lower Kd → tighter binding,
    more damage at any given concentration.
  - `:mode` — `:cidal` (kills cells), `:static` (slows growth), `:mutagen`
    (raises µ; coupling deferred to Phase 17 SOS).
  - `:degradable_by_hydrolase` — when `true` the drug can be cleaved by
    a generic Arkea hydrolase (any gene that co-expresses
    `:substrate_binding` + `:catalytic_site(reaction_class: :hydrolysis)`).
    The β-lactamase trope is the canonical example.

  ## Generative resistance — what the genome can do

  Phase 15 surfaces three independent resistance mechanisms, all of them
  emergent from the existing 11 functional-domain types:

  1. **Target absence**: a lineage that does not encode the relevant
     `target_class` (e.g. no PBP-like genes) is intrinsically resistant
     to drugs that target it.
  2. **Enzymatic degradation**: a hydrolase-bearing lineage shrinks the
     drug pool by `degradation_rate × hydrolase_capacity × abundance`.
  3. **Efflux**: a lineage that co-encodes
     `:transmembrane_anchor + :channel_pore + :energy_coupling +
     :substrate_binding` reduces its *intracellular* drug concentration
     via `Phenotype.efflux_capacity`. Phase 15 models this as a single
     scalar applied to the binding probability; Phase 17 will refine
     into per-target efflux specificity.

  The catalog ships with one canonical antibiotic — a β-lactam-like
  agent — sufficient for the canonical RAS scenario in
  `DESIGN_STRESS-TEST.md`. New entries are additive.

  This module is **strictly pure**: no I/O, no OTP calls.
  """

  @typedoc "Xenobiotic catalog id (atom keys)."
  @type id :: atom()

  @typedoc "One catalog entry."
  @type entry :: %{
          target_class: atom(),
          kd: float(),
          mode: :cidal | :static | :mutagen,
          degradable_by_hydrolase: boolean()
        }

  @catalog %{
    # β-lactam antibiotic: targets PBP-like proteins (penicillin-binding
    # proteins, the cell-wall transpeptidases). Cidal because PBP
    # blockade derails cell-wall biosynthesis → osmotic lysis.
    # β-lactamases (Arkea proxy: hydrolases) cleave the β-lactam ring,
    # making the drug substrate for active resistance.
    beta_lactam: %{
      target_class: :pbp_like,
      kd: 10.0,
      mode: :cidal,
      degradable_by_hydrolase: true
    }
  }

  # Per-target sensitivity in `:cidal` mode — the maximum fitness loss
  # per fully-bound target. `:cidal` near 0.95 = catastrophic when the
  # drug saturates; `:static` halves growth; `:mutagen` does not affect
  # growth here (Phase 17 will couple it into µ).
  @mode_severity %{
    cidal: 0.95,
    static: 0.50,
    mutagen: 0.0
  }

  # Degradation rate constant: per (unit hydrolase capacity, unit drug
  # concentration, unit cell abundance). Conservative — Phase 15 only
  # needs the qualitative effect (a β-lactamase population eventually
  # detoxifies the pool), not a fitted kinetic curve.
  @k_degradation 1.0e-5

  # Efflux scaling: fraction of extracellular concentration that
  # actually reaches the cytoplasm under maximal efflux. With efflux
  # capacity = 1.0, intracellular = 0.10 × extracellular (a 10× pump).
  @max_efflux_protection 0.90

  @doc "Return the static catalog of xenobiotics."
  @spec catalog() :: %{id() => entry()}
  def catalog, do: @catalog

  @doc "List of xenobiotic ids known to the catalog."
  @spec ids() :: [id()]
  def ids, do: Map.keys(@catalog)

  @doc "Look up an entry. Returns `nil` if the id is unknown."
  @spec entry(id()) :: entry() | nil
  def entry(id) when is_atom(id), do: Map.get(@catalog, id)

  @doc "Mode-specific severity coefficient (`0.0..1.0`)."
  @spec mode_severity(:cidal | :static | :mutagen) :: float()
  def mode_severity(mode), do: Map.get(@mode_severity, mode, 0.0)

  @doc """
  Compute the bound fraction of a target under a given drug exposure.

  Saturating Hill-like response:

      bound = [drug_intracellular] / (Kd + [drug_intracellular])

  Returns a value in `0.0..1.0`.
  """
  @spec bound_fraction(float(), float()) :: float()
  def bound_fraction(intracellular_drug, kd)
      when is_number(intracellular_drug) and is_number(kd) and kd > 0.0 do
    if intracellular_drug <= 0.0 do
      0.0
    else
      intracellular_drug / (kd + intracellular_drug)
    end
  end

  @doc """
  Scale the extracellular drug concentration to its intracellular
  equivalent given the lineage's efflux capacity in `0.0..1.0`.

  At `efflux_capacity == 0.0` the cell sees the full external
  concentration; at `1.0` the pump knocks it down by `@max_efflux_protection`.
  """
  @spec intracellular_concentration(float(), float()) :: float()
  def intracellular_concentration(extracellular, efflux_capacity)
      when is_number(extracellular) and is_number(efflux_capacity) do
    capped_capacity = efflux_capacity |> max(0.0) |> min(1.0)
    extracellular * (1.0 - @max_efflux_protection * capped_capacity)
  end

  @doc """
  Aggregate fitness damage for a lineage from a xenobiotic pool.

  Walks the pool, multiplies the per-drug binding-driven damage by
  the lineage's target-class abundance, composes the survival factors
  multiplicatively, and returns a final survival value in `0.0..1.0`.

  Lineages without a matching target_class abundance, or that fully
  efflux the drug, end up at `1.0` (no damage).
  """
  @spec survival_factor(
          %{id() => float()},
          %{atom() => float()},
          float()
        ) :: float()
  def survival_factor(xenobiotic_pool, target_classes, efflux_capacity)
      when is_map(xenobiotic_pool) and is_map(target_classes) do
    Enum.reduce(xenobiotic_pool, 1.0, fn {xeno_id, conc}, acc ->
      case entry(xeno_id) do
        nil ->
          acc

        %{target_class: target, kd: kd, mode: mode} ->
          target_abundance = Map.get(target_classes, target, 0.0)
          intracellular = intracellular_concentration(conc, efflux_capacity)
          bound = bound_fraction(intracellular, kd)
          severity = mode_severity(mode)
          damage = bound * severity * target_abundance
          acc * max(0.0, 1.0 - damage)
      end
    end)
  end

  @doc """
  Compute the per-tick degradation removed from one drug entry.

  `degradation = @k_degradation × concentration × hydrolase_capacity ×
  abundance`. Capped at the current concentration (cannot remove more
  than is present). Returns a non-negative float.
  """
  @spec degradation_amount(float(), float(), non_neg_integer()) :: float()
  def degradation_amount(concentration, hydrolase_capacity, abundance)
      when is_number(concentration) and is_number(hydrolase_capacity) and
             is_integer(abundance) and abundance >= 0 do
    raw = @k_degradation * concentration * hydrolase_capacity * abundance
    raw |> max(0.0) |> min(concentration)
  end

  @doc "Per-second degradation rate constant (exposed for tests)."
  def k_degradation, do: @k_degradation

  @doc "Maximum efflux protection fraction (exposed for tests)."
  def max_efflux_protection, do: @max_efflux_protection
end
