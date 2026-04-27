defmodule Arkea.Genome.Gene do
  @moduledoc """
  A gene is an ordered sequence of logical codons (50–200 symbols) organised
  into a `promoter_block` (optional), a `regulatory_block` (optional), and
  one or more `domains` (DESIGN.md Block 7).

  ## Source of truth

  The `codons` field is the canonical sequence; `promoter_block`,
  `regulatory_block`, and `domains` are **derived views** computed by
  `parse_codons/1`. After a mutation that touches `codons`, call
  `reparse/1` to refresh the derived views.

  ## Phase 1 simplifications

  Block 7 specifies that parameter_codons may vary in length (10..30) and
  that promoter / regulatory blocks may precede the first domain. To keep
  Phase 1 implementable without committing to a full grammar, the parser
  assumes:

  - **No promoter or regulatory block** (both `nil`).
  - **Fixed `@phase1_param_codons_length = 20`** codons per domain →
    each domain occupies exactly 23 codons (3 type_tag + 20 parameters).
  - Hence the gene length must be a positive multiple of 23. The smallest
    accepted gene is one domain (23 codons); the largest accepted is nine
    domains (207 codons). Block 7's nominal envelope of 50–200 codons is
    *contained* in this range — production seeds will respect the design
    envelope explicitly, while the parser accepts the wider range so
    minimal one-domain genes can be tested in isolation.

  Phase 3 (generative system) will introduce variable parameter_codons
  length encoding and the optional regulatory blocks. The struct already
  carries the optional fields so that Phase 3 is a non-breaking extension.

  ## Phase 1 round-trip caveat

  `from_domains/1` accepts any valid `Domain.t()` (parameter_codons in
  `10..30`), but `from_codons/1` only parses domains with exactly 20
  parameter codons (the fixed Phase 1 grammar). Therefore the
  `from_domains → codons → from_codons` round-trip is **guaranteed only
  for domains built with 20 parameter_codons**. Test generators use
  `Generators.domain_phase1/0` (fixed length 20) for this round-trip; a
  free-form `Domain.new/2` with 15 parameter_codons can produce a gene
  via `from_domains/1` but its codon sequence won't realign through
  `from_codons/1`.
  """

  use TypedStruct

  alias Arkea.Genome.Codon
  alias Arkea.Genome.Domain

  @phase1_param_codons_length 20
  @phase1_domain_codon_length 3 + @phase1_param_codons_length

  # Min/max chosen so the gene always contains at least 1 domain and
  # remains within Block 7's 50..200 codon envelope. With per-domain length
  # fixed at 23 in Phase 1, the smallest multiple of 23 ≥ 50 is 69 (3 domains
  # short of that), and the largest ≤ 200 is 184. We allow 23..207 here so
  # tiny single-domain genes are accepted in tests; production seeds will
  # respect the design envelope.
  @min_codons 23
  @max_codons 207

  typedstruct enforce: true do
    field :id, binary()
    field :codons, [Codon.t()]
    field :promoter_block, [Codon.t()] | nil, default: nil
    field :regulatory_block, [Codon.t()] | nil, default: nil
    field :domains, [Domain.t()]
  end

  @doc "Phase 1 fixed length of `parameter_codons` per domain (= 20)."
  @spec phase1_param_codons_length() :: 20
  def phase1_param_codons_length, do: @phase1_param_codons_length

  @doc "Phase 1 total codon length per domain (= 23)."
  @spec phase1_domain_codon_length() :: 23
  def phase1_domain_codon_length, do: @phase1_domain_codon_length

  @doc "Inclusive total-codon range accepted by `from_codons/1`."
  @spec codons_range() :: Range.t()
  def codons_range, do: @min_codons..@max_codons

  @doc """
  Build a gene from a list of domains.

  Concatenates each domain's `type_tag ++ parameter_codons` to produce the
  canonical `codons` sequence. Generates a UUID v4. Pure.

  Raises if `domains` is empty or any domain is invalid.
  """
  @spec from_domains([Domain.t()]) :: t()
  def from_domains([]), do: raise(ArgumentError, "gene must have at least one domain")

  def from_domains(domains) when is_list(domains) do
    unless Enum.all?(domains, &Domain.valid?/1) do
      raise ArgumentError, "all domains must be valid"
    end

    codons =
      Enum.flat_map(domains, fn %Domain{type_tag: tag, parameter_codons: pc} ->
        tag ++ pc
      end)

    %__MODULE__{
      id: Arkea.UUID.v4(),
      codons: codons,
      promoter_block: nil,
      regulatory_block: nil,
      domains: domains
    }
  end

  @doc """
  Build a gene from a raw codon list (Phase 1 grammar).

  Splits the sequence into successive domains of fixed length 23
  (`3 + 20`). Returns `{:ok, gene}` on success, `{:error, reason}` otherwise.

  In Phase 3 this parser will be generalised to handle promoter / regulatory
  blocks and variable-length parameter codons.
  """
  @spec from_codons([Codon.t()]) :: {:ok, t()} | {:error, atom()}
  def from_codons(codons) when is_list(codons) do
    with :ok <- Codon.validate(codons, codons_range()),
         :ok <- check_phase1_alignment(codons),
         {:ok, domains} <- parse_domains_phase1(codons) do
      {:ok,
       %__MODULE__{
         id: Arkea.UUID.v4(),
         codons: codons,
         promoter_block: nil,
         regulatory_block: nil,
         domains: domains
       }}
    end
  end

  def from_codons(_), do: {:error, :not_a_list}

  @doc """
  Re-parse `codons` to refresh `domains` (call after a mutation
  that touched `codons`). Pure.
  """
  @spec reparse(t()) :: {:ok, t()} | {:error, atom()}
  def reparse(%__MODULE__{codons: codons} = gene) do
    case parse_domains_phase1(codons) do
      {:ok, domains} -> {:ok, %{gene | domains: domains}}
      {:error, _} = err -> err
    end
  end

  @doc "Number of codons in the gene (length of `codons`)."
  @spec codon_count(t()) :: non_neg_integer()
  def codon_count(%__MODULE__{codons: codons}), do: length(codons)

  @doc "Number of parsed domains."
  @spec domain_count(t()) :: non_neg_integer()
  def domain_count(%__MODULE__{domains: domains}), do: length(domains)

  @doc "True when the gene satisfies its structural invariants."
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{
        id: id,
        codons: codons,
        promoter_block: promoter,
        regulatory_block: regulatory,
        domains: domains
      })
      when is_binary(id) do
    length(codons) in codons_range() and
      Enum.all?(codons, &Codon.valid?/1) and
      domains != [] and
      Enum.all?(domains, &Domain.valid?/1) and
      validate_optional_block(promoter) and
      validate_optional_block(regulatory)
  end

  def valid?(_), do: false

  @doc "Validation with reason."
  @spec validate(t()) :: :ok | {:error, atom()}
  def validate(%__MODULE__{} = gene) do
    cond do
      not is_binary(gene.id) -> {:error, :invalid_id}
      length(gene.codons) not in codons_range() -> {:error, :codon_count_out_of_range}
      not Enum.all?(gene.codons, &Codon.valid?/1) -> {:error, :invalid_codon}
      gene.domains == [] -> {:error, :no_domains}
      not Enum.all?(gene.domains, &Domain.valid?/1) -> {:error, :invalid_domain}
      not validate_optional_block(gene.promoter_block) -> {:error, :invalid_promoter_block}
      not validate_optional_block(gene.regulatory_block) -> {:error, :invalid_regulatory_block}
      true -> :ok
    end
  end

  def validate(_), do: {:error, :not_a_gene}

  # ----------------------------------------------------------------------
  # Private helpers

  defp check_phase1_alignment(codons) do
    if rem(length(codons), @phase1_domain_codon_length) == 0 do
      :ok
    else
      {:error, :codon_count_not_phase1_aligned}
    end
  end

  defp parse_domains_phase1(codons) do
    codons
    |> Enum.chunk_every(@phase1_domain_codon_length)
    |> Enum.reduce_while({:ok, []}, fn chunk, {:ok, acc} ->
      {tag, params} = Enum.split(chunk, 3)

      try do
        domain = Domain.new(tag, params)
        {:cont, {:ok, [domain | acc]}}
      rescue
        ArgumentError -> {:halt, {:error, :invalid_domain_chunk}}
      end
    end)
    |> case do
      {:ok, domains} -> {:ok, Enum.reverse(domains)}
      {:error, _} = err -> err
    end
  end

  defp validate_optional_block(nil), do: true

  defp validate_optional_block(codons) when is_list(codons) do
    Enum.all?(codons, &Codon.valid?/1)
  end

  defp validate_optional_block(_), do: false
end
