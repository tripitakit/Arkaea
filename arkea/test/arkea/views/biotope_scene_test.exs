defmodule Arkea.Views.BiotopeSceneTest do
  use ExUnit.Case, async: true

  alias Arkea.Views.BiotopeScene

  describe "build/1 with empty data" do
    test "returns empty layout when no phases" do
      layout = BiotopeScene.build(%{phases: [], lineages: []})

      assert layout.empty?
      assert layout.bands == []
      assert layout.particles == []
      assert layout.tick == 0
    end

    test "carries the tick value" do
      layout = BiotopeScene.build(%{phases: [], lineages: [], tick: 42})
      assert layout.tick == 42
    end
  end

  describe "build/1 with phases" do
    setup do
      phases = [
        %{
          name: "surface",
          label: "Surface",
          color: "#f59e0b",
          temperature: 25.0,
          ph: 7.0,
          dilution_rate: 0.05,
          total_abundance: 200,
          lineage_count: 2
        },
        %{
          name: "deep",
          label: "Deep",
          color: "#22d3ee",
          temperature: 12.0,
          ph: 7.4,
          dilution_rate: 0.02,
          total_abundance: 50,
          lineage_count: 1
        }
      ]

      lineages = [
        %{
          id: "L1",
          total_abundance: 150,
          cluster: "biofilm",
          color: "#84cc16",
          phase_abundance: %{"surface" => 150, "deep" => 0}
        },
        %{
          id: "L2",
          total_abundance: 100,
          cluster: "motile",
          color: "#22d3ee",
          phase_abundance: %{"surface" => 50, "deep" => 50}
        }
      ]

      {:ok, phases: phases, lineages: lineages}
    end

    test "builds one band per phase, in order", ctx do
      layout = BiotopeScene.build(%{phases: ctx.phases, lineages: ctx.lineages})

      assert length(layout.bands) == 2
      assert Enum.map(layout.bands, & &1.name) == ["surface", "deep"]
      refute layout.empty?
    end

    test "bands are stacked vertically with monotonically increasing y", ctx do
      layout = BiotopeScene.build(%{phases: ctx.phases, lineages: ctx.lineages})

      [b1, b2] = layout.bands
      assert b2.y > b1.y
      assert b1.y >= 0
      assert b2.y + b2.h <= layout.height + 0.001
    end

    test "selected_phase marks the matching band", ctx do
      layout =
        BiotopeScene.build(%{
          phases: ctx.phases,
          lineages: ctx.lineages,
          selected_phase: "deep"
        })

      [_surface, deep] = layout.bands
      assert deep.selected?
      assert deep.name == "deep"
    end

    test "particles are placed only inside band rectangles", ctx do
      layout = BiotopeScene.build(%{phases: ctx.phases, lineages: ctx.lineages})

      bands_by_name = Map.new(layout.bands, &{&1.name, &1})

      for p <- layout.particles do
        # The particle key encodes its band name; find it.
        [band_name, _, _] = String.split(p.key, ":")
        band = bands_by_name[band_name]
        assert band, "no band found for particle key #{p.key}"
        assert p.cx >= band.x and p.cx <= band.x + band.w
        assert p.cy >= band.y and p.cy <= band.y + band.h
      end
    end

    test "particle layout is deterministic across calls", ctx do
      layout_a = BiotopeScene.build(%{phases: ctx.phases, lineages: ctx.lineages})
      layout_b = BiotopeScene.build(%{phases: ctx.phases, lineages: ctx.lineages})

      assert Enum.map(layout_a.particles, &{&1.key, &1.cx, &1.cy, &1.r}) ==
               Enum.map(layout_b.particles, &{&1.key, &1.cx, &1.cy, &1.r})
    end

    test "particles carry the lineage color and cluster", ctx do
      layout = BiotopeScene.build(%{phases: ctx.phases, lineages: ctx.lineages})

      colors = layout.particles |> Enum.map(& &1.color) |> Enum.uniq() |> Enum.sort()
      assert "#84cc16" in colors or "#22d3ee" in colors

      clusters = layout.particles |> Enum.map(& &1.cluster) |> Enum.uniq()
      assert Enum.all?(clusters, &(&1 in ["biofilm", "motile", "generalist"]))
    end

    test "lineages with zero abundance in a phase contribute no particles", ctx do
      layout = BiotopeScene.build(%{phases: ctx.phases, lineages: ctx.lineages})

      # L1 has 0 abundance in :deep; no particle key starts with "deep:L1:"
      refute Enum.any?(layout.particles, fn p -> String.starts_with?(p.key, "deep:L1:") end)
    end

    test "particle radius is positive", ctx do
      layout = BiotopeScene.build(%{phases: ctx.phases, lineages: ctx.lineages})
      assert Enum.all?(layout.particles, &(&1.r > 0))
    end

    test "viewbox/0 returns a string with width and height" do
      assert BiotopeScene.viewbox() =~ "0 0"
    end
  end
end
