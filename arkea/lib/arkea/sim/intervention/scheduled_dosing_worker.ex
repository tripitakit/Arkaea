defmodule Arkea.Sim.Intervention.ScheduledDosingWorker do
  @moduledoc """
  Oban worker that fires a scheduled `Intervention.apply/2` once
  the target biotope reaches `due_tick` (Phase 32 / orchestration).

  The worker is enqueued by
  `Arkea.Sim.Intervention.Scheduler.schedule/1`. On `perform/1`:

    1. Looks up the biotope's current tick via
       `BiotopeServer.get_state/1`.
    2. If `tick_count >= due_tick` → applies the intervention via
       `BiotopeServer.apply_intervention/2` and returns `:ok`.
    3. Otherwise → the job is *snoozed* for `@poll_interval`
       seconds via `{:snooze, n}` and Oban re-runs it. The
       implicit polling cadence is therefore at-most-once-per-
       `@poll_interval` regardless of how far behind the biotope
       is, keeping load proportional to the number of pending
       schedules rather than to wall-clock time.

  Special outcomes:

    * `BiotopeServer` not found (e.g. the biotope was archived
      before the dose fired) → `{:cancel, :biotope_not_running}`,
      Oban marks the job as cancelled.
    * `Intervention.apply/2` returns `{:error, reason}` →
      propagated as `{:error, reason}` so Oban records the
      failure; the worker's `max_attempts: 3` lets transient
      errors retry, but a deterministic `{:error, :invalid_phase}`
      will exhaust attempts cleanly.
  """

  use Oban.Worker,
    queue: :scheduled_dosing,
    max_attempts: 3,
    unique: [period: 60, fields: [:worker, :args]]

  alias Arkea.Sim.Biotope.Server, as: BiotopeServer
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.Intervention.Scheduler

  # Seconds to wait between polls when the biotope is still
  # behind the due-tick. 30s gives "scheduled at tick 200" jobs
  # enough resolution under Arkea's default tick interval (2s in
  # production, 600s in test) without over-polling Oban.
  @poll_interval 30

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    biotope_id = Map.fetch!(args, "biotope_id")
    due_tick = Map.fetch!(args, "due_tick")
    command_raw = Map.fetch!(args, "command")

    case fetch_state(biotope_id) do
      :not_running ->
        {:cancel, :biotope_not_running}

      {:ok, %BiotopeState{} = state} ->
        if state.tick_count >= due_tick do
          fire_intervention(biotope_id, command_raw)
        else
          {:snooze, @poll_interval}
        end
    end
  end

  defp fetch_state(biotope_id) do
    case Registry.lookup(Arkea.Sim.Registry, {:biotope, biotope_id}) do
      [{pid, _}] when is_pid(pid) ->
        if Process.alive?(pid) do
          {:ok, BiotopeServer.get_state(biotope_id)}
        else
          :not_running
        end

      _ ->
        :not_running
    end
  rescue
    _ -> :not_running
  end

  defp fire_intervention(biotope_id, command_raw) do
    command = Scheduler.atomize_command(command_raw)

    case BiotopeServer.apply_intervention(biotope_id, command) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
