defmodule Arkea.Views.GeneExpression do
  @moduledoc """
  Pure per-gene expression view (Phase 25 / 2.2).

  The phenotype runtime (`Arkea.Sim.Phenotype.from_genome/1`)
  aggregates every domain into a handful of *global* scalars:
  one `base_growth_rate`, one `dna_binding_affinity`, one
  `repair_efficiency` for the whole lineage. That's enough to
  drive the Phase 5/6/7 ATP balance, but it hides the
  per-gene granularity a microbiologist needs to answer
  "*when is gene X actually expressed?*".

  This module exposes the missing per-gene surface as a *pure
  derivation*: given a `Genome.t()` and (optionally) a phase
  `signal_pool`, it returns one entry per chromosome gene with
  a baseline expression level and a regulatory modulation.

  ## Phase 25 staging

  V1 returns a deliberately conservative model:

    * **`base_level`** — `1.0` for every gene that carries a
      productive structural domain (`:catalytic_site`,
      `:transmembrane_anchor`, `:dna_binding`, `:channel_pore`,
      `:energy_coupling`, `:structural_fold`, `:surface_tag`,
      `:repair_fidelity`); `0.0` for the few empty-shell cases
      (a `Gene.from_codons/1` that produced only
      `:regulator_output` / `:ligand_sensor` domains, with no
      structural payload to express).
    * **`modulation`** — `± regulatory_outputs`-derived shift
      from the gene's own `:regulator_output` domains: the
      sum of `±cooperativity × binding_affinity` across the
      gene's regulator domains, clamped to `[-1.0, 1.0]`.
      Self-modulation only (cross-gene σ-coordination is
      7.2b runtime).
    * **`expression`** — `clamp(base_level + modulation, 0.0,
      2.0)` — the value the `gene_expression` time-series
      sample would carry if the persistence layer wired it
      (7.X follow-up, deliberately not in this commit).

  The QS signal pool argument is accepted but unused in V1 —
  the slot exists so the function signature is stable when
  7.2b arrives and the modulation starts depending on it.

  Pure: no DB, no genome mutation, deterministic on the input
  genome.
  """

  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene

  @structural_types ~w(catalytic_site transmembrane_anchor dna_binding
                       channel_pore energy_coupling structural_fold
                       surface_tag repair_fidelity)a

  @type entry :: %{
          gene_id: String.t(),
          base_level: float(),
          modulation: float(),
          expression: float()
        }

  @doc """
  Per-gene expression entries for the chromosome.

  `signal_pool` is forward-compatible — it will be consumed
  by 7.2b once the runtime σ-coordination ships.
  """
  @spec derive(Genome.t(), map()) :: [entry()]
  def derive(%Genome{chromosome: chromosome}, _signal_pool \\ %{}) do
    Enum.map(chromosome, &gene_entry/1)
  end

  defp gene_entry(%Gene{id: id, domains: domains}) do
    base = base_level_for(domains)
    modulation = modulation_for(domains)

    %{
      gene_id: id,
      base_level: base,
      modulation: modulation,
      expression: clamp(base + modulation, 0.0, 2.0)
    }
  end

  defp base_level_for(domains) do
    if Enum.any?(domains, fn %Domain{type: t} -> t in @structural_types end),
      do: 1.0,
      else: 0.0
  end

  defp modulation_for(domains) do
    domains
    |> Enum.filter(fn %Domain{type: t} -> t == :regulator_output end)
    |> Enum.reduce(0.0, fn %Domain{params: params}, acc ->
      sign = if params[:mode] == :repressor, do: -1.0, else: 1.0
      contrib = sign * (params[:cooperativity] || 1.0) * binding_strength(domains)
      acc + contrib
    end)
    |> clamp(-1.0, 1.0)
  end

  defp binding_strength(domains) do
    domains
    |> Enum.filter(fn %Domain{type: t} -> t == :dna_binding end)
    |> Enum.map(fn %Domain{params: p} -> p[:binding_affinity] || 0.0 end)
    |> case do
      [] -> 0.0
      vals -> Enum.sum(vals) / length(vals)
    end
  end

  defp clamp(v, lo, hi), do: v |> max(lo) |> min(hi)
end
