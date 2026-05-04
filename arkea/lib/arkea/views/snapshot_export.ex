defmodule Arkea.Views.SnapshotExport do
  @moduledoc """
  Pure JSON-friendly serialisation of a biotope state, ready for the
  Phase F export endpoints (`GET /api/biotopes/:id/snapshot.json`).

  This module shapes the data; it does not query the DB. Callers pass
  the `BiotopeState`, the audit log entries, and the optional list of
  time-series samples — `Phoenix.Controller`'s `json/2` (or Jason
  directly) does the rest.

  The shape is intentionally biology-first (lineage genealogy,
  metabolite pools, phenotype scalar fields) rather than a verbatim
  dump of the internal struct. Internal fields that have no value
  outside the running BEAM (`rng_seed`, `growth_delta_by_lineage`,
  etc.) are dropped.
  """

  alias Arkea.Ecology.Lineage
  alias Arkea.Ecology.Phase
  alias Arkea.Persistence.AuditLog
  alias Arkea.Persistence.TimeSeriesSample
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Phenotype

  @export_format_version 1

  @type export :: %{
          format_version: pos_integer(),
          biotope: map(),
          phases: [map()],
          lineages: [map()],
          audit_log: [map()],
          time_series: [map()]
        }

  @spec build(BiotopeState.t(), [AuditLog.t()], [TimeSeriesSample.t()]) :: export()
  def build(%BiotopeState{} = state, audit \\ [], samples \\ []) do
    %{
      format_version: @export_format_version,
      biotope: biotope_meta(state),
      phases: Enum.map(state.phases, &phase_export/1),
      lineages: Enum.map(state.lineages, &lineage_export/1),
      audit_log: Enum.map(audit, &audit_export/1),
      time_series: Enum.map(samples, &sample_export/1)
    }
  end

  defp biotope_meta(%BiotopeState{} = state) do
    %{
      id: state.id,
      archetype: atom_to_string(state.archetype),
      zone: atom_to_string(state.zone),
      tick_count: state.tick_count,
      x: state.x,
      y: state.y,
      owner_player_id: state.owner_player_id,
      neighbor_ids: state.neighbor_ids,
      dilution_rate: state.dilution_rate,
      total_abundance: BiotopeState.total_abundance(state),
      lineage_count: length(state.lineages),
      phase_count: length(state.phases)
    }
  end

  defp phase_export(%Phase{} = phase) do
    %{
      name: atom_to_string(phase.name),
      temperature: phase.temperature,
      ph: phase.ph,
      osmolarity: phase.osmolarity,
      dilution_rate: phase.dilution_rate,
      metabolite_pool: stringify_keys(phase.metabolite_pool),
      signal_pool: stringify_keys(phase.signal_pool),
      phage_pool_size: phage_pool_size(phase.phage_pool),
      xenobiotic_pool: stringify_keys(phase.xenobiotic_pool),
      toxin_pool: stringify_keys(phase.toxin_pool),
      dna_pool_size: dna_pool_size(Map.get(phase, :dna_pool, %{}))
    }
  end

  defp lineage_export(%Lineage{} = lineage) do
    base = %{
      id: lineage.id,
      parent_id: lineage.parent_id,
      original_seed_id: lineage.original_seed_id,
      created_at_tick: lineage.created_at_tick,
      total_abundance: Lineage.total_abundance(lineage),
      abundance_by_phase: stringify_keys(lineage.abundance_by_phase),
      biomass: stringify_keys(lineage.biomass),
      dna_damage: lineage.dna_damage,
      gene_count: lineage.genome && lineage.genome.gene_count,
      plasmid_count: lineage.genome && length(lineage.genome.plasmids),
      prophage_count: lineage.genome && length(lineage.genome.prophages)
    }

    case lineage.genome do
      nil -> Map.put(base, :phenotype, nil)
      genome -> Map.put(base, :phenotype, phenotype_export(genome))
    end
  end

  defp phenotype_export(genome) do
    %Phenotype{} = phenotype = Phenotype.from_genome(genome)

    %{
      base_growth_rate: phenotype.base_growth_rate,
      repair_efficiency: phenotype.repair_efficiency,
      energy_cost: phenotype.energy_cost,
      n_transmembrane: phenotype.n_transmembrane,
      dna_binding_affinity: phenotype.dna_binding_affinity,
      structural_stability: phenotype.structural_stability,
      surface_tags: stringify_each(phenotype.surface_tags),
      qs_produces:
        Enum.map(phenotype.qs_produces, fn {key, rate} ->
          %{signal_key: key, rate: rate}
        end),
      qs_receives:
        Enum.map(phenotype.qs_receives, fn {key, threshold} ->
          %{signal_key: key, threshold: threshold}
        end),
      biofilm_capable?: phenotype.biofilm_capable?,
      hydrolase_capacity: phenotype.hydrolase_capacity,
      efflux_capacity: phenotype.efflux_capacity
    }
  end

  defp audit_export(%AuditLog{} = entry) do
    %{
      id: entry.id,
      event_type: entry.event_type,
      occurred_at: entry.occurred_at,
      occurred_at_tick: entry.occurred_at_tick,
      target_lineage_id: entry.target_lineage_id,
      actor_player_id: entry.actor_player_id,
      payload: entry.payload || %{}
    }
  end

  defp sample_export(%TimeSeriesSample{} = sample) do
    %{
      tick: sample.tick,
      kind: sample.kind,
      scope_id: sample.scope_id,
      payload: sample.payload || %{},
      inserted_at: sample.inserted_at
    }
  end

  defp atom_to_string(nil), do: nil
  defp atom_to_string(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp atom_to_string(other), do: other

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_value(v)}
      {k, v} -> {k, stringify_value(v)}
    end)
  end

  defp stringify_keys(other), do: other

  defp stringify_value(%{} = m), do: stringify_keys(m)
  defp stringify_value(list) when is_list(list), do: Enum.map(list, &stringify_value/1)
  defp stringify_value(value), do: value

  defp stringify_each(list) when is_list(list) do
    Enum.map(list, fn
      a when is_atom(a) -> Atom.to_string(a)
      other -> other
    end)
  end

  defp stringify_each(_), do: []

  defp phage_pool_size(pool) when is_map(pool) do
    Enum.sum(
      Enum.map(pool, fn
        {_id, %{abundance: a}} when is_integer(a) -> a
        {_id, n} when is_integer(n) -> n
        _ -> 0
      end)
    )
  end

  defp phage_pool_size(_), do: 0

  defp dna_pool_size(pool) when is_map(pool) do
    Enum.sum(
      Enum.map(pool, fn
        {_id, %{abundance: a}} when is_integer(a) -> a
        {_id, n} when is_integer(n) -> n
        _ -> 0
      end)
    )
  end

  defp dna_pool_size(_), do: 0
end
