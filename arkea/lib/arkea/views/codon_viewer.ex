defmodule Arkea.Views.CodonViewer do
  @moduledoc """
  Pure view-model for the codon-level zoom (Phase 26 / 2.6).

  Given a `Gene.t()`, returns the sequence of its codons annotated
  with the structural role each codon plays inside the gene's
  Phase-1 grammar:

    * `:type_tag` — one of the three codons that pick the
      domain category. A substitution here can flip the
      `Domain.type` (and surfaces as `:domain_flip` in the
      audit log).
    * `:parameter_codon` — one of the 20 codons that contribute
      to the domain's continuous parameters via the weighted-sum
      kernel. A substitution here drifts the parameter value
      without changing the category.
    * `:promoter_codon` / `:regulatory_codon` — codons of the
      optional regulation blocks (Phase 25 / 7.3 parsers). Empty
      until a builder populates the blocks.

  This is the *data layer* the future Codon viewer UI consumes;
  rendering is a separate component. The shape is intentionally
  flat (one entry per codon) so the consumer can either lay the
  sequence out as a single linear track or chunk it back per
  domain.
  """

  alias Arkea.Genome.Codon
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene

  @type role :: :type_tag | :parameter_codon | :promoter_codon | :regulatory_codon

  @type entry :: %{
          index: non_neg_integer(),
          codon: Codon.t(),
          symbol: atom(),
          role: role(),
          domain_index: non_neg_integer() | nil,
          domain_type: atom() | nil,
          codon_in_domain: non_neg_integer() | nil
        }

  @type domain_summary :: %{
          domain_index: non_neg_integer(),
          type: atom(),
          start: non_neg_integer(),
          end_pos: non_neg_integer(),
          params: map()
        }

  @type t :: %{
          gene_id: String.t(),
          codon_count: non_neg_integer(),
          domain_count: non_neg_integer(),
          domains: [domain_summary()],
          codons: [entry()],
          promoter_codons: [entry()],
          regulatory_codons: [entry()]
        }

  @phase1_domain_size 23
  @phase1_type_tag_size 3

  @doc "Build the per-codon annotated view of a gene."
  @spec build(Gene.t()) :: t()
  def build(%Gene{} = gene) do
    chromosome_codons = annotate_chromosome_codons(gene)
    promoter_codons = annotate_block_codons(gene.promoter_block, :promoter_codon)
    regulatory_codons = annotate_block_codons(gene.regulatory_block, :regulatory_codon)
    domains = summarise_domains(gene)

    %{
      gene_id: gene.id,
      codon_count: length(gene.codons),
      domain_count: length(gene.domains),
      domains: domains,
      codons: chromosome_codons,
      promoter_codons: promoter_codons,
      regulatory_codons: regulatory_codons
    }
  end

  defp annotate_chromosome_codons(%Gene{codons: codons, domains: domains}) do
    domain_types =
      domains
      |> Enum.with_index()
      |> Enum.map(fn {%Domain{type: t}, i} -> {i, t} end)
      |> Map.new()

    codons
    |> Enum.with_index()
    |> Enum.map(fn {c, idx} ->
      domain_idx = div(idx, @phase1_domain_size)
      codon_in_domain = rem(idx, @phase1_domain_size)
      role = if codon_in_domain < @phase1_type_tag_size, do: :type_tag, else: :parameter_codon

      %{
        index: idx,
        codon: c,
        symbol: safe_codon_atom(c),
        role: role,
        domain_index: domain_idx,
        domain_type: Map.get(domain_types, domain_idx),
        codon_in_domain: codon_in_domain
      }
    end)
  end

  defp annotate_block_codons(nil, _role), do: []

  defp annotate_block_codons(codons, role) when is_list(codons) do
    codons
    |> Enum.with_index()
    |> Enum.map(fn {c, idx} ->
      %{
        index: idx,
        codon: c,
        symbol: safe_codon_atom(c),
        role: role,
        domain_index: nil,
        domain_type: nil,
        codon_in_domain: nil
      }
    end)
  end

  defp summarise_domains(%Gene{domains: domains}) do
    domains
    |> Enum.with_index()
    |> Enum.map(fn {%Domain{} = d, idx} ->
      start = idx * @phase1_domain_size

      %{
        domain_index: idx,
        type: d.type,
        start: start,
        end_pos: start + @phase1_domain_size - 1,
        params: d.params
      }
    end)
  end

  defp safe_codon_atom(c) do
    Codon.to_atom(c)
  rescue
    _ -> :unknown
  end
end
