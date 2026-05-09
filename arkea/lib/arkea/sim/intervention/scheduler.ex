defmodule Arkea.Sim.Intervention.Scheduler do
  @moduledoc """
  Orchestration layer that schedules `Arkea.Sim.Intervention` commands
  at a *future tick* of a target biotope (Phase 32 / orchestration —
  closes the `:scheduled_dosing` deferred-from-Phase-27 marker).

  The Phase-27 `Intervention.apply/2` API runs commands
  *immediately* against a `BiotopeState`. Real experimental
  protocols often need timed schedules (e.g. "add a 30 µg/mL
  beta-lactam pulse at tick 200, then repeat at tick 400") that
  sit outside the simulation tick loop. This module is the thin
  Oban wrapper that resolves that gap:

    * `schedule/2` validates a "scheduled dose" plan
      (target biotope + intervention command + due-tick) and
      enqueues it as an Oban job in the `:scheduled_dosing` queue.
    * The job's worker (`ScheduledDosingWorker`) waits until the
      target biotope's current tick is `>= due_tick` and then
      applies the intervention via `BiotopeServer.apply_intervention/2`.
    * If the biotope is still behind the due-tick at execution
      time, the worker re-enqueues itself with a short delay
      (poll-style; for Phase-32 v1 the polling is a 30-second
      back-off).

  ## Why Oban + not a GenServer timer

  Oban gives us free durability (jobs survive node restarts) and a
  uniform scheduling primitive that the rest of the persistence
  pipeline already uses (cf. `SnapshotWorker`). The trade-off is
  that scheduling is *coarse* — Oban polls its DB at second
  resolution; we don't dispatch on every tick. For the player-
  facing "schedule a dose at tick N of biotope X" workflow this
  resolution is more than sufficient.

  ## v1 limitations

    * **Single-shot only**: `schedule/2` enqueues one command per
      call. Repeating doses (e.g. "every N ticks") are
      out-of-scope; the player can chain calls or a future
      track can layer recurrence on top.
    * **Tick-based, not wall-clock-based**: due-tick is a
      simulation tick, not a `DateTime`. Mapping wall-clock to
      ticks lives upstream in the UI consumer.
    * **No cancellation API yet**: callers can leverage
      `Oban.cancel_job/1` directly with the returned job id;
      a wrapper `cancel/1` is straightforward when the UI
      consumer wants it.
  """

  alias Arkea.Sim.Intervention
  alias Arkea.Sim.Intervention.ScheduledDosingWorker

  @type schedule_input :: %{
          required(:biotope_id) => binary(),
          required(:due_tick) => non_neg_integer(),
          required(:command) => Intervention.command()
        }

  @doc """
  Schedule an intervention command to fire when the target biotope
  reaches `due_tick`. Returns the inserted Oban job (`{:ok, job}`)
  or a validation error (`{:error, reason}`).

  ## Required keys

    * `:biotope_id` — the target `BiotopeState.id`.
    * `:due_tick` — the simulation tick at which the intervention
      should fire (`>= 0`).
    * `:command` — a map shaped like `Intervention.apply/2`'s
      command argument (must include `:kind`, `:actor_player_id`,
      `:actor_name`).
  """
  @spec schedule(schedule_input()) :: {:ok, Oban.Job.t()} | {:error, atom()}
  def schedule(%{biotope_id: biotope_id, due_tick: due_tick, command: command} = _input)
      when is_binary(biotope_id) and is_integer(due_tick) and due_tick >= 0 and is_map(command) do
    with :ok <- validate_command(command) do
      args = %{
        "biotope_id" => biotope_id,
        "due_tick" => due_tick,
        "command" => stringify_command(command)
      }

      ScheduledDosingWorker.new(args)
      |> Arkea.Oban.insert()
    end
  end

  def schedule(_), do: {:error, :invalid_input}

  defp validate_command(command) do
    kind = Map.get(command, :kind)

    cond do
      not (is_atom(kind) and not is_nil(kind)) ->
        {:error, :invalid_command_kind}

      not is_binary(Map.get(command, :actor_player_id)) ->
        {:error, :invalid_actor_player_id}

      not is_binary(Map.get(command, :actor_name)) ->
        {:error, :invalid_actor_name}

      true ->
        :ok
    end
  end

  @doc """
  Convert an `Intervention.command()` map (atom-keyed, may carry
  atoms in nested values like `:phase_name`) to an Oban-safe
  string-keyed map. Atoms are stringified so the job can survive
  JSON serialisation; the worker rebuilds atoms on dequeue.
  """
  @spec stringify_command(map()) :: map()
  def stringify_command(command) when is_map(command) do
    command
    |> Map.new(fn {k, v} -> {to_string(k), serialise_value(v)} end)
  end

  defp serialise_value(v) when is_atom(v) and not is_boolean(v) and not is_nil(v),
    do: %{"__atom__" => Atom.to_string(v)}

  defp serialise_value(v) when is_map(v) and not is_struct(v), do: stringify_command(v)
  defp serialise_value(v) when is_list(v), do: Enum.map(v, &serialise_value/1)
  defp serialise_value(v), do: v

  @doc """
  Inverse of `stringify_command/1`. Rebuilds the atom-keyed
  command map (with atom values restored) from the Oban-stored
  string-keyed shape.
  """
  @spec atomize_command(map()) :: map()
  def atomize_command(command) when is_map(command) do
    command
    |> Enum.map(fn {k, v} -> {atomize_key(k), deserialise_value(v)} end)
    |> Map.new()
  end

  defp atomize_key(k) when is_binary(k), do: String.to_existing_atom(k)
  defp atomize_key(k), do: k

  defp deserialise_value(%{"__atom__" => name}) when is_binary(name),
    do: String.to_existing_atom(name)

  defp deserialise_value(v) when is_map(v) and not is_struct(v), do: atomize_command(v)
  defp deserialise_value(v) when is_list(v), do: Enum.map(v, &deserialise_value/1)
  defp deserialise_value(v), do: v
end
