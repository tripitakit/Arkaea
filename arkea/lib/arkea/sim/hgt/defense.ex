defmodule Arkea.Sim.HGT.Defense do
  @moduledoc """
  Restriction-Modification (R-M) defence as a uniform gating step on every
  HGT channel (Phase 12 — DESIGN.md Block 8).

  This module is **strictly pure**: no I/O, no OTP calls. All stochasticity
  is driven by the `:rand` state passed as an argument.

  ## Biological model (Arber-Dussoix host-modification, simplified)

  An R-M system has two activities:

  - **Restriction enzyme** — recognises a short DNA sequence (the
    *recognition site*) and cleaves any DNA that carries it.
  - **Methylase** — recognises the same sequence and adds a methyl mark
    that prevents the restriction enzyme from cleaving.

  In a host that owns both, its own DNA is methylated at every recognition
  site and is therefore protected; incoming DNA without the matching
  methylation is cleaved on entry, blocking establishment of foreign genetic
  material (Bickle & Krüger 1993, Arber 2000).

  Within Arkea both activities are *generative* phenotypic traits derived
  from gene composition (see `Arkea.Sim.Phenotype.rm_profiles/1`):

  - A gene with co-occurring `:dna_binding` + `:catalytic_site(:hydrolysis)`
    encodes a restriction enzyme; its `signal_key` is the recognition site.
  - A gene with co-occurring `:dna_binding` + `:catalytic_site(:isomerization)`
    encodes a methylase; its `signal_key` is the protected site.

  ## R-M gating model used here

  For a payload travelling from a *donor* lineage to a *recipient* lineage:

      restriction_sites      = recipient.restriction_profile
      donor_methylation_sites = donor.methylation_profile
                              ∪ payload-carried virion methylation
      vulnerable_sites = restriction_sites \\ donor_methylation_sites

      # Per vulnerable site, attempt to cleave with probability @cleave_p.
      p_digestion = 1 - (1 - @cleave_p) ^ length(vulnerable_sites)

  Outcome:

  - `{:passed, rng'}` — the payload survives the R-M gate.
  - `{:digested, vulnerable_sites, rng'}` — the payload is cleaved; the
    caller drops it.

  ## Why a probability (not a deterministic cut)

  Restriction enzymes are not perfectly efficient — *escape* is a baseline
  feature in vivo (Tock & Dryden 2005). `@cleave_p = 0.7` reproduces that
  imperfect immunity: a single matching site usually digests, but a
  fraction of payloads slip through, which is the substrate selection acts
  on when an HGT-acquired methylase emerges by mutation.
  """

  alias Arkea.Sim.HGT.Virion

  # Phase 20 calibration — per-site cleavage probability raised to
  # 0.95, in line with the in vivo efficiency of restriction enzymes
  # (Type II 95–99 % per recognition site, Tock & Dryden 2005).
  # The Phase 12 baseline of 0.70 modelled escape rates ~30 %/site,
  # which is permissive of unrealistic phage / plasmid breakthrough.
  # With 0.95 a payload that crosses 1 vulnerable site has a 5 %
  # escape rate; multi-site payloads compound to <1 %.
  @cleave_p 0.95

  @typedoc "Outcome of an R-M check on a single payload."
  @type outcome ::
          {:passed, :rand.state()}
          | {:digested, [binary()], :rand.state()}

  @doc """
  Run the R-M check for an HGT payload.

  ## Arguments

  - `restriction_sites` — list of recipient restriction `signal_key`s
    (typically `recipient_phenotype.restriction_profile`).
  - `donor_methylation_sites` — list of methylation `signal_key`s carried
    over with the payload. For conjugation/transformation this is the
    donor cell's `methylation_profile`. For phage infection it includes
    the virion's own `methylation_profile` (host-modification of the
    cell where the lytic burst happened).
  - `rng` — `:rand` state.

  Returns `outcome()` (see typespec).
  """
  @spec restriction_check([binary()], [binary()], :rand.state()) :: outcome()
  def restriction_check(restriction_sites, donor_methylation_sites, rng)
      when is_list(restriction_sites) and is_list(donor_methylation_sites) do
    methyl_set = MapSet.new(donor_methylation_sites)

    vulnerable =
      restriction_sites
      |> Enum.uniq()
      |> Enum.reject(fn site -> MapSet.member?(methyl_set, site) end)

    case vulnerable do
      [] ->
        {:passed, rng}

      sites ->
        roll_per_site(sites, rng)
    end
  end

  @doc """
  Convenience: run the R-M check for a virion infection.

  Reads `restriction_profile` from the recipient phenotype and merges the
  donor lineage's `methylation_profile` with the virion's own
  `methylation_profile` (host-modification carried over from the burst
  cell).
  """
  @spec restriction_check_virion(
          recipient_restriction_profile :: [binary()],
          Virion.t(),
          :rand.state()
        ) :: outcome()
  def restriction_check_virion(restriction_sites, %Virion{} = virion, rng) do
    restriction_check(restriction_sites, virion.methylation_profile, rng)
  end

  @doc "The per-site cleavage probability (exposed for tests)."
  @spec cleave_probability() :: float()
  def cleave_probability, do: @cleave_p

  # ---------------------------------------------------------------------------
  # Private helpers

  defp roll_per_site(sites, rng) do
    Enum.reduce_while(sites, {:passed, rng}, fn site, {:passed, acc_rng} ->
      {roll, next_rng} = :rand.uniform_s(acc_rng)

      if roll < @cleave_p do
        {:halt, {:digested, [site], next_rng}}
      else
        {:cont, {:passed, next_rng}}
      end
    end)
  end
end
