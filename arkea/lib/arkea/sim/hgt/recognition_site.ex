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
    # Phase 31 / L1.7 full closure — per-position methylation
    # tracking. For methylase sites, the set of codon indices
    # (`0..length_in_codons - 1`) at which the methyltransferase
    # has placed a methyl mark. Restriction sites carry an empty
    # set (they don't methylate; the field is co-typed for
    # uniform protection-coverage checks).
    field :methylated_positions, MapSet.t(non_neg_integer()), default: MapSet.new()
  end

  @palindrome_tolerance 0
  @gap_density_threshold 0.5
  # Phase-1 codon alphabet is `0..19`. The `complement involution`
  # `c → @codon_max - c` plays the role of the canonical Watson-Crick
  # base-pair complement (A↔T, G↔C) at the codon level: a "complement
  # palindrome" matches its own reverse-complement, the way EcoRI's
  # recognition site `5'-GAATTC-3'` is the same DNA viewed from
  # either strand. Phase 31 detected only *exact* palindromes
  # (sequence equals its reversal in plain coordinates); Phase 32
  # adds complement palindromes so we no longer miscategorise
  # textbook-shaped Type II sites.
  @codon_max 19

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
    n = length(pattern)

    # Phase 31 / L1.7 — methylase sites mark every codon position
    # by default (full coverage = full protection). A future
    # refinement can scale `methylated_positions` to the methylase
    # `kcat` (low-quality methylase methylates only some positions
    # → leaves a subset unprotected → restriction can still
    # cleave). Restriction sites carry an empty set.
    methylated_positions =
      case role do
        :methylation -> MapSet.new(0..(n - 1)//1)
        :restriction -> MapSet.new()
      end

    %__MODULE__{
      signature: signature,
      pattern: pattern,
      length_in_codons: n,
      palindrome?: palindrome?,
      type: type,
      role: role,
      methylated_positions: methylated_positions
    }
  end

  @doc """
  Override the default per-position methylation coverage. Returns
  a new `RecognitionSite` with the supplied set; the input must
  be a subset of `0..length_in_codons - 1`. Out-of-range positions
  are silently dropped.
  """
  @spec with_methylated_positions(t(), Enumerable.t()) :: t()
  def with_methylated_positions(%__MODULE__{length_in_codons: n} = site, positions) do
    set =
      positions
      |> Enum.to_list()
      |> Enum.filter(fn p -> is_integer(p) and p >= 0 and p < n end)
      |> MapSet.new()

    %{site | methylated_positions: set}
  end

  @doc """
  Phase 32 / L1.7 refinement — kcat-modulated partial methylation.

  The methylase's `:catalytic_site.kcat` (range `0..10` in Arkea's
  Phase-1 model) determines the *fraction* of the recognition site
  the enzyme actually marks per encounter:

      coverage_fraction = clamp(kcat / 10.0, 0.0, 1.0)
      n_methylated      = round(coverage_fraction × length)
      methylated        = first n_methylated positions (5' end)

  A perfectly-tuned methylase (kcat = 10) marks every position →
  full protection (matches the pre-Phase-32 default behaviour).
  A degraded methylase (low kcat) marks only the leading positions
  of the pattern → partial protection → restriction enzymes can
  still cleave at the trailing unmethylated positions, exactly the
  selection-visible failure mode that L1.7 said was missing.

  Why "first N positions" instead of a randomised subset: in vivo,
  methyltransferases scan the recognition site sequentially from a
  defined entry point (the M.HhaI processive scan, Klimasauskas
  1994). Phase-1 doesn't model strand directionality, so we use a
  deterministic 5'→3' fill — the modelling intent is "low kcat
  leaves *some* positions uncovered" rather than "the specific set
  of uncovered positions matters".

  Restriction sites pass through unchanged (their `kcat` field is
  irrelevant to per-position protection).
  """
  @spec scale_methylation_to_kcat(t(), number() | nil) :: t()
  def scale_methylation_to_kcat(%__MODULE__{role: :restriction} = site, _kcat), do: site

  def scale_methylation_to_kcat(%__MODULE__{role: :methylation, length_in_codons: n} = site, kcat) do
    fraction = methylation_coverage_fraction(kcat)
    n_methylated = round(fraction * n) |> max(0) |> min(n)
    positions = if n_methylated == 0, do: [], else: Enum.to_list(0..(n_methylated - 1)//1)
    with_methylated_positions(site, positions)
  end

  defp methylation_coverage_fraction(kcat) when is_number(kcat) do
    (kcat / 10.0) |> max(0.0) |> min(1.0)
  end

  defp methylation_coverage_fraction(_), do: 1.0

  @doc """
  True when `methylase_sites` collectively cover the entire
  pattern of `restriction_site` — i.e. every position of the
  restriction recognition site has a methyl mark from some
  matching methylase. Phase 31 / L1.7 sequence-level protection
  semantics.

  Matching uses the legacy `signature` for fast signature equality
  (the runtime calibration knob) AND additionally requires the
  methylase's `pattern` to equal the restriction's `pattern`
  (eliminates the false-positive case where two unrelated sites
  share a 4-codon prefix). When two sites with the same signature
  AND same pattern are paired, the union of their
  `methylated_positions` must contain `0..length-1` for the
  restriction site to count as protected.
  """
  @spec protected_by?(t(), [t()]) :: boolean()
  def protected_by?(%__MODULE__{role: :restriction} = restriction, methylase_sites)
      when is_list(methylase_sites) do
    full_range = MapSet.new(0..(restriction.length_in_codons - 1)//1)

    covering =
      methylase_sites
      |> Enum.filter(&pattern_matches?(restriction, &1))
      |> Enum.reduce(MapSet.new(), fn site, acc ->
        MapSet.union(acc, site.methylated_positions)
      end)

    MapSet.subset?(full_range, covering)
  end

  def protected_by?(_, _), do: false

  defp pattern_matches?(%__MODULE__{} = a, %__MODULE__{} = b) do
    a.signature == b.signature and a.pattern == b.pattern
  end

  @doc """
  True when the codon pattern is *any* kind of palindrome — exact
  (same as its plain reversal) **or** complement (same as its
  reverse-complement under `c → @codon_max - c`). Phase 32 / L1.7
  refinement: Type II R-M sites in vivo are reverse-complement
  palindromes (EcoRI: `5'-GAATTC-3' / 3'-CTTAAG-5'`), not plain
  palindromes — Phase 1 codons need the matching involution to
  classify them correctly.
  """
  @spec palindrome?([integer()]) :: boolean()
  def palindrome?(pattern) when is_list(pattern) do
    palindrome_kind(pattern) != :none
  end

  @doc """
  Classify the palindrome shape:

    * `:exact` — pattern equals its plain reversal.
    * `:complement` — pattern equals its reverse-complement
      `c → @codon_max - c`.
    * `:none` — neither.

  An *exact* palindrome is also trivially a complement palindrome
  only when every position is `@codon_max / 2 = 9.5` — i.e. never
  for integer codons; the two predicates are therefore disjoint
  for any non-empty pattern. Empty / single-codon patterns are
  classified `:exact` (the trivial palindrome).
  """
  @spec palindrome_kind([integer()]) :: :exact | :complement | :none
  def palindrome_kind(pattern) when is_list(pattern) do
    cond do
      exact_palindrome?(pattern) -> :exact
      complement_palindrome?(pattern) -> :complement
      true -> :none
    end
  end

  defp exact_palindrome?(pattern) do
    reversed = Enum.reverse(pattern)
    mismatches = pattern |> Enum.zip(reversed) |> Enum.count(fn {a, b} -> a != b end)
    div(mismatches, 2) <= @palindrome_tolerance
  end

  defp complement_palindrome?(pattern) do
    reverse_complement = pattern |> Enum.reverse() |> Enum.map(&(@codon_max - &1))

    mismatches =
      pattern |> Enum.zip(reverse_complement) |> Enum.count(fn {a, b} -> a != b end)

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
