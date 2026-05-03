defmodule Arkea.Game.SeedLibrary do
  @moduledoc """
  Player-side seed library (Phase 19 — DESIGN.md Block 8 / Community Mode).

  Each `entry` in a library captures one designed Arkeon seed:

      %{id, name, genome, description, created_at}

  The `id` is a stable per-entry handle that flows through to
  `Lineage.original_seed_id` when the seed is inoculated into a
  biotope, enabling cladistic analytics and community-mode
  bookkeeping.

  ## Phase 19 scope

  This module ships a **pure in-memory** library. The Ecto-backed
  persistence schema (`player_seeds` table — see
  `BIOLOGICAL-MODEL-REVIEW.md` Phase 19) is reserved for the runtime
  PR that wires a `Phoenix.LiveView` Seed Lab page; the simulation
  core only needs the value type + the validation invariants.

  The library is bounded at `@max_size` entries (default 12 per
  player) — a conservative cap that lets a player iterate on
  designs without turning the seed lab into a deck-building
  optimiser.
  """

  alias Arkea.Genome

  @max_size 12

  @typedoc "One entry in the library."
  @type entry :: %{
          id: binary(),
          name: binary(),
          genome: Genome.t(),
          description: binary(),
          created_at: integer()
        }

  @typedoc "The library itself: a map from entry id to entry."
  @type t :: %{binary() => entry()}

  @doc "Create an empty library."
  @spec new() :: t()
  def new, do: %{}

  @doc "Maximum number of entries allowed in a library."
  @spec max_size() :: pos_integer()
  def max_size, do: @max_size

  @doc """
  Add a designed seed to a library.

  Returns:
    - `{:ok, library, entry}` when the seed is accepted;
    - `{:error, :library_full}` when the library is at `@max_size`;
    - `{:error, :duplicate_name}` when an entry with the same name
      already exists.
  """
  @spec save(t(), Genome.t(), keyword()) ::
          {:ok, t(), entry()} | {:error, :library_full | :duplicate_name | :invalid_genome}
  def save(%{} = library, %Genome{} = genome, opts \\ []) do
    name = Keyword.fetch!(opts, :name) |> to_string()

    cond do
      not Genome.valid?(genome) ->
        {:error, :invalid_genome}

      map_size(library) >= @max_size ->
        {:error, :library_full}

      Enum.any?(library, fn {_id, entry} -> entry.name == name end) ->
        {:error, :duplicate_name}

      true ->
        entry = %{
          id: Arkea.UUID.v4(),
          name: name,
          genome: genome,
          description: Keyword.get(opts, :description, ""),
          created_at: Keyword.get_lazy(opts, :created_at, fn -> System.system_time(:second) end)
        }

        {:ok, Map.put(library, entry.id, entry), entry}
    end
  end

  @doc "Remove an entry by id. Pure no-op when the id is absent."
  @spec delete(t(), binary()) :: t()
  def delete(%{} = library, id) when is_binary(id), do: Map.delete(library, id)

  @doc "Return all entries in arbitrary order."
  @spec entries(t()) :: [entry()]
  def entries(%{} = library), do: Map.values(library)

  @doc "Look up an entry by id. `nil` if absent."
  @spec fetch(t(), binary()) :: entry() | nil
  def fetch(%{} = library, id) when is_binary(id), do: Map.get(library, id)
end
