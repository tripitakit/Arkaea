defmodule Arkea.Views.RestrictionInspector do
  @moduledoc """
  Pure view-model for the R-M restriction inspector (Phase 30 / partial
  closure of L1.7).

  Given a `Lineage.t()` (or its `Genome.t()`), surfaces the lineage's
  restriction-modification armoury at sequence resolution: the
  *full codon pattern* of each recognition site, its
  Type-I / Type-II / Type-III classification, palindrome flag, and
  whether the cell methylates its own site (auto-protection — the
  classical Arber-Dussoix host-modification self/non-self
  discrimination).

  Pre-Phase-30 the only inspectable handle was an opaque 4-codon
  signature like `"3,17,9,0"`. Now the player sees the underlying
  codon stream (e.g. `[3, 17, 9, 0, 0, 0, 0, 12, 5, 11, 11, 5, 12, 0, 0, 0, 0, 9, 17, 3]`)
  and a meaningful "this is a Type II palindrome" label, which is
  what the L1.7 honesty marker said was missing.

  ## Output shape

      %{
        lineage_id: ...,
        restriction_count: K_R,
        methylation_count: K_M,
        self_protected_signatures: [String.t()],   # restriction sites also methylated → auto-immune
        unprotected_signatures: [String.t()],      # restriction sites NOT methylated → would self-cleave
        sites: [
          %{
            signature: String.t(),
            pattern: [integer()],
            length_in_codons: pos_integer(),
            palindrome?: boolean(),
            type: :type_i | :type_ii | :type_iii,
            role: :restriction | :methylation,
            self_protected?: boolean()
          }, ...
        ],
        type_distribution: %{
          type_i: non_neg_integer(),
          type_ii: non_neg_integer(),
          type_iii: non_neg_integer()
        }
      }

  Pure: no I/O.
  """

  alias Arkea.Ecology.Lineage
  alias Arkea.Genome
  alias Arkea.Sim.HGT.RecognitionSite
  alias Arkea.Sim.Phenotype

  @type site_entry :: %{
          signature: String.t(),
          pattern: [integer()],
          length_in_codons: pos_integer(),
          palindrome?: boolean(),
          type: :type_i | :type_ii | :type_iii,
          role: :restriction | :methylation,
          self_protected?: boolean()
        }

  @type t :: %{
          lineage_id: String.t() | nil,
          restriction_count: non_neg_integer(),
          methylation_count: non_neg_integer(),
          self_protected_signatures: [String.t()],
          unprotected_signatures: [String.t()],
          sites: [site_entry()],
          type_distribution: %{
            type_i: non_neg_integer(),
            type_ii: non_neg_integer(),
            type_iii: non_neg_integer()
          }
        }

  @doc """
  Build the inspector view from a `Lineage.t()`. Lineages with
  `genome: nil` (delta-encoded descendants) yield an empty view.
  """
  @spec build(Lineage.t()) :: t()
  def build(%Lineage{id: id, genome: nil}) do
    empty_view(id)
  end

  def build(%Lineage{id: id, genome: %Genome{} = genome}) do
    build_from_genome(genome, id)
  end

  @doc "Build the inspector view from a bare `Genome.t()`."
  @spec from_genome(Genome.t()) :: t()
  def from_genome(%Genome{} = genome), do: build_from_genome(genome, nil)

  defp build_from_genome(%Genome{} = genome, lineage_id) do
    %{restriction_sites: rest_sites, methylation_sites: methyl_sites} =
      Phenotype.rm_profiles_detailed(genome)

    methyl_signatures = MapSet.new(methyl_sites, & &1.signature)

    rest_entries = Enum.map(rest_sites, &site_entry(&1, methyl_signatures))
    methyl_entries = Enum.map(methyl_sites, &site_entry(&1, methyl_signatures))

    self_protected =
      rest_sites
      |> Enum.filter(fn s -> MapSet.member?(methyl_signatures, s.signature) end)
      |> Enum.map(& &1.signature)
      |> Enum.uniq()

    unprotected =
      rest_sites
      |> Enum.reject(fn s -> MapSet.member?(methyl_signatures, s.signature) end)
      |> Enum.map(& &1.signature)
      |> Enum.uniq()

    sites = rest_entries ++ methyl_entries

    %{
      lineage_id: lineage_id,
      restriction_count: length(rest_sites),
      methylation_count: length(methyl_sites),
      self_protected_signatures: self_protected,
      unprotected_signatures: unprotected,
      sites: sites,
      type_distribution: type_distribution(sites)
    }
  end

  defp site_entry(%RecognitionSite{} = s, methyl_signatures) do
    %{
      signature: s.signature,
      pattern: s.pattern,
      length_in_codons: s.length_in_codons,
      palindrome?: s.palindrome?,
      type: s.type,
      role: s.role,
      self_protected?: MapSet.member?(methyl_signatures, s.signature)
    }
  end

  defp type_distribution(sites) do
    base = %{type_i: 0, type_ii: 0, type_iii: 0}
    Enum.reduce(sites, base, fn site, acc -> Map.update(acc, site.type, 1, &(&1 + 1)) end)
  end

  defp empty_view(lineage_id) do
    %{
      lineage_id: lineage_id,
      restriction_count: 0,
      methylation_count: 0,
      self_protected_signatures: [],
      unprotected_signatures: [],
      sites: [],
      type_distribution: %{type_i: 0, type_ii: 0, type_iii: 0}
    }
  end
end
