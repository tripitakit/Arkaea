defmodule Arkea.Sim.HGT.RecognitionSite do
  @moduledoc """
  Inspectable R-M recognition site (Phase 30 / partial closure of
  L1.7).

  Pre-Phase-30, an R-M recognition site was an opaque 4-codon
  string `"c0,c1,c2,c3"` (`Phenotype.restriction_profile` /
  `methylation_profile`). The L1.7 honesty marker said the
  *specificity* of restriction enzymes was *not inspectable at
  sequence level* and methylation *not visualisable as a pattern*
  — the codon stream encoding the site was hidden behind the
  4-codon CSV signature.

  This module surfaces the underlying sequence and a Type-I /
  Type-II / Type-III classification without changing the runtime
  matching mechanism (`Defense.restriction_check/3` still keys on
  the 4-codon `signature` so existing Phase-12 calibration is
  preserved). It is a *view layer* extension: the `signature` is
  the legacy matching token; `pattern`, `length_in_codons`,
  `palindrome?` and `type` are the new inspectable fields.

  ## Type taxonomy (canonical bacterial R-M; Roberts et al. 2003)

    * **Type II** — short *palindromic* recognition site (e.g.
      EcoRI: `5'-GAATTC-3' / 3'-CTTAAG-5'`). Restriction enzyme
      and methylase recognise the same site; cleavage happens at
      or near the site. **Palindrome ⇒ Type II** in Arkea's proxy
      classifier.

    * **Type I** — *bipartite asymmetric* site (e.g.
      EcoKI: `AAC(N6)GTGC`): two specific codon clusters
      separated by a non-specific spacer. The enzyme
      methylates and cleaves at sites distant from each other.
      **Asymmetric pattern with a clear bipartite layout** in
      Arkea's classifier.

    * **Type III** — short *asymmetric* site (e.g. EcoP15I:
      `5'-CAGCAG-3'`); cleavage at a fixed distance from the
      site. Distinguished from Type I by being short (no clear
      bipartite layout) and asymmetric. The Phase-1 codon model
      can encode Type III only as "asymmetric, short core" —
      we use it as the catch-all for non-palindromic sites that
      don't show the bipartite Type-I shape.

  ## Bipartite layout heuristic (Type I detection)

  A canonical Type I site has two specific clusters separated by
  a "spacer" of unspecific (low-complexity) codons. We approximate
  this with a *gap density* metric:

      gap_density = count of `0`-codons in the middle 50 % of the
                    pattern, divided by middle length.

  When `gap_density > 0.5` AND the pattern is asymmetric, we tag
  it `:type_i` (bipartite). Otherwise asymmetric patterns default
  to `:type_iii`.

  This is intentionally a *coarse* classifier — full Type I/II/III
  encoding would require named methylation positions and per-base
  modification states, which is out of scope for the partial
  closure; a future Phase-30+ track can refine it.

  ## Pattern extraction

  The pattern is the *full* parameter codon stream of the
  `:catalytic_site` domain (typically 20 codons in Phase 1), not
  just the first 4 used for the signature. This is what the
  inspector view shows so the player can read "this enzyme
  recognises [3, 17, 9, 0, 0, 0, 0, 12, 5, ...]" rather than just
  the opaque `"3,17,9,0"` signature.

  Pure data; no I/O.
  """

  use TypedStruct

  @typedoc "Recognition-site type, after Roberts 2003."
  @type rm_type :: :type_i | :type_ii | :type_iii

  typedstruct enforce: true do
    field :signature, binary()
    field :pattern, [integer()]
    field :length_in_codons, non_neg_integer()
    field :palindrome?, boolean()
    field :type, rm_type()
    field :role, :restriction | :methylation
  end

  @palindrome_tolerance 0
  @gap_density_threshold 0.5

  @doc """
  Build a `RecognitionSite.t()` from a `:catalytic_site` domain's
  signature + parameter codons + role tag.

  `role` is `:restriction` for hydrolysis-class enzymes
  (cleavage activity) and `:methylation` for isomerization-class
  enzymes (modification activity); the field is informational —
  matching during defense uses `signature` only.
  """
  @spec new(binary(), [integer()], :restriction | :methylation) :: t()
  def new(signature, pattern, role)
      when is_binary(signature) and is_list(pattern) and role in [:restriction, :methylation] do
    palindrome? = palindrome?(pattern)
    type = classify_type(pattern, palindrome?)

    %__MODULE__{
      signature: signature,
      pattern: pattern,
      length_in_codons: length(pattern),
      palindrome?: palindrome?,
      type: type,
      role: role
    }
  end

  @doc """
  True when the codon pattern equals its own reverse, within
  `@palindrome_tolerance` mismatches. Phase-1 codons live in
  `0..19` — there is no "complementary base" mapping, so we use
  exact reversal as the canonical palindrome test (a Phase-30+
  refinement could introduce an explicit codon-complement
  involution `c -> 19 - c` if needed).
  """
  @spec palindrome?([integer()]) :: boolean()
  def palindrome?(pattern) when is_list(pattern) do
    reversed = Enum.reverse(pattern)
    mismatches = pattern |> Enum.zip(reversed) |> Enum.count(fn {a, b} -> a != b end)
    div(mismatches, 2) <= @palindrome_tolerance
  end

  @doc """
  Classify the pattern as Type I / II / III. Pure heuristic.
  """
  @spec classify_type([integer()], boolean()) :: rm_type()
  def classify_type(_pattern, true), do: :type_ii

  def classify_type(pattern, false) when is_list(pattern) do
    if bipartite?(pattern), do: :type_i, else: :type_iii
  end

  defp bipartite?(pattern) do
    n = length(pattern)

    if n < 6 do
      false
    else
      mid_start = div(n, 4)
      mid_len = n - 2 * mid_start
      middle = pattern |> Enum.drop(mid_start) |> Enum.take(mid_len)

      zero_density =
        case middle do
          [] -> 0.0
          xs -> Enum.count(xs, &(&1 == 0)) / length(xs)
        end

      zero_density > @gap_density_threshold
    end
  end
end
