defmodule Arkea.Sim.Signaling do
  @moduledoc """
  Pure quorum sensing logic for Phase 7 (DESIGN.md Block 9).

  Signal identity: a 4-codon signature encoded as "c0,c1,c2,c3" (binary key).
  The four integers are in 0..19, derived from the first four parameter_codons
  of a `:catalytic_site` or `:ligand_sensor` domain.

  Signal matching: Gaussian affinity exp(-dist²/(2σ²)) with σ=4.0 in [0..19]^4.
  Two identical keys yield affinity 1.0; maximally different keys (all 0 vs all 19)
  yield affinity ≈ 0.028, well below any practical activation threshold.

  ## Design invariants

  - All functions are pure: no I/O, no side effects, no process interaction.
  - `binding_affinity/2` is always in [0.0, 1.0] for any valid key pair.
  - `produce_signals/3` never decreases existing pool concentrations.
  - `qs_sigma_boost/2` is clamped to 0.0..1.0.
  """

  alias Arkea.Sim.Phenotype

  @sigma 4.0

  @doc """
  Parse a signal key back to a list of 4 integers.

  ## Examples

      iex> Arkea.Sim.Signaling.parse_key("5,5,5,5")
      [5, 5, 5, 5]
  """
  @spec parse_key(binary()) :: [integer()]
  def parse_key(key), do: key |> String.split(",") |> Enum.map(&String.to_integer/1)

  @doc """
  Gaussian binding affinity between two signal keys.

  Returns a float in [0.0, 1.0]. Maximum (1.0) when both keys are identical.
  Falls off with the squared Euclidean distance in codon space, with σ=4.0.

  ## Examples

      iex> Arkea.Sim.Signaling.binding_affinity("5,5,5,5", "5,5,5,5")
      1.0
  """
  @spec binding_affinity(binary(), binary()) :: float()
  def binding_affinity(signal_key, receptor_key) do
    sig = parse_key(signal_key)
    rec = parse_key(receptor_key)
    dist_sq = Enum.zip(sig, rec) |> Enum.sum_by(fn {s, r} -> (s - r) * (s - r) end)
    :math.exp(-dist_sq / (2.0 * @sigma * @sigma))
  end

  @doc """
  Compute the QS sigma boost for one lineage from its receptors and the current signal pool.

  For each `{rec_key, threshold}` in `phenotype.qs_receives`:
    For each `{sig_key, conc}` in `signal_pool`:
      `aff = binding_affinity(sig_key, rec_key)`
      If `conc * aff > threshold`: `boost += aff * 0.5`

  Returns total boost clamped to `0.0..1.0`.

  Pure. Zero when `qs_receives` is empty or `signal_pool` is empty.
  """
  @spec qs_sigma_boost(Phenotype.t(), %{binary() => float()}) :: float()
  def qs_sigma_boost(%Phenotype{qs_receives: []}, _signal_pool), do: 0.0
  def qs_sigma_boost(_phenotype, signal_pool) when map_size(signal_pool) == 0, do: 0.0

  def qs_sigma_boost(%Phenotype{qs_receives: receivers}, signal_pool) do
    boost = Enum.reduce(receivers, 0.0, &accumulate_receptor_boost(&1, &2, signal_pool))
    min(boost, 1.0)
  end

  # ---------------------------------------------------------------------------
  # Private helpers

  # Accumulate sigma boost from one receptor across all signals in the pool.
  defp accumulate_receptor_boost({rec_key, threshold}, acc_boost, signal_pool) do
    Enum.reduce(signal_pool, acc_boost, fn {sig_key, conc}, inner ->
      receptor_signal_contribution(sig_key, conc, rec_key, threshold, inner)
    end)
  end

  # Add aff * 0.5 to the running boost when one signal activates a receptor.
  defp receptor_signal_contribution(sig_key, conc, rec_key, threshold, acc) do
    aff = binding_affinity(sig_key, rec_key)
    if conc * aff > threshold, do: acc + aff * 0.5, else: acc
  end

  @doc """
  Produce signals: given a lineage's phenotype and abundance, return an updated
  signal pool with the lineage's signal contributions added.

  For each `{sig_key, rate}` in `phenotype.qs_produces`:
    `amount = rate * abundance / 100.0`
    `signal_pool[sig_key] += amount`

  Pure. Returns the pool unchanged when `qs_produces` is empty.
  """
  @spec produce_signals(Phenotype.t(), non_neg_integer(), %{binary() => float()}) ::
          %{binary() => float()}
  def produce_signals(%Phenotype{qs_produces: []}, _abundance, signal_pool), do: signal_pool

  def produce_signals(%Phenotype{qs_produces: producers}, abundance, signal_pool) do
    Enum.reduce(producers, signal_pool, fn {sig_key, rate}, pool ->
      amount = rate * abundance / 100.0
      Map.update(pool, sig_key, amount, fn existing -> existing + amount end)
    end)
  end
end
