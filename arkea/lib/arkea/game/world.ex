defmodule Arkea.Game.World do
  @moduledoc """
  Lightweight runtime read model for the prototype world shell.

  Reads active biotopes from the Registry/GenServers without introducing a
  separate process or shared mutable cache. This keeps the current Phase 8/10
  runtime boundaries intact while giving the UI a macroscala overview.
  """

  alias Arkea.Game.PrototypePlayer
  alias Arkea.Sim.Biotope.Server, as: BiotopeServer
  alias Arkea.Sim.BiotopeState
  alias Arkea.Sim.SeedScenario

  @fallback_positions %{
    oligotrophic_lake: {18.0, 22.0},
    eutrophic_pond: {40.0, 38.0},
    mesophilic_soil: {72.0, 24.0},
    methanogenic_bog: {24.0, 66.0},
    saline_estuary: {86.0, 56.0},
    marine_sediment: {90.0, 76.0},
    hydrothermal_vent: {58.0, 82.0},
    acid_mine_drainage: {68.0, 68.0}
  }

  @node_clearance_x 19.0
  @node_clearance_y 11.5
  @map_bounds_x {11.0, 89.0}
  @map_bounds_y {12.0, 88.0}
  @layout_passes 18

  @type ownership :: :player_controlled | :wild | :foreign_controlled

  @type biotope_summary :: %{
          id: binary(),
          archetype: atom(),
          zone: atom(),
          owner_player_id: binary() | nil,
          ownership: ownership(),
          tick_count: non_neg_integer(),
          total_population: non_neg_integer(),
          lineage_count: non_neg_integer(),
          phase_count: non_neg_integer(),
          neighbor_ids: [binary()],
          display_x: float(),
          display_y: float(),
          is_demo: boolean()
        }

  @spec overview(binary()) :: %{
          biotopes: [biotope_summary()],
          edges: [map()],
          active_count: non_neg_integer(),
          owned_count: non_neg_integer(),
          wild_count: non_neg_integer(),
          edge_count: non_neg_integer(),
          max_tick: non_neg_integer(),
          archetype_breakdown: [%{archetype: atom(), count: non_neg_integer()}],
          focus_biotope_id: binary() | nil
        }
  def overview(player_id \\ PrototypePlayer.id()) do
    biotopes =
      player_id
      |> list_biotopes()
      |> resolve_node_collisions()

    edges = build_edges(biotopes)

    %{
      biotopes: biotopes,
      edges: edges,
      active_count: length(biotopes),
      owned_count: Enum.count(biotopes, &(&1.ownership == :player_controlled)),
      wild_count: Enum.count(biotopes, &(&1.ownership == :wild)),
      edge_count: length(edges),
      max_tick: Enum.max(Enum.map(biotopes, & &1.tick_count), fn -> 0 end),
      archetype_breakdown: archetype_breakdown(biotopes),
      focus_biotope_id: default_focus_id(biotopes)
    }
  end

  @spec list_biotopes(binary()) :: [biotope_summary()]
  def list_biotopes(player_id \\ PrototypePlayer.id()) do
    running_ids()
    |> Enum.map(&safe_summary(&1, player_id))
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&sort_key/1)
  end

  @spec template_position(atom()) :: {float(), float()}
  def template_position(archetype) when is_atom(archetype) do
    Map.get(@fallback_positions, archetype, {50.0, 50.0})
  end

  @spec spawn_coords(atom()) :: {float(), float()}
  def spawn_coords(archetype) when is_atom(archetype) do
    {base_x, base_y} = template_position(archetype)
    sibling_count = Enum.count(list_biotopes(), &(&1.archetype == archetype))
    col = rem(sibling_count, 3) - 1
    row = div(sibling_count, 3)

    {
      clamp(base_x + col * 5.5, 10.0, 90.0),
      clamp(base_y + row * 5.0, 12.0, 88.0)
    }
  end

  @spec running_ids() :: [binary()]
  def running_ids do
    Registry.select(Arkea.Sim.Registry, [{{{:biotope, :"$1"}, :_, :_}, [], [:"$1"]}])
    |> Enum.sort()
  end

  defp default_focus_id([]), do: nil

  defp default_focus_id(biotopes) do
    ids = MapSet.new(biotopes, & &1.id)
    demo_id = SeedScenario.default_biotope_id()

    if MapSet.member?(ids, demo_id) do
      demo_id
    else
      hd(biotopes).id
    end
  end

  defp safe_summary(id, player_id) do
    state = BiotopeServer.get_state(id)
    {display_x, display_y} = display_coords(state)

    %{
      id: state.id,
      archetype: state.archetype,
      zone: resolved_zone(state),
      owner_player_id: state.owner_player_id,
      ownership: ownership_for(state.owner_player_id, player_id),
      tick_count: state.tick_count,
      total_population: BiotopeState.total_abundance(state),
      lineage_count: length(state.lineages),
      phase_count: length(state.phases),
      neighbor_ids: state.neighbor_ids,
      display_x: display_x,
      display_y: display_y,
      is_demo: state.id == SeedScenario.default_biotope_id()
    }
  rescue
    _ -> nil
  end

  defp sort_key(summary) do
    {
      ownership_rank(summary.ownership),
      (summary.is_demo && 0) || 1,
      Atom.to_string(summary.archetype),
      summary.id
    }
  end

  defp ownership_rank(:player_controlled), do: 0
  defp ownership_rank(:wild), do: 1
  defp ownership_rank(:foreign_controlled), do: 2

  defp ownership_for(owner_player_id, player_id) when owner_player_id == player_id,
    do: :player_controlled

  defp ownership_for(nil, _player_id), do: :wild
  defp ownership_for(_owner_player_id, _player_id), do: :foreign_controlled

  defp display_coords(%BiotopeState{x: x, y: y, archetype: archetype, id: id}) do
    if x != 0.0 or y != 0.0 do
      {clamp(x, 8.0, 92.0), clamp(y, 10.0, 90.0)}
    else
      {base_x, base_y} = template_position(archetype)
      x_offset = (rem(:erlang.phash2(id), 9) - 4) * 1.6
      y_offset = (rem(:erlang.phash2({id, :y}), 7) - 3) * 1.4
      {clamp(base_x + x_offset, 8.0, 92.0), clamp(base_y + y_offset, 10.0, 90.0)}
    end
  end

  defp resolved_zone(%BiotopeState{zone: :unassigned, archetype: archetype}),
    do: zone_for(archetype)

  defp resolved_zone(%BiotopeState{zone: zone}), do: zone

  defp zone_for(:oligotrophic_lake), do: :lacustrine_zone
  defp zone_for(:eutrophic_pond), do: :swampy_zone
  defp zone_for(:marine_sediment), do: :marine_zone
  defp zone_for(:hydrothermal_vent), do: :hydrothermal_zone
  defp zone_for(:acid_mine_drainage), do: :hydrothermal_zone
  defp zone_for(:methanogenic_bog), do: :swampy_zone
  defp zone_for(:mesophilic_soil), do: :soil_zone
  defp zone_for(:saline_estuary), do: :coastal_zone

  defp build_edges(biotopes) do
    by_id = Map.new(biotopes, &{&1.id, &1})

    {_seen, edges} =
      Enum.reduce(biotopes, {MapSet.new(), []}, fn biotope, {seen, acc} ->
        Enum.reduce(biotope.neighbor_ids, {seen, acc}, fn neighbor_id, {seen_acc, edge_acc} ->
          case Map.get(by_id, neighbor_id) do
            nil ->
              {seen_acc, edge_acc}

            target ->
              key =
                case biotope.id <= target.id do
                  true -> {biotope.id, target.id}
                  false -> {target.id, biotope.id}
                end

              if MapSet.member?(seen_acc, key) do
                {seen_acc, edge_acc}
              else
                edge = %{
                  id: "#{elem(key, 0)}:#{elem(key, 1)}",
                  x1: biotope.display_x,
                  y1: biotope.display_y,
                  x2: target.display_x,
                  y2: target.display_y
                }

                {MapSet.put(seen_acc, key), [edge | edge_acc]}
              end
          end
        end)
      end)

    Enum.reverse(edges)
  end

  defp archetype_breakdown(biotopes) do
    biotopes
    |> Enum.group_by(& &1.archetype)
    |> Enum.map(fn {archetype, members} -> %{archetype: archetype, count: length(members)} end)
    |> Enum.sort_by(&{&1.count * -1, Atom.to_string(&1.archetype)})
  end

  defp clamp(value, lo, hi) when is_number(value) do
    value
    |> Kernel.max(lo)
    |> Kernel.min(hi)
    |> Kernel.*(1.0)
  end

  defp resolve_node_collisions([]), do: []
  defp resolve_node_collisions([_single] = biotopes), do: biotopes

  defp resolve_node_collisions(biotopes) do
    ids = Enum.map(biotopes, & &1.id)

    initial =
      Map.new(biotopes, fn biotope ->
        {biotope.id,
         %{biotope | display_x: clamp_x(biotope.display_x), display_y: clamp_y(biotope.display_y)}}
      end)

    by_id =
      Enum.reduce(1..@layout_passes, initial, fn _pass, acc ->
        Enum.reduce(pair_ids(ids), acc, fn {left_id, right_id}, acc2 ->
          left = Map.fetch!(acc2, left_id)
          right = Map.fetch!(acc2, right_id)

          if overlapping?(left, right) do
            {left2, right2} = separate_pair(left, right)

            acc2
            |> Map.put(left_id, left2)
            |> Map.put(right_id, right2)
          else
            acc2
          end
        end)
      end)

    Enum.map(ids, &Map.fetch!(by_id, &1))
  end

  defp pair_ids(ids) do
    ids
    |> Enum.with_index()
    |> Enum.flat_map(fn {left_id, index} ->
      ids
      |> Enum.drop(index + 1)
      |> Enum.map(&{left_id, &1})
    end)
  end

  defp overlapping?(left, right) do
    abs(left.display_x - right.display_x) < @node_clearance_x and
      abs(left.display_y - right.display_y) < @node_clearance_y
  end

  defp separate_pair(left, right) do
    dx = right.display_x - left.display_x
    dy = right.display_y - left.display_y

    dir_x = if dx == 0.0, do: default_direction(left.id, right.id), else: dx / abs(dx)
    dir_y = if dy == 0.0, do: default_direction({left.id, :y}, {right.id, :y}), else: dy / abs(dy)

    shift_x = max((@node_clearance_x - abs(dx)) / 2.0, 0.0) + 0.35
    shift_y = max((@node_clearance_y - abs(dy)) / 2.0, 0.0) + 0.25

    {
      %{
        left
        | display_x: clamp_x(left.display_x - dir_x * shift_x),
          display_y: clamp_y(left.display_y - dir_y * shift_y)
      },
      %{
        right
        | display_x: clamp_x(right.display_x + dir_x * shift_x),
          display_y: clamp_y(right.display_y + dir_y * shift_y)
      }
    }
  end

  defp default_direction(left_key, right_key) do
    if :erlang.phash2(left_key) <= :erlang.phash2(right_key), do: -1.0, else: 1.0
  end

  defp clamp_x(value) do
    {lo, hi} = @map_bounds_x
    clamp(value, lo, hi)
  end

  defp clamp_y(value) do
    {lo, hi} = @map_bounds_y
    clamp(value, lo, hi)
  end
end
