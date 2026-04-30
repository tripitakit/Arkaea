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

  ## Phase 3 — generative system

  `compute_params/1` dispatches on `domain.type` and returns type-specific
  continuous parameters alongside the always-present `:raw_sum`. The raw_sum
  (weighted sum of parameter_codons) is in `0..~530` for codon values in
  `0..19` with the frozen log-normal weight table. All derived floats are
  normalised using a linear clamp with `@max_expected_raw_sum = 500.0`, which
  gives smooth, approximately-uniform distributions over the valid ranges
  without introducing non-linear distortion. The choice of linear clamp over
  `tanh` is deliberate: linear scaling preserves proportionality between
  genotype and phenotype, which is important for selection to be gradual and
  predictable (Block 2 principle: "semplificare senza banalizzare").

  `valid?/1` and `validate/1` verify both `:raw_sum` (universal) and every
  type-specific key for the domain's concrete type.
  """

  use TypedStruct

  alias Arkea.Genome.Codon
  alias Arkea.Genome.Domain.Type

  @type_tag_length 3
  @parameter_codons_min 10
  @parameter_codons_max 30

  # Normalisation constant: raw_sum range is 0..~530 (max codon 19, max weight
  # ~2.1, 30 codons). We use 500.0 as the practical ceiling — values that
  # slightly exceed it are clamped at 1.0 by min(..., 1.0). This keeps the
  # normalised value in 0.0..1.0 for any valid domain.
  @max_expected_raw_sum 500.0

  @reaction_classes [:hydrolysis, :oxidation, :reduction, :isomerization, :ligation, :lyase]
  @response_curves [:linear, :hill, :sigmoidal]
  @tag_classes [:pilus_receptor, :phage_receptor, :surface_antigen]
  @repair_classes [:mismatch, :proofreading, :error_prone]

  typedstruct enforce: true do
    field :type, Type.t()
    field :type_tag, [Codon.t()]
    field :parameter_codons, [Codon.t()]
    field :params, %{atom() => term()}
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

  Always returns `:raw_sum` (the weighted sum of all parameter_codons).
  Additionally returns type-specific keys determined by `domain.type`.

  Pure and deterministic.

  ## Type-specific keys

  | Type | Keys |
  |---|---|
  | `:substrate_binding` | `:target_metabolite_id`, `:km`, `:specificity_breadth` |
  | `:catalytic_site` | `:reaction_class`, `:kcat`, `:cofactor_required` |
  | `:transmembrane_anchor` | `:hydrophobicity`, `:n_passes` |
  | `:channel_pore` | `:selectivity`, `:gating_threshold` |
  | `:energy_coupling` | `:atp_cost`, `:pmf_coupling` |
  | `:dna_binding` | `:promoter_specificity`, `:binding_affinity` |
  | `:regulator_output` | `:mode`, `:cooperativity` |
  | `:ligand_sensor` | `:sensed_metabolite_id`, `:threshold`, `:response_curve` |
  | `:structural_fold` | `:stability`, `:multimerization_n` |
  | `:surface_tag` | `:tag_class` |
  | `:repair_fidelity` | `:repair_class`, `:efficiency` |
  """
  @spec compute_params(t()) :: %{atom() => term()}
  def compute_params(%__MODULE__{type: type, parameter_codons: codons}) do
    raw_sum = Codon.weighted_sum(codons)
    norm = min(raw_sum / @max_expected_raw_sum, 1.0)
    base = %{raw_sum: raw_sum}
    Map.merge(base, type_params(type, codons, raw_sum, norm))
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
      Map.has_key?(params, :raw_sum) and
      type_params_valid?(type, params)
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

      not type_params_valid?(domain.type, domain.params) ->
        {:error, :params_missing_type_specific_keys}

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

  # ---------------------------------------------------------------------------
  # Private — type-specific parameter dispatch

  # Splits codons into thirds for sub-range encoding.
  defp split_thirds(codons) do
    n = length(codons)
    third = div(n, 3)
    first = Enum.take(codons, third)
    last = Enum.drop(codons, n - third)
    mid = codons |> Enum.drop(third) |> Enum.take(n - 2 * third)
    {first, mid, last}
  end

  # Splits codons into halves for sub-range encoding.
  defp split_halves(codons) do
    half = div(length(codons), 2)
    {Enum.take(codons, half), Enum.drop(codons, half)}
  end

  defp sum_codons(codons), do: Enum.sum(codons)

  defp norm_of(codons) do
    s = Codon.weighted_sum(codons)
    min(s / @max_expected_raw_sum, 1.0)
  end

  # :substrate_binding
  # - target_metabolite_id: rem(first_codon, 13) → 0..12
  # - km: norm * 99.99 + 0.01 → 0.01..100.0 (affinity constant, mM scale)
  # - specificity_breadth: third-quartile norm → 0.0..1.0
  defp type_params(:substrate_binding, codons, _raw_sum, norm) do
    {first_t, _mid_t, last_t} = split_thirds(codons)
    first_codon = List.first(codons, 0)
    third_norm = norm_of(last_t ++ first_t)
    km = norm * 99.99 + 0.01

    %{
      target_metabolite_id: rem(first_codon, 13),
      km: km,
      specificity_breadth: third_norm
    }
  end

  # :catalytic_site
  # - reaction_class: rem(sum_first_3, 6) → index into 6-element list
  # - kcat: norm * 10.0 → 0.0..10.0 (catalytic turnover, s⁻¹ order of magnitude)
  # - cofactor_required: rem(last_codon, 2) == 0
  defp type_params(:catalytic_site, codons, _raw_sum, norm) do
    first_3 = Enum.take(codons, 3)
    last_codon = List.last(codons, 0)
    reaction_class = Enum.at(@reaction_classes, rem(sum_codons(first_3), 6))

    %{
      reaction_class: reaction_class,
      kcat: norm * 10.0,
      cofactor_required: rem(last_codon, 2) == 0
    }
  end

  # :transmembrane_anchor
  # - hydrophobicity: norm → 0.0..1.0
  # - n_passes: max(1, rem(sum_last_3, 6) + 1) → 1..6
  defp type_params(:transmembrane_anchor, codons, _raw_sum, norm) do
    last_3 = Enum.take(codons, -3)
    n_passes = max(1, rem(sum_codons(last_3), 6) + 1)
    %{hydrophobicity: norm, n_passes: n_passes}
  end

  # :channel_pore
  # - selectivity: norm of first third → 0.0..1.0
  # - gating_threshold: norm of second third → 0.0..1.0
  defp type_params(:channel_pore, codons, _raw_sum, _norm) do
    {first_t, mid_t, _last_t} = split_thirds(codons)
    %{selectivity: norm_of(first_t), gating_threshold: norm_of(mid_t)}
  end

  # :energy_coupling
  # - atp_cost: norm * 5.0 → 0.0..5.0
  # - pmf_coupling: norm of last third → 0.0..1.0
  defp type_params(:energy_coupling, codons, _raw_sum, norm) do
    {_first_t, _mid_t, last_t} = split_thirds(codons)
    %{atp_cost: norm * 5.0, pmf_coupling: norm_of(last_t)}
  end

  # :dna_binding
  # - promoter_specificity: norm of first half → 0.0..1.0
  # - binding_affinity: norm of second half → 0.0..1.0
  defp type_params(:dna_binding, codons, _raw_sum, _norm) do
    {first_h, second_h} = split_halves(codons)
    %{promoter_specificity: norm_of(first_h), binding_affinity: norm_of(second_h)}
  end

  # :regulator_output
  # - mode: rem(first_codon, 2) == 0 → :activator, else :repressor
  # - cooperativity: 1.0 + norm * 3.0 → 1.0..4.0
  defp type_params(:regulator_output, codons, _raw_sum, norm) do
    first_codon = List.first(codons, 0)
    mode = if rem(first_codon, 2) == 0, do: :activator, else: :repressor
    %{mode: mode, cooperativity: 1.0 + norm * 3.0}
  end

  # :ligand_sensor
  # - sensed_metabolite_id: rem(first_codon, 13) → 0..12
  # - threshold: norm of middle third → 0.0..1.0
  # - response_curve: rem(sum_last_3, 3) → index into 3-element list
  defp type_params(:ligand_sensor, codons, _raw_sum, _norm) do
    first_codon = List.first(codons, 0)
    {_first_t, mid_t, last_t} = split_thirds(codons)
    response_curve = Enum.at(@response_curves, rem(sum_codons(last_t), 3))

    %{
      sensed_metabolite_id: rem(first_codon, 13),
      threshold: norm_of(mid_t),
      response_curve: response_curve
    }
  end

  # :structural_fold
  # - stability: norm of first half → 0.0..1.0
  # - multimerization_n: max(1, rem(sum_last_3, 8) + 1) → 1..8
  defp type_params(:structural_fold, codons, _raw_sum, _norm) do
    {first_h, _second_h} = split_halves(codons)
    last_3 = Enum.take(codons, -3)
    multimerization_n = max(1, rem(sum_codons(last_3), 8) + 1)
    %{stability: norm_of(first_h), multimerization_n: multimerization_n}
  end

  # :surface_tag
  # - tag_class: rem(first_codon, 3) → index into 3-element list
  defp type_params(:surface_tag, codons, _raw_sum, _norm) do
    first_codon = List.first(codons, 0)
    tag_class = Enum.at(@tag_classes, rem(first_codon, 3))
    %{tag_class: tag_class}
  end

  # :repair_fidelity
  # - repair_class: rem(first_codon, 3) → index into 3-element list
  # - efficiency: norm → 0.0..1.0
  defp type_params(:repair_fidelity, codons, _raw_sum, norm) do
    first_codon = List.first(codons, 0)
    repair_class = Enum.at(@repair_classes, rem(first_codon, 3))
    %{repair_class: repair_class, efficiency: norm}
  end

  # ---------------------------------------------------------------------------
  # Private — type-specific params validation

  defp type_params_valid?(:substrate_binding, params) do
    Map.has_key?(params, :target_metabolite_id) and
      Map.has_key?(params, :km) and
      Map.has_key?(params, :specificity_breadth)
  end

  defp type_params_valid?(:catalytic_site, params) do
    Map.has_key?(params, :reaction_class) and
      Map.has_key?(params, :kcat) and
      Map.has_key?(params, :cofactor_required)
  end

  defp type_params_valid?(:transmembrane_anchor, params) do
    Map.has_key?(params, :hydrophobicity) and Map.has_key?(params, :n_passes)
  end

  defp type_params_valid?(:channel_pore, params) do
    Map.has_key?(params, :selectivity) and Map.has_key?(params, :gating_threshold)
  end

  defp type_params_valid?(:energy_coupling, params) do
    Map.has_key?(params, :atp_cost) and Map.has_key?(params, :pmf_coupling)
  end

  defp type_params_valid?(:dna_binding, params) do
    Map.has_key?(params, :promoter_specificity) and Map.has_key?(params, :binding_affinity)
  end

  defp type_params_valid?(:regulator_output, params) do
    Map.has_key?(params, :mode) and Map.has_key?(params, :cooperativity)
  end

  defp type_params_valid?(:ligand_sensor, params) do
    Map.has_key?(params, :sensed_metabolite_id) and
      Map.has_key?(params, :threshold) and
      Map.has_key?(params, :response_curve)
  end

  defp type_params_valid?(:structural_fold, params) do
    Map.has_key?(params, :stability) and Map.has_key?(params, :multimerization_n)
  end

  defp type_params_valid?(:surface_tag, params) do
    Map.has_key?(params, :tag_class)
  end

  defp type_params_valid?(:repair_fidelity, params) do
    Map.has_key?(params, :repair_class) and Map.has_key?(params, :efficiency)
  end

  defp type_params_valid?(_, _), do: false
end
