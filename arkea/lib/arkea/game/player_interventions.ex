defmodule Arkea.Game.PlayerInterventions do
  @moduledoc """
  Authorization and budget checks for player-driven biotope interventions.
  """

  import Ecto.Query

  alias Arkea.Game.PlayerAssets
  alias Arkea.Persistence.InterventionLog
  alias Arkea.Repo
  alias Arkea.Sim.Biotope.Server, as: BiotopeServer
  alias Ecto.Changeset

  @budget_cooldown_seconds 60

  @type budget_status :: %{
          allowed?: boolean(),
          owner?: boolean(),
          retry_at: DateTime.t() | nil,
          remaining_seconds: non_neg_integer(),
          last_kind: String.t() | nil
        }

  @spec status(binary(), binary()) :: budget_status()
  def status(player_id, biotope_id) when is_binary(player_id) and is_binary(biotope_id) do
    owner? = PlayerAssets.controls_biotope?(player_id, biotope_id)
    last = latest_for_biotope(player_id, biotope_id)

    if owner? do
      budget_from_last(last)
    else
      %{allowed?: false, owner?: false, retry_at: nil, remaining_seconds: 0, last_kind: nil}
    end
  end

  @spec apply(map(), binary(), map()) ::
          {:ok, %{payload: map(), tick: non_neg_integer()}}
          | {:error,
             :forbidden
             | :budget_locked
             | :invalid_phase
             | :no_lineage_host
             | :persistence_failed
             | atom()}
  def apply(player_profile, biotope_id, command)
      when is_map(player_profile) and is_binary(biotope_id) and is_map(command) do
    case status(player_profile.id, biotope_id) do
      %{owner?: false} ->
        {:error, :forbidden}

      %{allowed?: false} ->
        {:error, :budget_locked}

      _ ->
        enriched =
          command
          |> Map.put(:actor_player_id, player_profile.id)
          |> Map.put(:actor_name, player_profile.display_name)

        with {:ok, result} <- BiotopeServer.apply_intervention(biotope_id, enriched),
             :ok <-
               record_execution(execution_attrs(player_profile.id, biotope_id, enriched, result)) do
          {:ok, result}
        else
          {:error, %Changeset{}} ->
            {:error, :persistence_failed}

          other ->
            other
        end
    end
  end

  @spec record_execution(map()) :: :ok | {:error, Ecto.Changeset.t()}
  def record_execution(attrs) when is_map(attrs) do
    %InterventionLog{}
    |> InterventionLog.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, _entry} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp latest_for_biotope(player_id, biotope_id) do
    Repo.one(
      from row in InterventionLog,
        where: row.player_id == ^player_id and row.biotope_id == ^biotope_id,
        order_by: [desc: row.executed_at],
        limit: 1
    )
  end

  defp budget_from_last(nil) do
    %{allowed?: true, owner?: true, retry_at: nil, remaining_seconds: 0, last_kind: nil}
  end

  defp budget_from_last(%InterventionLog{} = last) do
    retry_at = DateTime.add(last.executed_at, @budget_cooldown_seconds, :second)

    case DateTime.compare(DateTime.utc_now(), retry_at) do
      :lt ->
        remaining = max(DateTime.diff(retry_at, DateTime.utc_now(), :second), 0)

        %{
          allowed?: false,
          owner?: true,
          retry_at: retry_at,
          remaining_seconds: remaining,
          last_kind: last.kind
        }

      _ ->
        %{allowed?: true, owner?: true, retry_at: nil, remaining_seconds: 0, last_kind: last.kind}
    end
  end

  defp execution_attrs(player_id, biotope_id, command, %{payload: payload}) do
    %{
      player_id: player_id,
      biotope_id: biotope_id,
      kind: command.kind |> to_string(),
      scope: command |> Map.get(:scope, :phase) |> to_string(),
      phase_name: phase_name_value(command),
      payload: stringify_keys(payload),
      occurred_at_tick: Map.get(payload, :tick) || Map.get(payload, "tick"),
      executed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    }
  end

  defp phase_name_value(command) do
    case Map.get(command, :phase_name) do
      phase_name when is_atom(phase_name) -> Atom.to_string(phase_name)
      phase_name when is_binary(phase_name) -> phase_name
      _ -> nil
    end
  end

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
