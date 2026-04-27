defmodule Arkea.Ecology.Biotope do
  @moduledoc """
  A biotope is a node in the world graph (DESIGN.md Block 10) and the
  authoritative unit of simulation owned by `Arkea.Ecology.Biotope.Server`
  (Phase 2).

  Each biotope:

  - belongs to one of 8 archetypes (Block 10);
  - has 2–3 phases (Block 12) typed for its archetype;
  - sits at planar coordinates `(x, y)` and is connected to neighbours by
    UUID — the graph topology lives outside this struct (Phase 8);
  - is owned by exactly one player (`owner_player_id`) or wild (`nil`).

  Phase 1 only models the data structure; the tick engine arrives in Phase 2.
  """

  use TypedStruct

  alias Arkea.Ecology.Phase

  @archetypes [
    :oligotrophic_lake,
    :eutrophic_pond,
    :marine_sediment,
    :hydrothermal_vent,
    :acid_mine_drainage,
    :methanogenic_bog,
    :mesophilic_soil,
    :saline_estuary
  ]

  @type archetype ::
          :oligotrophic_lake
          | :eutrophic_pond
          | :marine_sediment
          | :hydrothermal_vent
          | :acid_mine_drainage
          | :methanogenic_bog
          | :mesophilic_soil
          | :saline_estuary

  typedstruct enforce: true do
    field :id, binary()
    field :archetype, archetype()
    field :x, float()
    field :y, float()
    field :zone, atom()
    field :owner_player_id, binary() | nil, default: nil
    field :phases, [Phase.t()]
    field :neighbor_ids, [binary()], default: []
  end

  @doc "All 8 supported archetypes in canonical order."
  @spec archetypes() :: [archetype()]
  def archetypes, do: @archetypes

  @doc "True when `atom` is one of the 8 archetypes."
  @spec valid_archetype?(term()) :: boolean()
  def valid_archetype?(atom) when is_atom(atom), do: atom in @archetypes
  def valid_archetype?(_), do: false

  @doc """
  Build a biotope.

  ## Required

    * `archetype` — one of `archetypes/0`
    * `coords` — `{x, y}` tuple of floats

  ## Options

    * `:zone` — atom, default derived from archetype
    * `:owner_player_id` — binary or `nil` (default `nil`, wild)
    * `:phases` — explicit list of `Phase.t()`; defaults to `default_phases/1`
    * `:neighbor_ids` — list of UUIDs, default `[]`

  Pure. Raises on invalid input.
  """
  @spec new(archetype(), {float(), float()}, keyword()) :: t()
  def new(archetype, {x, y}, opts \\ [])
      when is_atom(archetype) and is_float(x) and is_float(y) do
    unless valid_archetype?(archetype) do
      raise ArgumentError, "unknown archetype: #{inspect(archetype)}"
    end

    biotope = %__MODULE__{
      id: Arkea.UUID.v4(),
      archetype: archetype,
      x: x,
      y: y,
      zone: Keyword.get(opts, :zone, default_zone(archetype)),
      owner_player_id: Keyword.get(opts, :owner_player_id),
      phases: Keyword.get_lazy(opts, :phases, fn -> default_phases(archetype) end),
      neighbor_ids: Keyword.get(opts, :neighbor_ids, [])
    }

    case validate(biotope) do
      :ok -> biotope
      {:error, reason} -> raise ArgumentError, "invalid biotope: #{reason}"
    end
  end

  @doc """
  Default phases for an archetype (Block 12).

  Every archetype declares 2 or 3 phases with environmental defaults that
  match its profile (Block 10). These are seeds; per-instance variation is
  introduced by sampling around the centroid in later phases.
  """
  @spec default_phases(archetype()) :: [Phase.t()]
  def default_phases(:oligotrophic_lake) do
    [
      Phase.new(:surface,
        temperature: 18.0,
        ph: 7.2,
        osmolarity: 50.0,
        dilution_rate: 0.05
      ),
      Phase.new(:water_column,
        temperature: 12.0,
        ph: 7.4,
        osmolarity: 50.0,
        dilution_rate: 0.03
      )
    ]
  end

  def default_phases(:eutrophic_pond) do
    [
      Phase.new(:surface,
        temperature: 22.0,
        ph: 7.0,
        osmolarity: 80.0,
        dilution_rate: 0.04
      ),
      Phase.new(:water_column,
        temperature: 18.0,
        ph: 6.8,
        osmolarity: 80.0,
        dilution_rate: 0.02
      ),
      Phase.new(:sediment,
        temperature: 14.0,
        ph: 6.5,
        osmolarity: 100.0,
        dilution_rate: 0.005
      )
    ]
  end

  def default_phases(:marine_sediment) do
    [
      Phase.new(:interface,
        temperature: 8.0,
        ph: 7.8,
        osmolarity: 1100.0,
        dilution_rate: 0.01
      ),
      Phase.new(:bulk_sediment,
        temperature: 6.0,
        ph: 7.6,
        osmolarity: 1100.0,
        dilution_rate: 0.001
      )
    ]
  end

  def default_phases(:hydrothermal_vent) do
    [
      Phase.new(:vent_core,
        temperature: 75.0,
        ph: 6.0,
        osmolarity: 1100.0,
        dilution_rate: 0.15
      ),
      Phase.new(:mixing_zone,
        temperature: 35.0,
        ph: 6.5,
        osmolarity: 700.0,
        dilution_rate: 0.08
      )
    ]
  end

  def default_phases(:acid_mine_drainage) do
    [
      Phase.new(:acid_water,
        temperature: 18.0,
        ph: 3.0,
        osmolarity: 200.0,
        dilution_rate: 0.05
      ),
      Phase.new(:mineral_surface,
        temperature: 16.0,
        ph: 3.2,
        osmolarity: 200.0,
        dilution_rate: 0.005
      )
    ]
  end

  def default_phases(:methanogenic_bog) do
    [
      Phase.new(:surface_oxic,
        temperature: 12.0,
        ph: 5.5,
        osmolarity: 60.0,
        dilution_rate: 0.02
      ),
      Phase.new(:peat_core,
        temperature: 8.0,
        ph: 5.0,
        osmolarity: 60.0,
        dilution_rate: 0.001
      )
    ]
  end

  def default_phases(:mesophilic_soil) do
    [
      Phase.new(:aerated_pore,
        temperature: 20.0,
        ph: 6.8,
        osmolarity: 150.0,
        dilution_rate: 0.04
      ),
      Phase.new(:wet_clump,
        temperature: 18.0,
        ph: 6.5,
        osmolarity: 200.0,
        dilution_rate: 0.01
      ),
      Phase.new(:soil_water,
        temperature: 19.0,
        ph: 6.7,
        osmolarity: 100.0,
        dilution_rate: 0.06
      )
    ]
  end

  def default_phases(:saline_estuary) do
    [
      Phase.new(:freshwater_layer,
        temperature: 16.0,
        ph: 7.2,
        osmolarity: 100.0,
        dilution_rate: 0.10
      ),
      Phase.new(:mixing_zone,
        temperature: 17.0,
        ph: 7.6,
        osmolarity: 600.0,
        dilution_rate: 0.08
      ),
      Phase.new(:marine_layer,
        temperature: 18.0,
        ph: 8.0,
        osmolarity: 1100.0,
        dilution_rate: 0.06
      )
    ]
  end

  @doc "Lookup a phase by name. Returns `nil` if missing."
  @spec phase(t(), atom()) :: Phase.t() | nil
  def phase(%__MODULE__{phases: phases}, name) when is_atom(name) do
    Enum.find(phases, fn %Phase{name: n} -> n == name end)
  end

  @doc """
  Apply a pure update function to one named phase. Returns the biotope
  with the updated phase substituted. Raises if the phase is not present.
  """
  @spec update_phase(t(), atom(), (Phase.t() -> Phase.t())) :: t()
  def update_phase(%__MODULE__{phases: phases} = biotope, name, updater)
      when is_atom(name) and is_function(updater, 1) do
    case Enum.find_index(phases, fn %Phase{name: n} -> n == name end) do
      nil -> raise ArgumentError, "phase #{inspect(name)} not present in biotope"
      index -> %{biotope | phases: List.update_at(phases, index, updater)}
    end
  end

  @doc """
  Union of all `lineage_ids` across all phases.

  Useful for cap enforcement and pruning at the biotope level.
  """
  @spec all_lineage_ids(t()) :: MapSet.t(binary())
  def all_lineage_ids(%__MODULE__{phases: phases}) do
    Enum.reduce(phases, MapSet.new(), fn %Phase{lineage_ids: ids}, acc ->
      MapSet.union(acc, ids)
    end)
  end

  @doc "True when the biotope has no owner."
  @spec wild?(t()) :: boolean()
  def wild?(%__MODULE__{owner_player_id: nil}), do: true
  def wild?(%__MODULE__{}), do: false

  @doc "True when the biotope satisfies its structural invariants."
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = biotope), do: validate(biotope) == :ok
  def valid?(_), do: false

  @doc "Validation with reason."
  @spec validate(t()) :: :ok | {:error, atom()}
  def validate(%__MODULE__{} = biotope) do
    Enum.find_value(validation_checks(biotope), :ok, fn {check, error_atom} ->
      if check.(), do: false, else: {:error, error_atom}
    end)
  end

  def validate(_), do: {:error, :not_a_biotope}

  # ----------------------------------------------------------------------
  # Private helpers

  defp validation_checks(biotope) do
    [
      {fn -> is_binary(biotope.id) end, :invalid_id},
      {fn -> valid_archetype?(biotope.archetype) end, :invalid_archetype},
      {fn -> is_float(biotope.x) and is_float(biotope.y) end, :invalid_coords},
      {fn -> is_atom(biotope.zone) end, :invalid_zone},
      {fn -> biotope.owner_player_id == nil or is_binary(biotope.owner_player_id) end,
       :invalid_owner},
      {fn -> length(biotope.phases) in 2..3 end, :invalid_phase_count},
      {fn -> Enum.all?(biotope.phases, &Phase.valid?/1) end, :invalid_phase},
      {fn -> phase_names_unique?(biotope.phases) end, :duplicate_phase_names},
      {fn -> valid_neighbor_ids?(biotope.neighbor_ids) end, :invalid_neighbor_ids}
    ]
  end

  defp phase_names_unique?(phases) do
    names = Enum.map(phases, & &1.name)
    length(names) == length(Enum.uniq(names))
  end

  defp valid_neighbor_ids?(ids) when is_list(ids), do: Enum.all?(ids, &is_binary/1)
  defp valid_neighbor_ids?(_), do: false

  defp default_zone(:oligotrophic_lake), do: :lacustrine_zone
  defp default_zone(:eutrophic_pond), do: :swampy_zone
  defp default_zone(:marine_sediment), do: :marine_zone
  defp default_zone(:hydrothermal_vent), do: :hydrothermal_zone
  defp default_zone(:acid_mine_drainage), do: :hydrothermal_zone
  defp default_zone(:methanogenic_bog), do: :swampy_zone
  defp default_zone(:mesophilic_soil), do: :soil_zone
  defp default_zone(:saline_estuary), do: :coastal_zone
end
