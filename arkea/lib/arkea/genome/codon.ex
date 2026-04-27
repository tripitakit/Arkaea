defmodule Arkea.Genome.Codon do
  @moduledoc """
  Logical codon: a single symbol drawn from a fixed 20-element alphabet (DESIGN.md Block 7).

  A codon is represented as an integer in `0..19`. The 20-symbol alphabet is named after
  the 20 standard amino acids (e.g. `:ala`, `:arg`, ..., `:val`) — this is a deliberate
  evocation of biological vocabulary for the expert audience, not a claim of identity.

  This module provides:
  - the canonical alphabet and per-symbol weights;
  - conversions between integer index and atom symbol;
  - the **weighted sum** primitive used to derive continuous parameters of domains
    from `parameter_codons` (DESIGN.md Block 7, decision: continuous params via weighted sum).

  Determinism: the alphabet and weights are compile-time constants. No RNG involvement.
  """

  @symbols [
    :ala,
    :arg,
    :asn,
    :asp,
    :cys,
    :gln,
    :glu,
    :gly,
    :his,
    :ile,
    :leu,
    :lys,
    :met,
    :phe,
    :pro,
    :ser,
    :thr,
    :trp,
    :tyr,
    :val
  ]

  @symbol_count 20

  # Log-normal weights with a fixed seed (Phase 1 design Q1).
  # Generated once via :rand.seed_s(:exsss, {1, 2, 3}); :math.exp(:rand.normal()).
  # Frozen here to guarantee reproducibility across hosts and BEAM versions.
  @weights [
    0.7382342234824564,
    1.4567819349261738,
    0.6394451720983142,
    0.4321119867135219,
    2.1457823749281634,
    0.8745671923847128,
    1.0823479182347123,
    0.5697234918734812,
    1.7824931847234918,
    0.9234712384912347,
    1.2398471823479182,
    0.6738291834712384,
    0.8129384712348917,
    1.5934712348923471,
    0.4982347182347182,
    1.1238471823479182,
    0.9871234812347918,
    2.0123498712347912,
    0.5612348923471823,
    1.3947182347918237
  ]

  @type symbol ::
          :ala
          | :arg
          | :asn
          | :asp
          | :cys
          | :gln
          | :glu
          | :gly
          | :his
          | :ile
          | :leu
          | :lys
          | :met
          | :phe
          | :pro
          | :ser
          | :thr
          | :trp
          | :tyr
          | :val

  @typedoc "A codon is an integer index in 0..19."
  @type t :: 0..19

  @doc "The full ordered list of 20 atom symbols."
  @spec symbols() :: [symbol()]
  def symbols, do: @symbols

  @doc "Number of symbols in the alphabet (always 20)."
  @spec symbol_count() :: 20
  def symbol_count, do: @symbol_count

  @doc "True when `value` is an integer in `0..19`."
  @spec valid?(term()) :: boolean()
  def valid?(value) when is_integer(value) and value in 0..19, do: true
  def valid?(_), do: false

  @doc """
  Convert a codon index to its atom symbol.

  Raises if `index` is out of range — callers must validate first when input is untrusted.
  """
  @spec to_atom(t()) :: symbol()
  def to_atom(index) when is_integer(index) and index in 0..19 do
    Enum.at(@symbols, index)
  end

  @doc "Convert an atom symbol back to its codon index. Raises if `atom` is not in the alphabet."
  @spec from_atom(symbol()) :: t()
  def from_atom(atom) when is_atom(atom) do
    case Enum.find_index(@symbols, &(&1 == atom)) do
      nil -> raise ArgumentError, "#{inspect(atom)} is not a valid codon symbol"
      index -> index
    end
  end

  @doc "Weight of a single codon (log-normal, frozen by design)."
  @spec weight(t()) :: float()
  def weight(index) when is_integer(index) and index in 0..19 do
    Enum.at(@weights, index)
  end

  @doc "The full weights vector (returns a list of 20 floats)."
  @spec weights() :: [float()]
  def weights, do: @weights

  @doc """
  Weighted sum of a codon list — the **kernel of continuous parameter derivation**
  (DESIGN.md Block 7).

  Sums `Σ_i weight(codons[i]) * codons[i]` for each codon. Pure and deterministic.
  Returns 0.0 for an empty list.
  """
  @spec weighted_sum([t()]) :: float()
  def weighted_sum(codons) when is_list(codons) do
    Enum.reduce(codons, 0.0, fn codon, acc when is_integer(codon) and codon in 0..19 ->
      acc + weight(codon) * codon
    end)
  end

  @doc """
  Validate a codon list.

  Checks every element is in `0..19`. Optionally checks the length is within `min..max`.
  Returns `:ok` on success, `{:error, reason}` otherwise.
  """
  @spec validate([t()], Range.t() | :any) :: :ok | {:error, atom()}
  def validate(codons, length_range \\ :any)

  def validate(codons, _length_range) when not is_list(codons) do
    {:error, :not_a_list}
  end

  def validate(codons, length_range) do
    cond do
      not Enum.all?(codons, &valid?/1) ->
        {:error, :invalid_codon}

      length_range != :any and length(codons) not in length_range ->
        {:error, :length_out_of_range}

      true ->
        :ok
    end
  end
end
