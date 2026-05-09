defmodule Arkea.Sim.Intervention do
  @moduledoc """
  Pure intervention transforms applied outside the tick pipeline.

  Commands are validated and authorized elsewhere; this module only transforms
  authoritative `BiotopeState` data and emits typed events.
  """

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Genome
  alias Arkea.Genome.Domain
  alias Arkea.Genome.Gene
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Xenobiotic

  @nutrient_pulse %{glucose: 12.0, nh3: 2.0, po4: 1.0}
  @default_xenobiotic_dose 50.0

  # Default UV / MMS pulse — fraction of `Lineage.dna_damage_max/0`
  # added to every lineage in the targeted phase. 0.10 ≈ a moderate
  # acute exposure that is enough to push undamaged cells visibly
  # into the SOS regime (default threshold = 0.20 = 4% of cap), but
  # *not* a one-shot kill (the per-tick decay of 0.10 lets cells
  # recover unless successive pulses stack).
  @mutagen_pulse_default_dose 0.10

  @type command :: %{
          required(:kind) => atom(),
          required(:actor_player_id) => binary(),
          required(:actor_name) => binary(),
          optional(:phase_name) => atom(),
          optional(:scope) => atom()
        }

  @spec apply(BiotopeState.t(), command()) ::
          {:ok, BiotopeState.t(), [map()], map()} | {:error, atom()}
  def apply(%BiotopeState{} = state, %{kind: :nutrient_pulse} = command) do
    phase_name = Map.get(command, :phase_name)

    with {:ok, phase} <- fetch_phase(state, phase_name) do
      updated_phase =
        Enum.reduce(@nutrient_pulse, phase, fn {metabolite, amount}, acc ->
          current = Map.get(acc.metabolite_pool, metabolite, 0.0)
          Phase.update_metabolite(acc, metabolite, current + amount)
        end)

      new_state = put_phase(state, updated_phase)

      payload =
        base_payload(command, state, phase_name, %{metabolites: stringify_map(@nutrient_pulse)})

      {:ok, new_state, [%{type: :intervention, payload: payload}], payload}
    end
  end

  def apply(%BiotopeState{} = state, %{kind: :plasmid_inoculation} = command) do
    phase_name = Map.get(command, :phase_name)

    with {:ok, _phase} <- fetch_phase(state, phase_name),
         {:ok, host} <- dominant_host(state.lineages, phase_name) do
      child = build_plasmid_child(state, host, phase_name)
      new_state = %{state | lineages: [child | state.lineages]}

      payload =
        base_payload(command, state, phase_name, %{
          lineage_id: child.id,
          host_lineage_id: host.id,
          plasmid_gene_count: 1
        })

      {:ok, new_state, [%{type: :intervention, payload: payload}], payload}
    end
  end

  def apply(%BiotopeState{} = state, %{kind: :mixing_event} = command) do
    case state.phases do
      [] ->
        {:error, :invalid_phase}

      phases ->
        mixed_lineages = Enum.map(state.lineages, &redistribute_lineage(&1, phases))
        mixed_phases = homogenize_phase_pools(phases)

        payload =
          base_payload(command, state, nil, %{
            mixed_phase_count: length(phases),
            lineage_count: length(state.lineages)
          })

        {:ok, %{state | lineages: mixed_lineages, phases: mixed_phases},
         [%{type: :intervention, payload: payload}], payload}
    end
  end

  def apply(%BiotopeState{} = state, %{kind: :xenobiotic_pulse} = command) do
    phase_name = Map.get(command, :phase_name)
    xeno_id = Map.get(command, :xenobiotic_id, :beta_lactam)
    dose = Map.get(command, :dose, @default_xenobiotic_dose)

    with {:ok, phase} <- fetch_phase(state, phase_name),
         {:ok, _entry} <- fetch_xeno_entry(xeno_id),
         {:ok, dose_f} <- normalise_dose(dose) do
      updated_phase = Phase.add_xenobiotic(phase, xeno_id, dose_f)
      new_state = put_phase(state, updated_phase)

      payload =
        base_payload(command, state, phase_name, %{
          xenobiotic_id: Atom.to_string(xeno_id),
          dose: dose_f
        })

      {:ok, new_state, [%{type: :intervention, payload: payload}], payload}
    end
  end

  # Phase 27 / 27.2 — UV / MMS-like mutagenic pulse. Adds a fraction
  # of `Lineage.dna_damage_max/0` to every lineage *resident in*
  # `phase_name` (i.e. with abundance > 0 there). Cells already at
  # the damage cap clamp at the cap. Cells in other phases are
  # unaffected — the pulse is a phase-local irradiation (UV reaches
  # the surface phase but not deeper anaerobic zones; MMS in a
  # specific compartment doesn't migrate). Emits a per-lineage
  # `:dna_damage_pulse` audit entry alongside the umbrella
  # `:intervention` so consumers can track which cells were hit.
  def apply(%BiotopeState{} = state, %{kind: :mutagen_pulse} = command) do
    phase_name = Map.get(command, :phase_name)
    dose = Map.get(command, :dose, @mutagen_pulse_default_dose)

    with {:ok, _phase} <- fetch_phase(state, phase_name),
         {:ok, dose_f} <- normalise_dose(dose) do
      {updated_lineages, hit_ids} =
        apply_mutagen_pulse(state.lineages, phase_name, dose_f)

      payload =
        base_payload(command, state, phase_name, %{
          dose: dose_f,
          source: stringify_or_default(Map.get(command, :source), "uv"),
          affected_lineage_count: length(hit_ids)
        })

      events =
        [%{type: :intervention, payload: payload}] ++
          Enum.map(hit_ids, fn id ->
            %{
              type: :dna_damage_pulse,
              lineage_id: id,
              dose: dose_f,
              source: Map.get(command, :source, :uv),
              tick: state.tick_count
            }
          end)

      {:ok, %{state | lineages: updated_lineages}, events, payload}
    end
  end

  # Phase 27 / 27.3 — environmental shift. Updates the targeted
  # phase's physical parameters (`temperature`, `ph`, `osmolarity`,
  # `dilution_rate`) by the supplied keys. Each parameter is
  # validated against `Phase.validate/1`'s ranges; if the resulting
  # phase is invalid the whole intervention is rejected
  # (`:invalid_environment`). Unrelated keys in the command are
  # ignored. Emits a `:intervention` event with the *applied delta*
  # (only the keys that actually changed).
  def apply(%BiotopeState{} = state, %{kind: :environmental_shift} = command) do
    phase_name = Map.get(command, :phase_name)
    shifts = Map.get(command, :shifts, %{})

    with {:ok, phase} <- fetch_phase(state, phase_name),
         {:ok, updated_phase, applied} <- apply_environmental_shifts(phase, shifts),
         :ok <- Phase.validate(updated_phase) do
      new_state = put_phase(state, updated_phase)

      payload =
        base_payload(command, state, phase_name, %{
          applied: stringify_map(applied)
        })

      {:ok, new_state, [%{type: :intervention, payload: payload}], payload}
    else
      :invalid_environment -> {:error, :invalid_environment}
      {:error, _reason} = err -> err
      other when is_atom(other) -> {:error, other}
    end
  end

  # Phase 27 / 27.4 — surgical gene knockout. Replaces every codon
  # of the named gene in the target lineage with `0`, leaving the
  # codon count (and therefore the gene-grammar invariant) intact.
  # The resulting domains parse to `:substrate_binding` with
  # all-zero parameters — biologically equivalent to a non-functional
  # gene product (zero kcat, zero affinity, zero binding). The
  # `genome.gene_count` is recomputed; the lineage's `fitness_cache`
  # is invalidated so the next tick re-derives the phenotype from
  # the (now broken) genome.
  #
  # The lineage is matched by `:lineage_id`; the gene is matched by
  # `:gene_id` against the chromosome only (plasmid / prophage
  # knockouts are out of scope for v1 — those are usually achieved
  # by curing the replicon, which is a different intervention).
  def apply(%BiotopeState{} = state, %{kind: :gene_knockout} = command) do
    lineage_id = Map.get(command, :lineage_id)
    gene_id = Map.get(command, :gene_id)

    with {:ok, lineage} <- fetch_lineage(state, lineage_id),
         {:ok, knocked_genome, knocked_gene_id} <- knock_out_chromosome_gene(lineage, gene_id) do
      knocked_lineage = %{lineage | genome: knocked_genome, fitness_cache: nil}
      new_lineages = replace_lineage(state.lineages, knocked_lineage)
      new_state = %{state | lineages: new_lineages}

      payload =
        base_payload(command, state, nil, %{
          lineage_id: lineage_id,
          gene_id: knocked_gene_id
        })

      events = [
        %{type: :intervention, payload: payload},
        %{
          type: :gene_knockout,
          lineage_id: lineage_id,
          gene_id: knocked_gene_id,
          tick: state.tick_count
        }
      ]

      {:ok, new_state, events, payload}
    end
  end

  # Phase 27 / 27.5 — heterologous lineage inoculation. Adds a
  # caller-supplied genome as a new founder lineage of the biotope
  # at the targeted phase, with the supplied initial abundance.
  # This is the "save a lineage you observed elsewhere and
  # reintroduce it later" workflow — it lets the player retry an
  # experiment with the same genetic background instead of waiting
  # for re-derivation from random mutation.
  #
  # The genome is validated; abundance is required positive. The
  # founder is born at the *current* tick (not 0), so its lineage
  # tree position reflects when the player intervened.
  def apply(%BiotopeState{} = state, %{kind: :lineage_inoculation} = command) do
    phase_name = Map.get(command, :phase_name)
    genome = Map.get(command, :genome)
    abundance = Map.get(command, :abundance, 100)
    seed_id = Map.get(command, :original_seed_id)

    with {:ok, _phase} <- fetch_phase(state, phase_name),
         {:ok, valid_genome} <- validate_inoculation_genome(genome),
         {:ok, abund} <- validate_inoculation_abundance(abundance) do
      founder =
        Lineage.new_founder(
          valid_genome,
          %{phase_name => abund},
          state.tick_count,
          if(seed_id, do: [original_seed_id: seed_id], else: [])
        )

      new_lineages = [founder | state.lineages]
      new_state = %{state | lineages: new_lineages}

      payload =
        base_payload(command, state, phase_name, %{
          lineage_id: founder.id,
          abundance: abund,
          original_seed_id: seed_id
        })

      events = [
        %{type: :intervention, payload: payload},
        %{
          type: :lineage_inoculated,
          lineage_id: founder.id,
          phase_name: phase_name,
          abundance: abund,
          tick: state.tick_count
        }
      ]

      {:ok, new_state, events, payload}
    end
  end

  def apply(_state, _command), do: {:error, :unknown_intervention}

  defp fetch_xeno_entry(xeno_id) when is_atom(xeno_id) do
    case Xenobiotic.entry(xeno_id) do
      nil -> {:error, :unknown_xenobiotic}
      entry -> {:ok, entry}
    end
  end

  defp fetch_xeno_entry(_), do: {:error, :unknown_xenobiotic}

  defp normalise_dose(dose) when is_float(dose) and dose >= 0.0, do: {:ok, dose}
  defp normalise_dose(dose) when is_integer(dose) and dose >= 0, do: {:ok, dose * 1.0}
  defp normalise_dose(_), do: {:error, :invalid_dose}

  defp fetch_phase(%BiotopeState{phases: phases}, phase_name) when is_atom(phase_name) do
    case Enum.find(phases, &(&1.name == phase_name)) do
      %Phase{} = phase -> {:ok, phase}
      nil -> {:error, :invalid_phase}
    end
  end

  defp fetch_phase(_state, _phase_name), do: {:error, :invalid_phase}

  defp put_phase(%BiotopeState{phases: phases} = state, %Phase{name: phase_name} = updated_phase) do
    updated =
      Enum.map(phases, fn
        %Phase{name: ^phase_name} -> updated_phase
        phase -> phase
      end)

    %{state | phases: updated}
  end

  # Find the dominant lineage in `phase_name` that can host an
  # additional plasmid. Recipients are allowed to already carry
  # plasmids — natural conjugation chains let cells accumulate
  # multiple co-resident replicons; incompatibility-driven displacement
  # is handled later by the HGT plasmid step (Phase 16-BIO), not gated
  # here. The only requirement is "alive in the phase, has a genome".
  defp dominant_host(lineages, phase_name) do
    lineages
    |> Enum.filter(&(Lineage.abundance_in(&1, phase_name) > 0 and &1.genome != nil))
    |> Enum.max_by(&Lineage.abundance_in(&1, phase_name), fn -> nil end)
    |> case do
      %Lineage{} = lineage -> {:ok, lineage}
      nil -> {:error, :no_lineage_host}
    end
  end

  defp build_plasmid_child(%BiotopeState{tick_count: tick}, host, phase_name) do
    plasmid_gene =
      Gene.from_domains([
        Domain.new([0, 0, 2], List.duplicate(9, 20)),
        Domain.new([0, 0, 9], [0 | List.duplicate(8, 19)])
      ])

    child_genome = Genome.add_plasmid(host.genome, [plasmid_gene])
    child_tick = max(tick + 1, host.created_at_tick + 1)
    Lineage.new_child(host, child_genome, %{phase_name => 12}, child_tick)
  end

  defp redistribute_lineage(lineage, phases) do
    total = Lineage.total_abundance(lineage)
    phase_names = Enum.map(phases, & &1.name)
    phase_count = max(length(phase_names), 1)
    base = div(total, phase_count)
    remainder = rem(total, phase_count)

    abundance_by_phase =
      phase_names
      |> Enum.with_index()
      |> Map.new(fn {phase_name, index} ->
        extra = if index < remainder, do: 1, else: 0
        {phase_name, base + extra}
      end)

    %{lineage | abundance_by_phase: abundance_by_phase, fitness_cache: nil}
  end

  defp homogenize_phase_pools(phases) do
    metabolite_mean = mean_float_pool(phases, & &1.metabolite_pool)
    signal_mean = mean_float_pool(phases, & &1.signal_pool)
    phage_mean = mean_phage_pool(phases)

    Enum.map(phases, fn phase ->
      %{
        phase
        | metabolite_pool: metabolite_mean,
          signal_pool: signal_mean,
          phage_pool: phage_mean
      }
    end)
  end

  defp mean_float_pool(phases, accessor) do
    keys =
      phases
      |> Enum.flat_map(fn phase -> phase |> accessor.() |> Map.keys() end)
      |> Enum.uniq()

    divisor = max(length(phases), 1)

    Map.new(keys, fn key ->
      total =
        Enum.sum(Enum.map(phases, fn phase -> phase |> accessor.() |> Map.get(key, 0.0) end))

      {key, Float.round(total / divisor, 2)}
    end)
  end

  # Mixing intervention: redistribute phage abundances evenly across all phases
  # while preserving the virion metadata of the first phase that owns each id.
  defp mean_phage_pool(phases) do
    divisor = max(length(phases), 1)

    keys =
      phases
      |> Enum.flat_map(fn phase -> Map.keys(phase.phage_pool) end)
      |> Enum.uniq()

    Map.new(keys, fn key ->
      total =
        Enum.sum(
          Enum.map(phases, fn phase ->
            case Map.get(phase.phage_pool, key) do
              nil -> 0
              %Arkea.Sim.HGT.Virion{abundance: a} -> a
            end
          end)
        )

      mean = round(total / divisor)

      template = Enum.find_value(phases, fn phase -> Map.get(phase.phage_pool, key) end)
      {key, %{template | abundance: mean}}
    end)
  end

  defp base_payload(command, state, phase_name, extra) do
    %{
      kind: Atom.to_string(command.kind),
      scope: command_scope(command),
      phase_name: phase_name && Atom.to_string(phase_name),
      tick: state.tick_count,
      actor_player_id: command.actor_player_id,
      actor_name: command.actor_name,
      biotope_id: state.id
    }
    |> Map.merge(extra)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp command_scope(command) do
    command
    |> Map.get(:scope, :phase)
    |> to_string()
  end

  defp stringify_map(map) do
    Map.new(map, fn {key, value} ->
      {Atom.to_string(key), stringify_value(value)}
    end)
  end

  defp stringify_value(v) when is_atom(v) and not is_boolean(v) and not is_nil(v),
    do: Atom.to_string(v)

  defp stringify_value(v), do: v

  defp stringify_or_default(nil, default), do: default
  defp stringify_or_default(v, _default) when is_binary(v), do: v
  defp stringify_or_default(v, _default) when is_atom(v), do: Atom.to_string(v)

  # ---------------------------------------------------------------------------
  # Phase 27 / 27.2 — :mutagen_pulse helpers.

  defp apply_mutagen_pulse(lineages, phase_name, dose_fraction) do
    abs_dose = dose_fraction * Lineage.dna_damage_max()
    cap = Lineage.dna_damage_max()

    {updated, hits} =
      Enum.map_reduce(lineages, [], fn lineage, hit_acc ->
        if Lineage.abundance_in(lineage, phase_name) > 0 do
          new_damage = min(lineage.dna_damage + abs_dose, cap)
          {%{lineage | dna_damage: new_damage}, [lineage.id | hit_acc]}
        else
          {lineage, hit_acc}
        end
      end)

    {updated, Enum.reverse(hits)}
  end

  # ---------------------------------------------------------------------------
  # Phase 27 / 27.3 — :environmental_shift helpers.

  @env_shift_keys [:temperature, :ph, :osmolarity, :dilution_rate]

  defp apply_environmental_shifts(%Phase{} = phase, shifts) when is_map(shifts) do
    {updated, applied} =
      Enum.reduce(@env_shift_keys, {phase, %{}}, fn key, {acc_phase, acc_applied} ->
        case Map.get(shifts, key) do
          nil ->
            {acc_phase, acc_applied}

          value when is_number(value) ->
            current = Map.get(acc_phase, key)

            if current == value do
              {acc_phase, acc_applied}
            else
              {Map.put(acc_phase, key, value * 1.0), Map.put(acc_applied, key, value * 1.0)}
            end

          _other ->
            {acc_phase, acc_applied}
        end
      end)

    if map_size(applied) == 0 do
      {:error, :no_environmental_change}
    else
      {:ok, updated, applied}
    end
  end

  defp apply_environmental_shifts(_phase, _other), do: {:error, :invalid_shifts}

  # ---------------------------------------------------------------------------
  # Phase 27 / 27.4 — :gene_knockout helpers.

  defp fetch_lineage(%BiotopeState{lineages: lineages}, lineage_id) when is_binary(lineage_id) do
    case Enum.find(lineages, &(&1.id == lineage_id)) do
      %Lineage{} = l -> {:ok, l}
      nil -> {:error, :unknown_lineage}
    end
  end

  defp fetch_lineage(_state, _id), do: {:error, :unknown_lineage}

  defp knock_out_chromosome_gene(%Lineage{genome: nil}, _gene_id),
    do: {:error, :lineage_has_no_genome}

  defp knock_out_chromosome_gene(%Lineage{genome: %Genome{} = genome}, gene_id)
       when is_binary(gene_id) do
    case Enum.find(genome.chromosome, &(&1.id == gene_id)) do
      nil ->
        {:error, :unknown_gene}

      %Gene{} = target ->
        knocked_gene = neutralise_gene(target)

        new_chromosome =
          Enum.map(genome.chromosome, fn
            %Gene{id: ^gene_id} -> knocked_gene
            other -> other
          end)

        new_genome =
          genome
          |> Map.put(:chromosome, new_chromosome)
          |> Map.put(
            :gene_count,
            length(new_chromosome) + length(genome.plasmids) +
              length(genome.prophages)
          )

        {:ok, new_genome, gene_id}
    end
  end

  defp knock_out_chromosome_gene(_lineage, _gene_id), do: {:error, :invalid_gene_id}

  defp neutralise_gene(%Gene{codons: codons} = gene) do
    zero_codons = List.duplicate(0, length(codons))
    %{gene | codons: zero_codons, domains: rebuild_zero_domains(codons)}
  end

  # The chromosome-grammar invariant requires each domain block to
  # be 23 codons (`@phase1_domain_size` in `Gene`). We cannot call
  # `Gene.from_codons/1` here without coupling to its full parser;
  # instead we rebuild the domain list from the now-zeroed codon
  # stream using the same arithmetic.
  defp rebuild_zero_domains(original_codons) do
    n_domains = max(div(length(original_codons), 23), 0)

    Enum.map(0..(n_domains - 1)//1, fn _ ->
      Domain.new([0, 0, 0], List.duplicate(0, 20))
    end)
  end

  # ---------------------------------------------------------------------------
  # Phase 27 / 27.5 — :lineage_inoculation helpers.

  defp validate_inoculation_genome(%Genome{} = genome) do
    if Genome.valid?(genome), do: {:ok, genome}, else: {:error, :invalid_genome}
  end

  defp validate_inoculation_genome(_), do: {:error, :invalid_genome}

  defp validate_inoculation_abundance(n) when is_integer(n) and n > 0, do: {:ok, n}
  defp validate_inoculation_abundance(_), do: {:error, :invalid_abundance}

  defp replace_lineage(lineages, %Lineage{id: id} = updated) do
    Enum.map(lineages, fn
      %Lineage{id: ^id} -> updated
      other -> other
    end)
  end
end
