defmodule Arkea.Genome.Domain do
  @moduledoc """
  A functional domain is the unit of biological function within a gene
  (DESIGN.md Block 7).

  Composition:

  - `type_tag` — 3 codons that **categorically** select one of the 11 domain
    types (see `Arkea.Genome.Domain.Type`). A point mutation in the type tag
    can flip the domain to a different type — the rare "categorical jump"
    that drives discontinuous innovation.
  - `parameter_codons` — 10..30 codons that **continuously** parameterise the
    domain. Their weighted sum (`Arkea.Genome.Codon.weighted_sum/1`) feeds
    `params`, the map of derived continuous values.

  In Phase 1, `params` exposes a single key `:raw_sum`. Phase 3 (generative
  system) refines this with type-specific keys (Km, kcat, specificity, etc.).
  """

  use TypedStruct

  alias Arkea.Genome.Codon
  alias Arkea.Genome.Domain.Type

  @type_tag_length 3
  @parameter_codons_min 10
  @parameter_codons_max 30

  typedstruct enforce: true do
    field :type, Type.t()
    field :type_tag, [Codon.t()]
    field :parameter_codons, [Codon.t()]
    field :params, %{atom() => float()}
  end

  @doc "Length of the type tag (always 3)."
  @spec type_tag_length() :: 3
  def type_tag_length, do: @type_tag_length

  @doc "Inclusive parameter-codons length range."
  @spec parameter_codons_range() :: Range.t()
  def parameter_codons_range, do: @parameter_codons_min..@parameter_codons_max

  @doc """
  Build a domain from raw codon blocks.

  Validates that `type_tag` is exactly 3 codons and `parameter_codons` is
  in `10..30`. Computes `:type` via `Type.from_type_tag/1` and `:params`
  via `compute_params/1`. Pure.

  Raises `ArgumentError` on invalid input.
  """
  @spec new([Codon.t()], [Codon.t()]) :: t()
  def new(type_tag, parameter_codons)
      when is_list(type_tag) and is_list(parameter_codons) do
    with :ok <- Codon.validate(type_tag, @type_tag_length..@type_tag_length),
         :ok <- Codon.validate(parameter_codons, parameter_codons_range()) do
      type = Type.from_type_tag(type_tag)

      raw = %__MODULE__{
        type: type,
        type_tag: type_tag,
        parameter_codons: parameter_codons,
        params: %{}
      }

      %{raw | params: compute_params(raw)}
    else
      {:error, reason} ->
        raise ArgumentError, "invalid domain input: #{reason}"
    end
  end

  @doc """
  Compute the continuous parameters of a domain from its `parameter_codons`.

  Phase 1: returns `%{raw_sum: float}`. Phase 3 will dispatch on `domain.type`
  and extract type-specific keys (e.g. `:km`, `:kcat`, `:specificity_breadth`).

  Pure and deterministic.
  """
  @spec compute_params(t()) :: %{atom() => float()}
  def compute_params(%__MODULE__{parameter_codons: codons}) do
    %{raw_sum: Codon.weighted_sum(codons)}
  end

  @doc "True when the domain satisfies its structural invariants."
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{
        type: type,
        type_tag: type_tag,
        parameter_codons: parameter_codons,
        params: params
      }) do
    Type.valid?(type) and
      length(type_tag) == @type_tag_length and
      Enum.all?(type_tag, &Codon.valid?/1) and
      length(parameter_codons) in parameter_codons_range() and
      Enum.all?(parameter_codons, &Codon.valid?/1) and
      is_map(params) and
      Map.has_key?(params, :raw_sum)
  end

  def valid?(_), do: false

  @doc "Validation with reason. Returns `:ok` or `{:error, reason}`."
  @spec validate(t()) :: :ok | {:error, atom()}
  def validate(%__MODULE__{} = domain) do
    cond do
      not Type.valid?(domain.type) ->
        {:error, :invalid_type}

      length(domain.type_tag) != @type_tag_length ->
        {:error, :type_tag_wrong_length}

      not Enum.all?(domain.type_tag, &Codon.valid?/1) ->
        {:error, :type_tag_invalid_codon}

      length(domain.parameter_codons) not in parameter_codons_range() ->
        {:error, :parameter_codons_out_of_range}

      not Enum.all?(domain.parameter_codons, &Codon.valid?/1) ->
        {:error, :parameter_codons_invalid_codon}

      not Map.has_key?(domain.params, :raw_sum) ->
        {:error, :params_missing_raw_sum}

      true ->
        :ok
    end
  end

  def validate(_), do: {:error, :not_a_domain}

  @doc """
  Total codon length of the domain (type_tag + parameter_codons).

  Useful for `Gene.parse_codons/1` which advances by `domain_codon_length(d)`
  on each domain it parses.
  """
  @spec codon_length(t()) :: pos_integer()
  def codon_length(%__MODULE__{type_tag: tag, parameter_codons: pc}) do
    length(tag) + length(pc)
  end
end
