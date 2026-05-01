defmodule Arkea.Game.WorldTest do
  use Arkea.DataCase, async: false

  alias Arkea.Game.World
  alias Arkea.Sim.Biotope.Supervisor, as: BiotopeSupervisor
  alias Arkea.Sim.BiotopeState
  alias Arkea.Ecology.Phase

  test "overview repositions colliding world nodes so cards stay readable" do
    ids =
      for suffix <- ~w(alpha beta gamma) do
        state = overlapping_state("world-overlap-#{suffix}")
        {:ok, pid} = BiotopeSupervisor.start_biotope(state)
        on_exit(fn -> stop_biotope(state.id, pid) end)
        state.id
      end

    summaries =
      World.overview().biotopes
      |> Enum.filter(&(&1.id in ids))

    assert length(summaries) == 3

    Enum.each(summaries, fn summary ->
      assert summary.display_x >= 11.0
      assert summary.display_x <= 89.0
      assert summary.display_y >= 12.0
      assert summary.display_y <= 88.0
    end)

    Enum.each(pairwise(summaries), fn {left, right} ->
      refute abs(left.display_x - right.display_x) < 19.0 and
               abs(left.display_y - right.display_y) < 11.5
    end)
  end

  defp overlapping_state(label) do
    phase = Phase.new(:surface, dilution_rate: 0.02)

    BiotopeState.new_from_opts(
      id: Arkea.UUID.v4(),
      archetype: :eutrophic_pond,
      zone: String.to_atom("world_overlap_#{label}"),
      x: 40.0,
      y: 40.0,
      phases: [phase],
      dilution_rate: 0.02,
      lineages: [],
      neighbor_ids: []
    )
  end

  defp stop_biotope(id, pid) do
    case Registry.lookup(Arkea.Sim.Registry, {:biotope, id}) do
      [{^pid, _value}] when is_pid(pid) ->
        if Process.alive?(pid) do
          DynamicSupervisor.terminate_child(BiotopeSupervisor, pid)
        end

        :ok

      _ ->
        :ok
    end
  end

  defp pairwise(items) do
    items
    |> Enum.with_index()
    |> Enum.flat_map(fn {left, index} ->
      items
      |> Enum.drop(index + 1)
      |> Enum.map(&{left, &1})
    end)
  end
end
