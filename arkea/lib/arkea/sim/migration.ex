defmodule Arkea.Sim.Migration do
  @moduledoc """
  Pure migration planner and applier for Phase 8 network topology.

  The runtime ownership remains:

  - `Arkea.Sim.Tick` updates one biotope in isolation.
  - `Arkea.Sim.Migration.Coordinator` observes post-tick states and orchestrates
    inter-biotopo transfers.
  - This module stays pure: given a set of `BiotopeState` values, it computes
    transfer deltas and can apply one transfer back to a single state.

  ## Model

  Migration happens at three levels:

  - lineages: integer cell-equivalent abundance indices
  - metabolites and signals: floats
  - free phages: integers

  Lineages move phase-to-phase. A source phase prefers destination phases with
  similar environmental parameters and receives a small extra boost when the
  phase names match (e.g. `:surface -> :surface`).
  """

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Phenotype

  @default_base_flow 0.12
  @default_metabolite_flow_scale 0.45
  @default_signal_flow_scale 0.70
  @default_phage_flow_scale 0.30

  @type lineage_phase_deltas :: %{atom() => integer()}

  @type transfer :: %{
          lineage_deltas: %{binary() => lineage_phase_deltas()},
          lineage_templates: %{binary() => Lineage.t()},
          metabolite_deltas: %{atom() => %{atom() => float()}},
          signal_deltas: %{atom() => %{binary() => float()}},
          phage_deltas: %{atom() => %{binary() => integer()}}
        }

  @doc "Empty transfer payload."
  @spec empty_transfer() :: transfer()
  def empty_transfer do
    %{
      lineage_deltas: %{},
      lineage_templates: %{},
      metabolite_deltas: %{},
      signal_deltas: %{},
      phage_deltas: %{}
    }
  end

  @doc """
  True when the transfer contains no effective delta.
  """
  @spec empty_transfer?(transfer()) :: boolean()
  def empty_transfer?(transfer) when is_map(transfer) do
    zero_integer_phase_map?(transfer.lineage_deltas) and
      zero_float_phase_map?(transfer.metabolite_deltas) and
      zero_float_phase_map?(transfer.signal_deltas) and
      zero_integer_phase_map?(transfer.phage_deltas)
  end

  @doc """
  Compute the migration plan for a list of post-tick biotope states.

  Returns a map `biotope_id => transfer()`. The plan is deterministic.
  """
  @spec plan([BiotopeState.t()], keyword()) :: %{binary() => transfer()}
  def plan(states, opts \\ []) when is_list(states) do
    states_by_id = Map.new(states, &{&1.id, &1})

    Enum.reduce(states, %{}, fn source_state, acc ->
      source_state
      |> plan_lineage_transfers(states_by_id, opts)
      |> merge_transfer_maps(acc)
      |> then(fn transfer_acc ->
        plan_pool_transfers(source_state, states_by_id, opts, transfer_acc)
      end)
    end)
  end

  @doc """
  Apply one transfer to a single biotope state.

  Pure. Does not emit PubSub messages and does not touch any process state.
  """
  @spec apply_transfer(BiotopeState.t(), transfer()) :: BiotopeState.t()
  def apply_transfer(%BiotopeState{} = state, transfer) when is_map(transfer) do
    if empty_transfer?(transfer) do
      state
    else
      state
      |> apply_lineage_deltas(transfer)
      |> apply_phase_deltas(transfer)
    end
  end

  @doc """
  Summarise one biotope-scoped transfer for logging or UI events.
  """
  @spec transfer_summary(transfer()) :: %{
          lineage_cells: non_neg_integer(),
          metabolite_mass: float(),
          signal_mass: float(),
          phage_particles: non_neg_integer()
        }
  def transfer_summary(transfer) when is_map(transfer) do
    %{
      lineage_cells: positive_integer_phase_sum(transfer.lineage_deltas),
      metabolite_mass: positive_float_phase_sum(transfer.metabolite_deltas),
      signal_mass: positive_float_phase_sum(transfer.signal_deltas),
      phage_particles: positive_integer_phase_sum(transfer.phage_deltas)
    }
  end

  @doc """
  Distance-derived directed edge weight in `0.0..1.0`.
  """
  @spec edge_weight(BiotopeState.t(), BiotopeState.t()) :: float()
  def edge_weight(%BiotopeState{x: x1, y: y1}, %BiotopeState{x: x2, y: y2}) do
    distance = :math.sqrt(:math.pow(x1 - x2, 2) + :math.pow(y1 - y2, 2))
    1.0 / (1.0 + distance)
  end

  @doc """
  Mean environmental compatibility between two biotopes in `0.0..1.0`.
  """
  @spec biotope_compatibility(BiotopeState.t(), BiotopeState.t()) :: float()
  def biotope_compatibility(%BiotopeState{phases: src_phases}, %BiotopeState{phases: dst_phases}) do
    src_phases
    |> Enum.map(fn src_phase -> best_phase_score(src_phase, dst_phases) end)
    |> mean()
    |> clamp(0.0, 1.0)
  end

  @doc """
  Environmental compatibility between two phases in `0.0..1.0`.
  """
  @spec phase_compatibility(Phase.t(), Phase.t()) :: float()
  def phase_compatibility(%Phase{} = source, %Phase{} = destination) do
    temperature_delta = (abs(source.temperature - destination.temperature) / 70.0) |> min(1.0)
    ph_delta = (abs(source.ph - destination.ph) / 7.0) |> min(1.0)
    osm_delta = (abs(source.osmolarity - destination.osmolarity) / 1_200.0) |> min(1.0)

    base =
      1.0 -
        (temperature_delta * 0.45 +
           ph_delta * 0.35 +
           osm_delta * 0.20)

    same_phase_bonus = if source.name == destination.name, do: 1.15, else: 1.0
    clamp(base * same_phase_bonus, 0.0, 1.0)
  end

  # ---------------------------------------------------------------------------
  # Planning

  defp plan_lineage_transfers(source_state, states_by_id, opts) do
    neighbors = neighbor_states(source_state, states_by_id)
    base_flow = Keyword.get(opts, :base_flow, @default_base_flow)

    Enum.reduce(source_state.lineages, %{}, fn lineage, acc ->
      phenotype = if lineage.genome != nil, do: Phenotype.from_genome(lineage.genome), else: nil

      Enum.reduce(lineage.abundance_by_phase, acc, fn {phase_name, abundance}, inner_acc ->
        source_phase = phase_by_name(source_state, phase_name)

        cond do
          abundance <= 0 or source_phase == nil ->
            inner_acc

          neighbors == [] ->
            inner_acc

          true ->
            move_lineage_from_phase(
              source_state,
              source_phase,
              lineage,
              abundance,
              phenotype,
              neighbors,
              base_flow,
              inner_acc
            )
        end
      end)
    end)
  end

  defp move_lineage_from_phase(
         source_state,
         source_phase,
         lineage,
         abundance,
         phenotype,
         neighbors,
         base_flow,
         acc
       ) do
    scores =
      Enum.map(neighbors, fn destination ->
        {destination, neighbor_score(source_state, destination, source_phase)}
      end)

    positive_scores = Enum.filter(scores, fn {_destination, score} -> score > 0.0 end)

    if positive_scores == [] do
      acc
    else
      mobility = lineage_mobility(source_phase.name, phenotype)
      total_budget = min(abundance, trunc(abundance * base_flow * mobility))

      if total_budget <= 0 do
        acc
      else
        allocations =
          allocate_integer_by_weights(total_budget, Enum.map(positive_scores, &elem(&1, 1)))

        Enum.zip(positive_scores, allocations)
        |> Enum.reduce(acc, fn
          {{destination, _score}, count_to_neighbor}, transfer_acc when count_to_neighbor > 0 ->
            distribute_lineage_to_destination(
              source_phase,
              source_state.id,
              destination,
              lineage,
              count_to_neighbor,
              transfer_acc
            )

          _, transfer_acc ->
            transfer_acc
        end)
      end
    end
  end

  defp distribute_lineage_to_destination(
         source_phase,
         source_id,
         destination_state,
         lineage,
         count_to_neighbor,
         acc
       ) do
    phase_weights = Enum.map(destination_state.phases, &phase_compatibility(source_phase, &1))

    allocations = allocate_integer_by_weights(count_to_neighbor, phase_weights)

    Enum.zip(destination_state.phases, allocations)
    |> Enum.reduce(acc, fn
      {%Phase{name: phase_name}, moved}, transfer_acc when moved > 0 ->
        transfer_acc
        |> put_lineage_delta(source_id, lineage.id, source_phase.name, -moved, lineage)
        |> put_lineage_delta(destination_state.id, lineage.id, phase_name, moved, lineage)

      _, transfer_acc ->
        transfer_acc
    end)
  end

  defp plan_pool_transfers(source_state, states_by_id, opts, acc) do
    neighbors = neighbor_states(source_state, states_by_id)
    base_flow = Keyword.get(opts, :base_flow, @default_base_flow)

    Enum.reduce(source_state.phases, acc, fn source_phase, transfer_acc ->
      scores =
        Enum.map(neighbors, fn destination ->
          {destination, neighbor_score(source_state, destination, source_phase)}
        end)
        |> Enum.filter(fn {_destination, score} -> score > 0.0 end)

      if scores == [] do
        transfer_acc
      else
        transfer_acc
        |> move_phase_pool(
          source_state.id,
          source_phase,
          scores,
          source_phase.metabolite_pool,
          base_flow * Keyword.get(opts, :metabolite_flow_scale, @default_metabolite_flow_scale),
          :metabolite
        )
        |> move_phase_pool(
          source_state.id,
          source_phase,
          scores,
          source_phase.signal_pool,
          base_flow * Keyword.get(opts, :signal_flow_scale, @default_signal_flow_scale),
          :signal
        )
        |> move_phase_pool(
          source_state.id,
          source_phase,
          scores,
          source_phase.phage_pool,
          base_flow * Keyword.get(opts, :phage_flow_scale, @default_phage_flow_scale),
          :phage
        )
      end
    end)
  end

  defp move_phase_pool(acc, _source_id, _source_phase, _scores, pool, _scale, _kind)
       when pool == %{},
       do: acc

  defp move_phase_pool(acc, source_id, source_phase, scores, pool, scale, kind) do
    Enum.reduce(pool, acc, fn {key, amount}, transfer_acc ->
      if zero_amount?(amount) do
        transfer_acc
      else
        total_budget = scale_budget(amount, scale)

        if zero_amount?(total_budget) do
          transfer_acc
        else
          distribute_pool_budget(
            transfer_acc,
            source_id,
            source_phase,
            scores,
            key,
            total_budget,
            kind
          )
        end
      end
    end)
  end

  defp distribute_pool_budget(
         acc,
         source_id,
         source_phase,
         scores,
         key,
         total_budget,
         kind
       ) do
    neighbor_amounts =
      case kind do
        :phage ->
          allocate_integer_by_weights(total_budget, Enum.map(scores, &elem(&1, 1)))

        _ ->
          scale_float_by_weights(total_budget, Enum.map(scores, &elem(&1, 1)))
      end

    Enum.zip(scores, neighbor_amounts)
    |> Enum.reduce(acc, fn {{destination, _score}, moved}, transfer_acc ->
      if zero_amount?(moved) do
        transfer_acc
      else
        phase_weights = Enum.map(destination.phases, &phase_compatibility(source_phase, &1))

        transfer_acc
        |> put_phase_resource_delta(source_id, source_phase.name, kind, key, negate(moved))
        |> put_destination_phase_resource_deltas(
          destination.id,
          destination.phases,
          phase_weights,
          kind,
          key,
          moved
        )
      end
    end)
  end

  defp put_destination_phase_resource_deltas(
         acc,
         destination_id,
         destination_phases,
         phase_weights,
         kind,
         key,
         moved
       ) do
    allocations =
      case kind do
        :phage -> allocate_integer_by_weights(moved, phase_weights)
        _ -> scale_float_by_weights(moved, phase_weights)
      end

    Enum.zip(destination_phases, allocations)
    |> Enum.reduce(acc, fn {%Phase{name: phase_name}, delta}, inner_acc ->
      if zero_amount?(delta) do
        inner_acc
      else
        put_phase_resource_delta(inner_acc, destination_id, phase_name, kind, key, delta)
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Applying transfers

  defp apply_lineage_deltas(state, transfer) do
    existing_ids = MapSet.new(Enum.map(state.lineages, & &1.id))

    updated_existing =
      Enum.map(state.lineages, fn lineage ->
        deltas = Map.get(transfer.lineage_deltas, lineage.id, %{})

        if map_size(deltas) == 0 do
          lineage
        else
          Lineage.apply_growth(lineage, deltas)
        end
      end)

    spawned_lineages =
      transfer.lineage_deltas
      |> Enum.reject(fn {lineage_id, _deltas} -> MapSet.member?(existing_ids, lineage_id) end)
      |> Enum.map(fn {lineage_id, deltas} ->
        template = Map.fetch!(transfer.lineage_templates, lineage_id)
        clone_lineage(template, positive_phase_deltas(deltas))
      end)
      |> Enum.reject(&(Lineage.total_abundance(&1) == 0))

    %{
      state
      | lineages:
          Enum.reject(updated_existing ++ spawned_lineages, &(Lineage.total_abundance(&1) == 0))
    }
  end

  defp apply_phase_deltas(state, transfer) do
    updated_phases =
      Enum.map(state.phases, fn phase ->
        metabolite_delta = Map.get(transfer.metabolite_deltas, phase.name, %{})
        signal_delta = Map.get(transfer.signal_deltas, phase.name, %{})
        phage_delta = Map.get(transfer.phage_deltas, phase.name, %{})

        phase
        |> apply_float_pool_delta(:metabolite_pool, metabolite_delta)
        |> apply_float_pool_delta(:signal_pool, signal_delta)
        |> apply_integer_pool_delta(:phage_pool, phage_delta)
      end)

    %{state | phases: updated_phases}
  end

  defp apply_float_pool_delta(%Phase{} = phase, _field, delta) when delta == %{}, do: phase

  defp apply_float_pool_delta(%Phase{} = phase, field, delta) do
    updated_pool =
      Enum.reduce(delta, Map.fetch!(phase, field), fn {key, diff}, acc ->
        Map.update(acc, key, max(diff, 0.0), fn current -> max(current + diff, 0.0) end)
      end)
      |> Enum.reject(fn {_key, value} -> value <= 0.0 end)
      |> Map.new()

    Map.put(phase, field, updated_pool)
  end

  defp apply_integer_pool_delta(%Phase{} = phase, _field, delta) when delta == %{}, do: phase

  defp apply_integer_pool_delta(%Phase{} = phase, field, delta) do
    updated_pool =
      Enum.reduce(delta, Map.fetch!(phase, field), fn {key, diff}, acc ->
        Map.update(acc, key, max(diff, 0), fn current -> max(current + diff, 0) end)
      end)
      |> Enum.reject(fn {_key, value} -> value == 0 end)
      |> Map.new()

    Map.put(phase, field, updated_pool)
  end

  defp clone_lineage(template, abundances) do
    %{template | abundance_by_phase: abundances, fitness_cache: nil}
  end

  defp positive_phase_deltas(deltas) do
    deltas
    |> Enum.filter(fn {_phase_name, delta} -> delta > 0 end)
    |> Map.new()
  end

  # ---------------------------------------------------------------------------
  # Transfer assembly

  defp put_lineage_delta(acc, biotope_id, lineage_id, phase_name, delta, template)
       when delta != 0 do
    update_in(acc, [biotope_id], fn transfer ->
      transfer
      |> ensure_transfer()
      |> then(fn ensured ->
        updated_deltas =
          Map.update(
            ensured.lineage_deltas,
            lineage_id,
            %{phase_name => delta},
            fn phase_deltas ->
              Map.update(phase_deltas, phase_name, delta, &(&1 + delta))
            end
          )

        templates =
          if delta > 0 do
            Map.put_new(ensured.lineage_templates, lineage_id, template)
          else
            ensured.lineage_templates
          end

        %{ensured | lineage_deltas: updated_deltas, lineage_templates: templates}
      end)
    end)
  end

  defp put_lineage_delta(acc, _biotope_id, _lineage_id, _phase_name, _delta, _template), do: acc

  defp put_phase_resource_delta(acc, biotope_id, phase_name, kind, key, delta) when delta != 0 do
    update_in(acc, [biotope_id], fn transfer ->
      transfer
      |> ensure_transfer()
      |> do_put_phase_resource_delta(phase_name, kind, key, delta)
    end)
  end

  defp put_phase_resource_delta(acc, _biotope_id, _phase_name, _kind, _key, _delta), do: acc

  defp do_put_phase_resource_delta(transfer, phase_name, :metabolite, key, delta) do
    %{
      transfer
      | metabolite_deltas:
          update_phase_delta_map(transfer.metabolite_deltas, phase_name, key, delta)
    }
  end

  defp do_put_phase_resource_delta(transfer, phase_name, :signal, key, delta) do
    %{
      transfer
      | signal_deltas: update_phase_delta_map(transfer.signal_deltas, phase_name, key, delta)
    }
  end

  defp do_put_phase_resource_delta(transfer, phase_name, :phage, key, delta) do
    %{
      transfer
      | phage_deltas: update_phase_delta_map(transfer.phage_deltas, phase_name, key, delta)
    }
  end

  defp update_phase_delta_map(phase_map, phase_name, key, delta) do
    Map.update(phase_map, phase_name, %{key => delta}, fn pool_delta ->
      Map.update(pool_delta, key, delta, &(&1 + delta))
    end)
  end

  defp ensure_transfer(nil), do: empty_transfer()
  defp ensure_transfer(transfer), do: transfer

  defp merge_transfer_maps(left, right) do
    Map.merge(right, left, fn _biotope_id, existing, incoming ->
      %{
        lineage_deltas:
          Map.merge(existing.lineage_deltas, incoming.lineage_deltas, fn _lineage_id, a, b ->
            Map.merge(a, b, fn _phase_name, delta_a, delta_b -> delta_a + delta_b end)
          end),
        lineage_templates: Map.merge(existing.lineage_templates, incoming.lineage_templates),
        metabolite_deltas:
          merge_phase_resource_maps(existing.metabolite_deltas, incoming.metabolite_deltas),
        signal_deltas: merge_phase_resource_maps(existing.signal_deltas, incoming.signal_deltas),
        phage_deltas: merge_phase_resource_maps(existing.phage_deltas, incoming.phage_deltas)
      }
    end)
  end

  defp merge_phase_resource_maps(left, right) do
    Map.merge(left, right, fn _phase_name, left_map, right_map ->
      Map.merge(left_map, right_map, fn _key, left_delta, right_delta ->
        left_delta + right_delta
      end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Scoring helpers

  defp neighbor_states(%BiotopeState{neighbor_ids: neighbor_ids, id: source_id}, states_by_id) do
    neighbor_ids
    |> Enum.uniq()
    |> Enum.reject(&(&1 == source_id))
    |> Enum.map(&Map.get(states_by_id, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp phase_by_name(%BiotopeState{phases: phases}, phase_name) do
    Enum.find(phases, &(&1.name == phase_name))
  end

  defp neighbor_score(source_state, destination_state, source_phase) do
    edge_weight(source_state, destination_state) *
      zone_factor(source_state.zone, destination_state.zone) *
      best_phase_score(source_phase, destination_state.phases)
  end

  defp best_phase_score(source_phase, destination_phases) do
    destination_phases
    |> Enum.map(&phase_compatibility(source_phase, &1))
    |> Enum.max(fn -> 0.0 end)
  end

  defp zone_factor(:unassigned, _), do: 1.0
  defp zone_factor(_, :unassigned), do: 1.0
  defp zone_factor(zone, zone), do: 1.15
  defp zone_factor(_, _), do: 0.75

  defp lineage_mobility(phase_name, nil) do
    phase_mobility(phase_name)
  end

  defp lineage_mobility(phase_name, phenotype) do
    anchor_penalty = phenotype.n_transmembrane * 0.12
    stability_bonus = phenotype.structural_stability * 0.10
    clamp(phase_mobility(phase_name) - anchor_penalty + stability_bonus, 0.05, 1.0)
  end

  defp phase_mobility(phase_name)

  defp phase_mobility(phase_name)
       when phase_name in [
              :surface,
              :water_column,
              :mixing_zone,
              :interface,
              :freshwater_layer,
              :marine_layer,
              :soil_water,
              :aerated_pore,
              :surface_oxic
            ],
       do: 1.0

  defp phase_mobility(phase_name)
       when phase_name in [:acid_water, :wet_clump, :peat_core, :marine_sediment],
       do: 0.65

  defp phase_mobility(phase_name)
       when phase_name in [:sediment, :bulk_sediment, :mineral_surface, :vent_core],
       do: 0.35

  defp phase_mobility(_phase_name), do: 0.60

  # ---------------------------------------------------------------------------
  # Numeric helpers

  defp allocate_integer_by_weights(total, weights) when total <= 0 or weights == [] do
    List.duplicate(0, length(weights))
  end

  defp allocate_integer_by_weights(total, weights) do
    positive_sum = Enum.sum(weights)

    if positive_sum <= 0.0 do
      List.duplicate(0, length(weights))
    else
      raw =
        Enum.map(weights, fn weight ->
          if weight <= 0.0, do: 0.0, else: total * weight / positive_sum
        end)

      floors = Enum.map(raw, &trunc/1)
      remainder = total - Enum.sum(floors)

      raw
      |> Enum.with_index()
      |> Enum.map(fn {value, idx} -> {idx, value - trunc(value)} end)
      |> Enum.sort_by(fn {_idx, fraction} -> -fraction end)
      |> Enum.take(remainder)
      |> Enum.reduce(floors, fn {idx, _fraction}, acc -> List.update_at(acc, idx, &(&1 + 1)) end)
    end
  end

  defp scale_float_by_weights(total, weights) when total == 0.0 or weights == [] do
    List.duplicate(0.0, length(weights))
  end

  defp scale_float_by_weights(total, weights) do
    positive_sum = Enum.sum(weights)

    if positive_sum <= 0.0 do
      List.duplicate(0.0, length(weights))
    else
      weights
      |> Enum.with_index()
      |> Enum.map(fn {weight, idx} ->
        cond do
          weight <= 0.0 ->
            0.0

          idx == length(weights) - 1 ->
            allocated_so_far =
              weights
              |> Enum.take(idx)
              |> Enum.map(fn previous_weight ->
                if previous_weight <= 0.0, do: 0.0, else: total * previous_weight / positive_sum
              end)
              |> Enum.sum()

            total - allocated_so_far

          true ->
            total * weight / positive_sum
        end
      end)
    end
  end

  defp scale_budget(amount, scale) when is_integer(amount), do: min(amount, trunc(amount * scale))
  defp scale_budget(amount, scale) when is_float(amount), do: amount * scale

  defp positive_integer_phase_sum(phase_map) do
    phase_map
    |> Map.values()
    |> Enum.flat_map(&Map.values/1)
    |> Enum.filter(&(&1 > 0))
    |> Enum.sum()
  end

  defp positive_float_phase_sum(phase_map) do
    phase_map
    |> Map.values()
    |> Enum.flat_map(&Map.values/1)
    |> Enum.filter(&(&1 > 0.0))
    |> Enum.sum()
  end

  defp zero_integer_phase_map?(phase_map) do
    Enum.all?(phase_map, fn {_phase_name, deltas} ->
      Enum.all?(deltas, fn {_key, delta} -> delta == 0 end)
    end)
  end

  defp zero_float_phase_map?(phase_map) do
    Enum.all?(phase_map, fn {_phase_name, deltas} ->
      Enum.all?(deltas, fn {_key, delta} -> abs(delta) < 1.0e-12 end)
    end)
  end

  defp zero_amount?(amount) when is_integer(amount), do: amount == 0
  defp zero_amount?(amount) when is_float(amount), do: abs(amount) < 1.0e-12

  defp negate(amount) when is_integer(amount), do: -amount
  defp negate(amount) when is_float(amount), do: -amount

  defp mean([]), do: 0.0
  defp mean(values), do: Enum.sum(values) / length(values)

  defp clamp(value, lo, hi), do: value |> max(lo) |> min(hi)
end
