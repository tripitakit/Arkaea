defmodule Arkea.Sim.Intergenic do
  @moduledoc """
  Pure runtime semantics for intergenic blocks attached to genes.

  These blocks are a compact gameplay-facing proxy for mechanisms that are
  biologically recognisable but intentionally abstracted in Arkea:

  - `sigma_promoter` and `multi_sigma_operator` bias expression capacity
  - `metabolite_riboswitch` relieves wasteful expression under starvation
  - `orit_site` and `integration_hotspot` bias transfer success
  - `repeat_array` and `duplication_hotspot` bias local rearrangements

  The functions in this module do not perform I/O and do not touch OTP state.
  """

  alias Arkea.Genome
  alias Arkea.Genome.Gene

  @empty_blocks %{expression: [], transfer: [], duplication: []}

  @doc """
  Aggregate expression-control modifiers from a genome.

  Returns:

  - `:sigma_bonus` — additive boost to the lineage-level sigma scalar
  - `:qs_multiplier` — multiplier applied to quorum-sensing sigma boosts
  - `:energy_relief` — ATP-equivalent relief applied under starvation
  """
  @spec expression_modifiers(Genome.t(), float(), float()) :: %{
          sigma_bonus: float(),
          qs_multiplier: float(),
          energy_relief: float()
        }
  def expression_modifiers(%Genome{} = genome, atp_yield, energy_cost)
      when is_number(atp_yield) and is_number(energy_cost) do
    promoter_count = count_modules(genome, :expression, "sigma_promoter")
    operator_count = count_modules(genome, :expression, "multi_sigma_operator")
    riboswitch_count = count_modules(genome, :expression, "metabolite_riboswitch")

    base_burden = max(energy_cost * 5.0, 0.0)

    starvation_factor =
      if base_burden > 0.0 do
        max(base_burden - atp_yield, 0.0) / base_burden
      else
        0.0
      end

    sigma_bonus = min(promoter_count * 0.08 + operator_count * 0.04, 0.45)
    qs_multiplier = min(1.0 + operator_count * 0.30, 2.0)

    energy_relief =
      min(base_burden * 0.18 * riboswitch_count * starvation_factor, base_burden * 0.60)

    %{
      sigma_bonus: sigma_bonus,
      qs_multiplier: qs_multiplier,
      energy_relief: energy_relief
    }
  end

  @doc """
  Multiplicative transfer bias for a donor/recipient pair.

  Accepts either a `Genome.plasmid()` map or a raw gene list (legacy).

  - `oriT_site` on the transferred plasmid is the strongest donor-side boost
  - `oriT_site` elsewhere in the donor genome gives a weaker mobilisable-cargo boost
  - `integration_hotspot` in the recipient genome improves establishment odds
  """
  @spec transfer_probability_multiplier(Genome.t(), Genome.t(), Genome.plasmid() | [Gene.t()]) ::
          float()
  def transfer_probability_multiplier(donor, recipient, %{genes: genes}) when is_list(genes),
    do: transfer_probability_multiplier(donor, recipient, genes)

  def transfer_probability_multiplier(
        %Genome{} = donor_genome,
        %Genome{} = recipient_genome,
        plasmid
      )
      when is_list(plasmid) do
    plasmid_orit = count_modules(plasmid, :transfer, "orit_site")

    donor_background_orit =
      count_modules(
        donor_genome.chromosome ++ Enum.flat_map(donor_genome.prophages, & &1.genes),
        :transfer,
        "orit_site"
      )

    recipient_hotspots = count_modules(recipient_genome, :transfer, "integration_hotspot")

    donor_bonus = min(plasmid_orit * 0.45 + donor_background_orit * 0.15, 0.90)
    recipient_bonus = min(recipient_hotspots * 0.20, 0.60)

    1.0 + donor_bonus + recipient_bonus
  end

  @doc """
  Local duplication susceptibility of a gene.

  The baseline weight is `1`. Repeats and dedicated hotspots add extra weight.
  """
  @spec duplication_weight(Gene.t()) :: pos_integer()
  def duplication_weight(%Gene{} = gene) do
    repeat_arrays = count_modules([gene], :duplication, "repeat_array")
    duplication_hotspots = count_modules([gene], :duplication, "duplication_hotspot")
    1 + repeat_arrays * 3 + duplication_hotspots * 2
  end

  @doc """
  Genome-level duplication bonus used to rebalance mutation-type sampling.

  The returned integer is in `0..12` and is intended to be moved from the
  substitution bucket into the duplication bucket.
  """
  @spec duplication_bonus(Genome.t()) :: non_neg_integer()
  def duplication_bonus(%Genome{chromosome: chromosome}) do
    chromosome
    |> Enum.map(&(duplication_weight(&1) - 1))
    |> Enum.sum()
    |> Kernel.*(2)
    |> min(12)
  end

  defp count_modules(%Genome{} = genome, family, module_id) do
    genome
    |> Genome.all_genes()
    |> count_modules(family, module_id)
  end

  defp count_modules(genes, family, module_id) when is_list(genes) do
    Enum.count(genes, fn gene ->
      module_id in modules_for_gene(gene, family)
    end)
  end

  defp modules_for_gene(%Gene{} = gene, family) do
    blocks = Map.get(gene, :intergenic_blocks, @empty_blocks)

    blocks
    |> Map.get(family, Map.get(blocks, Atom.to_string(family), []))
    |> List.wrap()
  end
end
