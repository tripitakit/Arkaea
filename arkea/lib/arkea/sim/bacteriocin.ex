defmodule Arkea.Sim.Bacteriocin do
  @moduledoc """
  Bacteriocin warfare (Phase 17 — DESIGN.md Block 8).

  Bacteriocins are narrow-spectrum proteinaceous toxins secreted by
  one bacterial population to kill close relatives. The producing
  cell encodes both the toxin and a matching immunity tag (Surface
  tag) that distinguishes self from target — this kin recognition is
  exactly the dynamic that makes bacteriocins a *strategic* weapon
  rather than indiscriminate poison (Riley & Wertz 2002).

  ## Generative pattern

  A bacteriocin gene is any gene that co-expresses

      :substrate_binding   (target acquisition)
      :catalytic_site(:hydrolysis)   (membrane / wall disruption)
      :transmembrane_anchor   (secretion machinery)

  on the same gene. The producer also ships at least one
  `:surface_tag` somewhere in its genome — that tag is the
  *immunity* signature: lineages whose `surface_tags` set contains
  the same atom are immune to the producer's toxin.

  ## Pool dynamics

  Each tick:

  1. Every producer in a phase secretes
     `@secretion_per_cell × abundance` units into
     `Phase.toxin_pool`, keyed by the producer's lineage id.
  2. Every non-immune lineage in the same phase loses
     `Σ_pools (toxin_concentration × @damage_rate)` from its
     `Lineage.biomass.wall` value.
  3. The pool decays alongside other phase pools through
     `Phase.dilute/1`.

  The damage path goes through `Lineage.biomass.wall`, not directly
  through abundance. Cells whose wall integrity collapses below the
  Phase 14 lysis threshold are killed by `Tick.step_lysis/1`. This
  routes bacteriocin lethality through the same osmotic-shock /
  PBP-deficiency pipeline that already powers cell-wall failure.

  ## Constants

  Rates are deliberately conservative — the goal of Phase 17 is to
  make bacteriocins a *real* selective pressure when both producer
  and non-immune target co-reside, not to fit specific assay
  kinetics.
  """

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Gene
  alias Arkea.Sim.Phenotype

  # Per-cell secretion per tick. Producer abundance × this constant =
  # toxin units added to the pool. Calibrated low so a 5_000-cell
  # producer adds ~0.5 units/tick — observable on multi-tick
  # timescales but well short of one-shot kills.
  @secretion_per_cell 0.0001

  # Per-tick wall damage applied to a fully susceptible cell exposed
  # to a toxin pool of unit concentration. Wall integrity collapses
  # to the lysis threshold (`Biomass.lysis_probability/1` 0.40) over
  # ~50–100 ticks at sustained unit concentration, leaving room for
  # adaptive responses (target-tag mutation, immunity acquisition via
  # HGT) before total kill.
  @damage_rate 0.005

  # Per-pool damage cap. The cap matters under absurd toxin
  # saturation: even if 200 producers cumulatively reach a
  # concentration of 1.0, the wall damage from any single pool stays
  # ≤ this constant, so a target population can mount a defence.
  @max_damage_per_pool 0.05

  @doc "Per-cell secretion rate (exposed for tests)."
  def secretion_per_cell, do: @secretion_per_cell

  @doc "Per-tick wall damage scaling (exposed for tests)."
  def damage_rate, do: @damage_rate

  @doc "Per-pool damage cap (exposed for tests)."
  def max_damage_per_pool, do: @max_damage_per_pool

  @doc """
  True iff a genome encodes a viable bacteriocin producer.

  A viable producer needs *both*:

    1. at least one bacteriocin-shaped gene (the toxin); and
    2. at least one `:surface_tag` domain anywhere in the genome (the
       self-immunity marker).

  The two-prong requirement matches in vivo selection: a bacteriocin
  gene without a co-encoded immunity protein kills its own host on
  expression, so any lineage without (2) cannot stably carry (1) —
  it would be driven extinct by selection within a generation.
  Encoding both as a hard precondition for "producer" status keeps
  the simulation from generating self-suicidal mutants that flood
  the toxin pool with no offsetting fitness benefit.
  """
  @spec producer?(Genome.t()) :: boolean()
  def producer?(%Genome{} = genome) do
    has_toxin_gene?(genome) and has_immunity_tag?(genome)
  end

  defp has_toxin_gene?(%Genome{} = genome) do
    genome
    |> Genome.all_genes()
    |> Enum.any?(&bacteriocin_gene?/1)
  end

  defp has_immunity_tag?(%Genome{} = genome) do
    genome
    |> Genome.all_domains()
    |> Enum.any?(fn d -> d.type == :surface_tag end)
  end

  @doc """
  Compute the bacteriocin-relevant identity of a phenotype.

  Returns a map with:

    - `:producer?` — boolean producer flag (matches `producer?/1`).
    - `:secretion_rate` — per-cell rate to add to the pool (zero for
      non-producers).
    - `:immunity_tags` — `MapSet` of `:surface_tag` atoms that confer
      immunity to producers carrying any of them.
  """
  @spec profile(Phenotype.t() | Genome.t()) :: %{
          producer?: boolean(),
          secretion_rate: float(),
          immunity_tags: MapSet.t(atom())
        }
  def profile(%Genome{} = genome) do
    is_producer = producer?(genome)

    %{
      producer?: is_producer,
      secretion_rate: if(is_producer, do: @secretion_per_cell, else: 0.0),
      immunity_tags:
        Phenotype.from_genome(genome).surface_tags
        |> Enum.reject(&is_nil/1)
        |> MapSet.new()
    }
  end

  def profile(%Phenotype{surface_tags: tags}) do
    %{
      producer?: false,
      secretion_rate: 0.0,
      immunity_tags: tags |> Enum.reject(&is_nil/1) |> MapSet.new()
    }
  end

  @doc """
  Run one bacteriocin tick across a single phase.

  Returns `{updated_lineages, updated_phase}`. Pure.

  Steps:

  1. Identify producers, accumulate their secretion into
     `phase.toxin_pool`.
  2. For every non-immune lineage with abundance in this phase,
     reduce `biomass.wall` by the cumulative damage of the
     non-self-tagged pools.
  """
  @spec step([Lineage.t()], Phase.t()) :: {[Lineage.t()], Phase.t()}
  def step(lineages, %Phase{} = phase) do
    profiles = Map.new(lineages, fn l -> {l.id, lineage_profile(l)} end)

    pool_with_secretion = secrete_into_pool(phase.toxin_pool, lineages, profiles, phase.name)

    new_lineages =
      Enum.map(lineages, fn lineage ->
        apply_damage(lineage, pool_with_secretion, profiles, phase.name)
      end)

    {new_lineages, %{phase | toxin_pool: pool_with_secretion}}
  end

  # ---------------------------------------------------------------------------
  # Private

  defp lineage_profile(%Lineage{genome: nil}),
    do: %{producer?: false, secretion_rate: 0.0, immunity_tags: MapSet.new()}

  defp lineage_profile(%Lineage{genome: genome}), do: profile(genome)

  defp bacteriocin_gene?(%Gene{domains: domains}) do
    has_type?(domains, :substrate_binding) and
      has_type?(domains, :transmembrane_anchor) and
      Enum.any?(domains, fn d ->
        d.type == :catalytic_site and d.params[:reaction_class] == :hydrolysis
      end)
  end

  defp has_type?(domains, type), do: Enum.any?(domains, fn d -> d.type == type end)

  defp secrete_into_pool(pool, lineages, profiles, phase_name) do
    Enum.reduce(lineages, pool, fn lineage, acc ->
      profile = Map.fetch!(profiles, lineage.id)

      if profile.producer? do
        abundance = Lineage.abundance_in(lineage, phase_name)
        increment = abundance * profile.secretion_rate

        if increment > 0.0 do
          Map.update(acc, lineage.id, increment, &(&1 + increment))
        else
          acc
        end
      else
        acc
      end
    end)
  end

  defp apply_damage(%Lineage{} = lineage, pool, profiles, phase_name)
       when map_size(pool) == 0 do
    _ = profiles
    _ = phase_name
    lineage
  end

  defp apply_damage(%Lineage{} = lineage, pool, profiles, phase_name) do
    abundance = Lineage.abundance_in(lineage, phase_name)

    cond do
      abundance == 0 ->
        lineage

      lineage.genome == nil ->
        lineage

      true ->
        target_profile = Map.fetch!(profiles, lineage.id)

        damage =
          Enum.reduce(pool, 0.0, fn {producer_id, conc}, acc ->
            cond do
              producer_id == lineage.id ->
                acc

              # Self-immunity: any matching surface_tag protects.
              not MapSet.disjoint?(
                target_profile.immunity_tags,
                producer_immunity_tags(profiles, producer_id)
              ) ->
                acc

              true ->
                acc + min(@max_damage_per_pool, conc * @damage_rate)
            end
          end)

        if damage <= 0.0 do
          lineage
        else
          new_wall = max(lineage.biomass.wall - damage, 0.0)
          new_biomass = %{lineage.biomass | wall: new_wall}
          %{lineage | biomass: new_biomass, fitness_cache: nil}
        end
    end
  end

  defp producer_immunity_tags(profiles, producer_id) do
    case Map.get(profiles, producer_id) do
      nil -> MapSet.new()
      profile -> profile.immunity_tags
    end
  end
end
