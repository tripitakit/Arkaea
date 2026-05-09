defmodule Arkea.Persistence.AuditWriter do
  @moduledoc """
  Persists typed runtime events into `audit_log`.

  Two event shapes coexist:

    * Diff-derived events (legacy, pre-remediation) — wrap their fields in
      a nested `:payload` map, e.g. `%{type: :lineage_born, payload: %{...}}`.
    * Channel-direct events (Sub-task 1.1–1.5 remediation) — flat maps with
      domain fields hoisted to the top level, e.g.
      `%{type: :transformation_event, recipient_lineage_id: ..., gene_index: ...}`.

  Each branch maps to a row with `target_lineage_id` set to the most natural
  affected lineage (recipient for HGT/transduction/phage, victim for
  bacteriocin, parent for error catastrophe).
  """

  alias Arkea.Persistence.AuditLog

  @doc """
  Insert all runtime events for one transition within an existing transaction.
  """
  @spec insert_events(Ecto.Repo.t(), binary(), non_neg_integer(), [map()], DateTime.t()) ::
          {:ok, [AuditLog.t()]} | {:error, Ecto.Changeset.t()}
  def insert_events(_repo, _biotope_id, _tick_count, [], _occurred_at), do: {:ok, []}

  def insert_events(repo, biotope_id, tick_count, events, occurred_at)
      when is_binary(biotope_id) and is_integer(tick_count) and tick_count >= 0 do
    Enum.reduce_while(events, {:ok, []}, fn event, {:ok, acc} ->
      attrs = event_attrs(event, biotope_id, tick_count, occurred_at)

      case repo.insert(AuditLog.changeset(%AuditLog{}, attrs)) do
        {:ok, entry} -> {:cont, {:ok, [entry | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, inserted} -> {:ok, Enum.reverse(inserted)}
      {:error, _} = error -> error
    end
  end

  # --- Channel-direct (flat-shape) events: Sub-task 1.6 remediation. ---

  defp event_attrs(%{type: :transformation_event} = e, biotope_id, tick_count, occurred_at) do
    base_attrs(
      biotope_id,
      tick_count,
      occurred_at,
      "transformation_event",
      e.recipient_lineage_id,
      %{
        "origin_lineage_id" => e.origin_lineage_id,
        "gene_index" => e.gene_index
      }
    )
  end

  defp event_attrs(%{type: :phage_infection} = e, biotope_id, tick_count, occurred_at) do
    base_attrs(biotope_id, tick_count, occurred_at, "phage_infection", e.recipient_lineage_id, %{
      "mode" => atom_to_string(e.mode),
      "virion_id" => e.virion_id,
      "origin_lineage_id" => e.origin_lineage_id
    })
  end

  defp event_attrs(%{type: :rm_digestion} = e, biotope_id, tick_count, occurred_at) do
    base_attrs(biotope_id, tick_count, occurred_at, "rm_digestion", e.recipient_lineage_id, %{
      "virion_id" => e.virion_id,
      "origin_lineage_id" => e.origin_lineage_id
    })
  end

  defp event_attrs(%{type: :hgt_transfer} = e, biotope_id, tick_count, occurred_at) do
    # `inc_group` is `non_neg_integer` (see `Arkea.Genome` plasmid type
    # and `Arkea.Sim.HGT`); pass through as integer.
    base_attrs(biotope_id, tick_count, occurred_at, "hgt_transfer", e.recipient_lineage_id, %{
      "channel" => atom_to_string(e.channel),
      "donor_lineage_id" => e.donor_lineage_id,
      "plasmid_inc_group" => e.plasmid_inc_group
    })
  end

  defp event_attrs(%{type: :plasmid_displaced} = e, biotope_id, tick_count, occurred_at) do
    # `inc_group` is `non_neg_integer` (see `Arkea.Genome`); integer pass-through.
    base_attrs(
      biotope_id,
      tick_count,
      occurred_at,
      "plasmid_displaced",
      e.recipient_lineage_id,
      %{
        "displaced_inc_group" => e.displaced_inc_group,
        "new_donor_lineage_id" => e.new_donor_lineage_id
      }
    )
  end

  defp event_attrs(%{type: :transduction_event} = e, biotope_id, tick_count, occurred_at) do
    base_attrs(
      biotope_id,
      tick_count,
      occurred_at,
      "transduction_event",
      e.recipient_lineage_id,
      %{
        "donor_lineage_id" => e.donor_lineage_id,
        "payload_kind" => atom_to_string(e.payload_kind)
      }
    )
  end

  defp event_attrs(%{type: :bacteriocin_kill} = e, biotope_id, tick_count, occurred_at) do
    base_attrs(biotope_id, tick_count, occurred_at, "bacteriocin_kill", e.victim_lineage_id, %{
      "producer_lineage_ids" => e.producer_lineage_ids,
      "surface_tag_target" => e.surface_tag_target
    })
  end

  defp event_attrs(%{type: :error_catastrophe_death} = e, biotope_id, tick_count, occurred_at) do
    base_attrs(biotope_id, tick_count, occurred_at, "error_catastrophe_death", e.lineage_id, %{
      "mu" => e.mu,
      "genome_size" => e.genome_size
    })
  end

  # Phase 21 (Top 5 #3) — stress / phenotype-transition events.

  defp event_attrs(%{type: :sos_active} = e, biotope_id, tick_count, occurred_at) do
    base_attrs(biotope_id, tick_count, occurred_at, "sos_active", e.lineage_id, %{
      "dna_damage" => e.dna_damage,
      "trigger_source" => atom_to_string(e.trigger_source)
    })
  end

  defp event_attrs(%{type: :mutator_emergence} = e, biotope_id, tick_count, occurred_at) do
    base_attrs(biotope_id, tick_count, occurred_at, "mutator_emergence", e.lineage_id, %{
      "parent_id" => e.parent_id,
      "parent_repair_efficiency" => e.parent_repair_efficiency,
      "child_repair_efficiency" => e.child_repair_efficiency
    })
  end

  defp event_attrs(%{type: :biofilm_formation} = e, biotope_id, tick_count, occurred_at) do
    base_attrs(biotope_id, tick_count, occurred_at, "biofilm_formation", e.lineage_id, %{
      "parent_id" => e.parent_id
    })
  end

  defp event_attrs(%{type: :biofilm_dispersal} = e, biotope_id, tick_count, occurred_at) do
    base_attrs(biotope_id, tick_count, occurred_at, "biofilm_dispersal", e.lineage_id, %{
      "parent_id" => e.parent_id
    })
  end

  defp event_attrs(%{type: :migration_pulse} = e, biotope_id, tick_count, occurred_at) do
    # `target_lineage_id` is nil — `:migration_pulse` is a per-biotope
    # aggregate, not pinned to a single lineage. The receiving biotope
    # is captured by `target_biotope_id` via `base_attrs/6`.
    base_attrs(biotope_id, tick_count, occurred_at, "migration_pulse", nil, %{
      "lineage_cells" => e.lineage_cells,
      "metabolite_mass" => e.metabolite_mass,
      "signal_mass" => e.signal_mass,
      "phage_particles" => e.phage_particles
    })
  end

  # Phase 26 / 1.13 — `:domain_flip` audit event: a mutation has
  # changed a domain's category in the child lineage. `from_type` /
  # `to_type` are stringified atoms (`"catalytic_site"`, etc.) so the
  # ledger UI can render them as human labels without a server round-
  # trip.
  defp event_attrs(%{type: :domain_flip} = e, biotope_id, tick_count, occurred_at) do
    base_attrs(biotope_id, tick_count, occurred_at, "domain_flip", e.lineage_id, %{
      "gene_id" => e.gene_id,
      "domain_index" => e.domain_index,
      "from_type" => atom_to_string(e.from_type),
      "to_type" => atom_to_string(e.to_type)
    })
  end

  # Phase 26 / 1.14 — `:gene_chimera_birth` audit event: a successful
  # `Translocation` produced a new chimeric gene by splicing codons
  # from a source gene into a destination gene.
  defp event_attrs(%{type: :gene_chimera_birth} = e, biotope_id, tick_count, occurred_at) do
    base_attrs(biotope_id, tick_count, occurred_at, "gene_chimera_birth", e.lineage_id, %{
      "source_gene_id" => e.source_gene_id,
      "dest_gene_id" => e.dest_gene_id,
      "codons_moved" => e.codons_moved
    })
  end

  # --- Legacy diff-derived events (payload-shape). ---

  defp event_attrs(event, biotope_id, tick_count, occurred_at) do
    payload = Map.get(event, :payload, %{})

    %{
      event_type: event_type(Map.get(event, :type)),
      actor_player_id: actor_player_id(payload),
      target_biotope_id: biotope_id,
      target_lineage_id: lineage_id(payload),
      payload: stringify_keys(payload),
      occurred_at_tick: tick_count,
      occurred_at: occurred_at
    }
  end

  defp base_attrs(biotope_id, tick_count, occurred_at, event_type, target_lineage_id, payload) do
    %{
      event_type: event_type,
      actor_player_id: nil,
      target_biotope_id: biotope_id,
      target_lineage_id: target_lineage_id,
      payload: payload,
      occurred_at_tick: tick_count,
      occurred_at: occurred_at
    }
  end

  defp atom_to_string(nil), do: nil
  defp atom_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp atom_to_string(value), do: value

  defp event_type(type) when is_atom(type), do: Atom.to_string(type)
  defp event_type(type) when is_binary(type), do: type
  defp event_type(_type), do: "unknown"

  defp lineage_id(payload) when is_map(payload) do
    Map.get(payload, :lineage_id) || Map.get(payload, "lineage_id")
  end

  defp lineage_id(_payload), do: nil

  defp actor_player_id(payload) when is_map(payload) do
    Map.get(payload, :actor_player_id) || Map.get(payload, "actor_player_id")
  end

  defp actor_player_id(_payload), do: nil

  defp stringify_keys(%{} = map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), stringify_value(value)}
      {key, value} -> {key, stringify_value(value)}
    end)
  end

  defp stringify_keys(other), do: other

  defp stringify_value(%{} = map), do: stringify_keys(map)
  defp stringify_value(list) when is_list(list), do: Enum.map(list, &stringify_value/1)
  defp stringify_value(value), do: value
end
