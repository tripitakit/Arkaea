defmodule Arkea.Views.GeneDiff do
  @moduledoc """
  Pure view-model for the codon-level diff between two gene
  variants (Phase 26 / 2.3b).

  `GenomeDiff` (Phase 22 / 2.3a) answers *which genes differ*
  between two genomes at the gene-identity granularity.
  `GeneDiff` zooms one level deeper and answers, for a chosen
  pair of genes (typically two variants of "the same" gene
  evolved along distinct lineages), *where exactly the codon
  sequences diverge* — both as a flat per-position track and as
  a per-domain summary that flags type-tag flips vs. parameter-
  only drift.

  ## v1 alignment caveat

  The diff uses *positional* alignment (zip by codon index).
  Insertions / deletions are surfaced only as a tail-mismatch:
  positions that exist in one gene but not the other are tagged
  `:unaligned_a` or `:unaligned_b`. Proper edit-distance
  alignment (Needleman–Wunsch on the codon alphabet) is *not*
  attempted here — that requires the ancestral-sequence
  reconstruction of 3.7 to define a meaningful gap penalty.

  In practice, lineages that diverged via point substitutions
  (the dominant mutation class in the Phase-1 mutator) align
  perfectly position-by-position, so the v1 view is correct
  for the common case. Lineages that diverged via indel /
  duplication / inversion will show large-scale tail mismatch;
  the consumer can flag this visually.

  ## Output shape

      %{
        gene_a_id: ...,
        gene_b_id: ...,
        codon_count_a: N_a,
        codon_count_b: N_b,
        substitutions: K,             # codon positions that differ
                                      # within the aligned prefix
        type_tag_changes: K_tag,      # subset of K landing on a
                                      # type_tag codon
        parameter_changes: K_param,   # subset of K landing on a
                                      # parameter_codon
        positions: [
          %{
            index: i,
            codon_a: c_a | nil,
            codon_b: c_b | nil,
            role: :type_tag | :parameter_codon | :unaligned_a | :unaligned_b,
            domain_index: d | nil,
            change: :match | :substitution | :unaligned
          }, ...
        ],
        domains: [
          %{
            domain_index: i,
            type_a: t_a | nil,
            type_b: t_b | nil,
            type_changed?: boolean,
            substitutions_in_tag: x,
            substitutions_in_params: y,
            params_a: m_a | nil,
            params_b: m_b | nil
          }, ...
        ]
      }
  """

  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene

  @phase1_domain_size 23
  @phase1_type_tag_size 3

  @type position :: %{
          index: non_neg_integer(),
          codon_a: integer() | nil,
          codon_b: integer() | nil,
          role: :type_tag | :parameter_codon | :unaligned_a | :unaligned_b,
          domain_index: non_neg_integer() | nil,
          change: :match | :substitution | :unaligned
        }

  @type domain_diff :: %{
          domain_index: non_neg_integer(),
          type_a: atom() | nil,
          type_b: atom() | nil,
          type_changed?: boolean(),
          substitutions_in_tag: non_neg_integer(),
          substitutions_in_params: non_neg_integer(),
          params_a: map() | nil,
          params_b: map() | nil
        }

  @type t :: %{
          gene_a_id: String.t(),
          gene_b_id: String.t(),
          codon_count_a: non_neg_integer(),
          codon_count_b: non_neg_integer(),
          substitutions: non_neg_integer(),
          type_tag_changes: non_neg_integer(),
          parameter_changes: non_neg_integer(),
          positions: [position()],
          domains: [domain_diff()]
        }

  @doc "Build the per-codon diff for the gene pair `(a, b)`."
  @spec build(Gene.t(), Gene.t()) :: t()
  def build(%Gene{} = a, %Gene{} = b) do
    positions = build_positions(a.codons, b.codons)

    substitutions = Enum.count(positions, &(&1.change == :substitution))

    type_tag_changes =
      Enum.count(positions, &(&1.change == :substitution and &1.role == :type_tag))

    parameter_changes =
      Enum.count(positions, &(&1.change == :substitution and &1.role == :parameter_codon))

    %{
      gene_a_id: a.id,
      gene_b_id: b.id,
      codon_count_a: length(a.codons),
      codon_count_b: length(b.codons),
      substitutions: substitutions,
      type_tag_changes: type_tag_changes,
      parameter_changes: parameter_changes,
      positions: positions,
      domains: build_domain_diffs(a.domains, b.domains, positions)
    }
  end

  defp build_positions(codons_a, codons_b) do
    aligned_len = min(length(codons_a), length(codons_b))

    aligned =
      Enum.zip(codons_a, codons_b)
      |> Enum.with_index()
      |> Enum.map(fn {{ca, cb}, idx} ->
        %{
          index: idx,
          codon_a: ca,
          codon_b: cb,
          role: role_at(idx),
          domain_index: div(idx, @phase1_domain_size),
          change: if(ca == cb, do: :match, else: :substitution)
        }
      end)

    tail_a =
      codons_a
      |> Enum.drop(aligned_len)
      |> Enum.with_index(aligned_len)
      |> Enum.map(fn {ca, idx} ->
        %{
          index: idx,
          codon_a: ca,
          codon_b: nil,
          role: :unaligned_a,
          domain_index: div(idx, @phase1_domain_size),
          change: :unaligned
        }
      end)

    tail_b =
      codons_b
      |> Enum.drop(aligned_len)
      |> Enum.with_index(aligned_len)
      |> Enum.map(fn {cb, idx} ->
        %{
          index: idx,
          codon_a: nil,
          codon_b: cb,
          role: :unaligned_b,
          domain_index: div(idx, @phase1_domain_size),
          change: :unaligned
        }
      end)

    aligned ++ tail_a ++ tail_b
  end

  defp role_at(idx) do
    if rem(idx, @phase1_domain_size) < @phase1_type_tag_size,
      do: :type_tag,
      else: :parameter_codon
  end

  defp build_domain_diffs(domains_a, domains_b, positions) do
    n = max(length(domains_a), length(domains_b))

    aligned_subs_by_domain =
      positions
      |> Enum.filter(&(&1.change == :substitution))
      |> Enum.group_by(& &1.domain_index)

    Enum.map(0..(n - 1)//1, fn idx ->
      a = Enum.at(domains_a, idx)
      b = Enum.at(domains_b, idx)

      subs = Map.get(aligned_subs_by_domain, idx, [])
      tag_subs = Enum.count(subs, &(&1.role == :type_tag))
      param_subs = Enum.count(subs, &(&1.role == :parameter_codon))

      %{
        domain_index: idx,
        type_a: domain_type(a),
        type_b: domain_type(b),
        type_changed?: domain_type_changed?(a, b),
        substitutions_in_tag: tag_subs,
        substitutions_in_params: param_subs,
        params_a: domain_params(a),
        params_b: domain_params(b)
      }
    end)
    |> case do
      [] -> []
      list -> list
    end
  end

  defp domain_type(%Domain{type: t}), do: t
  defp domain_type(_), do: nil

  defp domain_params(%Domain{params: p}), do: p
  defp domain_params(_), do: nil

  defp domain_type_changed?(%Domain{type: ta}, %Domain{type: tb}), do: ta != tb
  defp domain_type_changed?(_, _), do: false
end
