defmodule Arkea.Persistence.AuditWriter do
  @moduledoc """
  Persists typed runtime events into `audit_log`.
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

  defp event_attrs(event, biotope_id, tick_count, occurred_at) do
    payload = Map.get(event, :payload, %{})

    %{
      event_type: event_type(Map.get(event, :type)),
      target_biotope_id: biotope_id,
      target_lineage_id: lineage_id(payload),
      payload: stringify_keys(payload),
      occurred_at_tick: tick_count,
      occurred_at: occurred_at
    }
  end

  defp event_type(:hgt_transfer), do: "hgt_event"
  defp event_type(type) when is_atom(type), do: Atom.to_string(type)
  defp event_type(type) when is_binary(type), do: type
  defp event_type(_type), do: "unknown"

  defp lineage_id(payload) when is_map(payload) do
    Map.get(payload, :lineage_id) || Map.get(payload, "lineage_id")
  end

  defp lineage_id(_payload), do: nil

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
