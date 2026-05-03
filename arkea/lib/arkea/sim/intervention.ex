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

  defp dominant_host(lineages, phase_name) do
    lineages
    |> Enum.filter(&(Lineage.abundance_in(&1, phase_name) > 0 and &1.genome != nil))
    |> Enum.reject(&plasmid_bearing?/1)
    |> Enum.max_by(&Lineage.abundance_in(&1, phase_name), fn -> nil end)
    |> case do
      %Lineage{} = lineage -> {:ok, lineage}
      nil -> {:error, :no_lineage_host}
    end
  end

  defp plasmid_bearing?(%Lineage{genome: nil}), do: false
  defp plasmid_bearing?(%Lineage{genome: genome}), do: genome.plasmids != []

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
    Map.new(map, fn {key, value} -> {Atom.to_string(key), value} end)
  end
end
