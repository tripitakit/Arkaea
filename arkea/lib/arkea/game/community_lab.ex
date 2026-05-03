defmodule Arkea.Game.CommunityLab do
  @moduledoc """
  Community Mode multi-seed provisioning (Phase 19 — DESIGN.md
  Block 8 / Community Mode).

  Wraps the Seed Lab single-seed flow with the multi-seed founder
  logic that lets a player inoculate up to `@max_community_seeds`
  distinct designs into the same biotope simultaneously. Each seed
  becomes an independent founder lineage tagged with the seed's id
  via `Lineage.original_seed_id`; the tag flows through every
  reproductive event so the audit log can reconstruct community
  dynamics later.

  ## Pure module

  This module is intentionally pure: no DB writes, no GenServer
  calls. Callers (Phoenix LiveView Seed Lab tab) own the orchestration
  with `Arkea.Game.SeedLibrary`, `Arkea.Persistence`, and the
  biotope server. `provision_community/3` returns ready-to-insert
  founder lineages and a `:community_provisioned` event payload.

  ## Anti-deck-building gating

  The hard cap `@max_community_seeds = 3` and the pre-condition
  that all seeds carry distinct `id`s prevent the trivial
  power-stacking failure mode. Phase 19 progression milestones
  (Endurance / Mutator emergence / Successful HGT) are tracked
  outside this module — see `Arkea.Game.PlayerProgression` (Phase 19
  follow-up).
  """

  alias Arkea.Ecology.Lineage
  alias Arkea.Game.SeedLibrary

  @max_community_seeds 3

  @typedoc """
  Result of a successful provisioning: a list of founder lineages
  plus a `:community_provisioned` audit-event payload.
  """
  @type provisioning_result :: %{
          founders: [Lineage.t()],
          event: %{type: atom(), payload: map()}
        }

  @doc "Maximum number of seeds that can co-found a biotope."
  @spec max_community_seeds() :: pos_integer()
  def max_community_seeds, do: @max_community_seeds

  @doc """
  Provision a multi-seed community in a single biotope.

  ## Arguments

    * `seed_entries` — list of `Arkea.Game.SeedLibrary.entry/0`
      values. Each entry contributes one founder lineage. The list
      length must be in `1..@max_community_seeds` and must contain
      no duplicate `:id`.
    * `phase_name` — the phase to seed all founders into.
    * `opts` — keyword:
        - `:per_founder_abundance` (default 100) — initial cell
          count for each founder in the seeded phase.
        - `:tick` (default 0) — `created_at_tick` for the founders.
        - `:biotope_id` (default `nil`) — included in the audit
          event payload so downstream telemetry knows which biotope
          received the inoculation.

  ## Returns

    * `{:ok, %{founders: [...], event: %{...}}}` on success;
    * `{:error, :empty_seeds}` when no seeds are passed;
    * `{:error, :too_many_seeds}` when the cap is exceeded;
    * `{:error, :duplicate_seed_id}` when two entries share an id.
  """
  @spec provision_community([SeedLibrary.entry()], atom(), keyword()) ::
          {:ok, provisioning_result()}
          | {:error, :empty_seeds | :too_many_seeds | :duplicate_seed_id}
  def provision_community(seed_entries, phase_name, opts \\ [])
      when is_list(seed_entries) and is_atom(phase_name) do
    cond do
      seed_entries == [] ->
        {:error, :empty_seeds}

      length(seed_entries) > @max_community_seeds ->
        {:error, :too_many_seeds}

      duplicate_id?(seed_entries) ->
        {:error, :duplicate_seed_id}

      true ->
        do_provision(seed_entries, phase_name, opts)
    end
  end

  @doc """
  Build a single founder lineage from a `SeedLibrary.entry/0`,
  tagged with the entry's id as `original_seed_id`.

  Pure. Useful for callers that build community founders incrementally
  (e.g. via streaming UI events) rather than in a single
  `provision_community/3` call.
  """
  @spec build_founder(SeedLibrary.entry(), atom(), keyword()) :: Lineage.t()
  def build_founder(%{id: id, genome: genome}, phase_name, opts \\ [])
      when is_binary(id) and is_atom(phase_name) and is_list(opts) do
    abundance = Keyword.get(opts, :per_founder_abundance, 100)
    tick = Keyword.get(opts, :tick, 0)

    Lineage.new_founder(genome, %{phase_name => abundance}, tick, original_seed_id: id)
  end

  # ---------------------------------------------------------------------------
  # Private

  defp duplicate_id?(seed_entries) do
    ids = Enum.map(seed_entries, & &1.id)
    length(ids) != length(Enum.uniq(ids))
  end

  defp do_provision(seed_entries, phase_name, opts) do
    biotope_id = Keyword.get(opts, :biotope_id)

    founders =
      Enum.map(seed_entries, fn entry ->
        build_founder(entry, phase_name, opts)
      end)

    event = build_community_event(seed_entries, founders, phase_name, biotope_id, opts)

    {:ok, %{founders: founders, event: event}}
  end

  defp build_community_event(seed_entries, founders, phase_name, biotope_id, opts) do
    payload = %{
      seed_ids: Enum.map(seed_entries, & &1.id),
      seed_names: Enum.map(seed_entries, & &1.name),
      founder_lineage_ids: Enum.map(founders, & &1.id),
      phase_name: Atom.to_string(phase_name),
      biotope_id: biotope_id,
      tick: Keyword.get(opts, :tick, 0)
    }

    %{type: :community_provisioned, payload: payload}
  end
end
