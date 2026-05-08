defmodule Arkea.Genome.Regulation do
  @moduledoc """
  Pure parsers for the `Gene.promoter_block` and
  `Gene.regulatory_block` codon sequences (Phase 25 / 7.3).

  Up to Phase 24 both fields were declared on `Gene` as `nil`
  in Phase 1 — they had a slot in the schema but no semantic
  surface. Phase 25 introduces the *structural* parsing layer
  so downstream callers (the runtime σ-coordination of 7.2b,
  the regulatory-network view of 2.5) can reason about the
  binding sites of a promoter and the metabolite sensitivity
  of a riboswitch without hand-rolling the codon arithmetic.

  Same staging strategy as `regulatory_outputs` (Phase 21
  / 7.1): pure parsing only, no runtime cabling here. The
  parsers are forgiving — a `nil` block returns `[]`, and a
  too-short block degrades gracefully to whatever entries can
  be assembled rather than raising.

  ## Convention

  ### `promoter_block`

  A flat sequence of codons interpreted in *4-codon strides*.
  Each stride is one σ-binding site:

      [signature_codon_a, signature_codon_b, signature_codon_c, strength_codon]

    * `signature` — `"a,b,c"` (the 3 codons joined with commas)
      — tag matched against σ-factor signatures by future
      runtime code.
    * `strength` — norm of `strength_codon / 19.0` clamped to
      `0.0..1.0` — how much this site amplifies the σ when
      bound.

  A trailing partial stride (< 4 codons) is silently dropped.
  Total sites = `div(length(codons), 4)`.

  ### `regulatory_block`

  A flat sequence of codons interpreted in *5-codon strides*.
  Each stride is one *riboswitch* / regulatory input:

      [metabolite_codon, threshold_codon, _, mode_codon, magnitude_codon]

    * `metabolite_id` — `rem(metabolite_codon, 13)` — index
      into `Arkea.Sim.Metabolism` canonical metabolites
      (0 .. 12).
    * `threshold` — norm of `threshold_codon / 19.0` clamped
      to `0.0..1.0` — relative concentration that flips the
      riboswitch.
    * `mode` — `rem(mode_codon, 2)` — `0 → :activator,
      1 → :repressor`.
    * `magnitude` — norm of `magnitude_codon / 19.0` clamped
      to `0.0..1.0` — gain factor on the leader gene's σ when
      the riboswitch fires.

  A trailing partial stride (< 5 codons) is silently dropped.
  """

  alias Arkea.Genome.Gene

  @type promoter_site :: %{
          signature: String.t(),
          strength: float()
        }

  @type riboswitch_entry :: %{
          metabolite_id: 0..12,
          threshold: float(),
          mode: :activator | :repressor,
          magnitude: float()
        }

  @promoter_stride 4
  @regulatory_stride 5
  @metabolite_count 13

  @doc """
  Parse `Gene.promoter_block` into a list of σ-binding sites.

  Returns `[]` for a `nil` or empty block.
  """
  @spec promoter_sites(Gene.t() | nil) :: [promoter_site()]
  def promoter_sites(nil), do: []
  def promoter_sites(%Gene{promoter_block: nil}), do: []

  def promoter_sites(%Gene{promoter_block: codons}) when is_list(codons) do
    codons
    |> Enum.chunk_every(@promoter_stride, @promoter_stride, :discard)
    |> Enum.map(&promoter_site_of/1)
  end

  defp promoter_site_of([a, b, c, strength]) do
    %{
      signature: "#{a},#{b},#{c}",
      strength: norm_codon(strength)
    }
  end

  @doc """
  Parse `Gene.regulatory_block` into a list of riboswitch
  entries.

  Returns `[]` for a `nil` or empty block.
  """
  @spec riboswitches(Gene.t() | nil) :: [riboswitch_entry()]
  def riboswitches(nil), do: []
  def riboswitches(%Gene{regulatory_block: nil}), do: []

  def riboswitches(%Gene{regulatory_block: codons}) when is_list(codons) do
    codons
    |> Enum.chunk_every(@regulatory_stride, @regulatory_stride, :discard)
    |> Enum.map(&riboswitch_of/1)
  end

  defp riboswitch_of([metabolite, threshold, _, mode, magnitude]) do
    %{
      metabolite_id: rem(safe_int(metabolite), @metabolite_count),
      threshold: norm_codon(threshold),
      mode: if(rem(safe_int(mode), 2) == 0, do: :activator, else: :repressor),
      magnitude: norm_codon(magnitude)
    }
  end

  # The codon alphabet is `0..19` (20 symbols, see
  # `Arkea.Genome.Codon.symbol_count/0`); the highest valid value
  # is 19 so we normalise on that.
  @max_codon_value 19

  defp norm_codon(c) do
    c
    |> safe_int()
    |> Kernel./(@max_codon_value)
    |> max(0.0)
    |> min(1.0)
  end

  defp safe_int(c) when is_integer(c), do: c
  defp safe_int(_), do: 0
end
