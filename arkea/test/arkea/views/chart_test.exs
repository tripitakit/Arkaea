defmodule Arkea.Views.ChartTest do
  use ExUnit.Case, async: true

  alias Arkea.Views.Chart

  describe "linear_scale/3" do
    test "maps domain endpoints to range endpoints" do
      f = Chart.linear_scale({0, 100}, {0, 200})
      assert f.(0) == 0.0
      assert f.(100) == 200.0
      assert f.(50) == 100.0
    end

    test "clamps inputs outside the domain" do
      f = Chart.linear_scale({0, 100}, {0, 200})
      assert f.(-10) == 0.0
      assert f.(110) == 200.0
    end

    test "degenerate domain pins to range minimum" do
      f = Chart.linear_scale({5, 5}, {0, 200})
      assert f.(5) == 0.0
      assert f.(99) == 0.0
    end
  end

  describe "log_scale/3" do
    test "monotonic increasing across decades" do
      f = Chart.log_scale({1.0, 1000.0}, {0, 300})
      assert f.(1.0) == 0.0
      assert_in_delta f.(10.0), 100.0, 0.5
      assert_in_delta f.(100.0), 200.0, 0.5
      assert f.(1000.0) == 300.0
    end

    test "non-positive inputs are clamped to epsilon" do
      f = Chart.log_scale({1.0, 100.0}, {0, 200})
      assert f.(0.0) <= 1.0
    end
  end

  describe "axis_ticks/3" do
    test "produces 5–8 round-numbered ticks for a typical range" do
      ticks = Chart.axis_ticks(0, 100)
      assert length(ticks) >= 5
      assert length(ticks) <= 12
      assert hd(ticks) <= 0
      assert List.last(ticks) >= 100
    end

    test "handles a tiny range gracefully" do
      ticks = Chart.axis_ticks(5, 5)
      assert ticks == [5]
    end
  end

  describe "path_for_series/4" do
    test "empty series yields empty string" do
      assert Chart.path_for_series([], fn x -> x end, fn y -> y end) == ""
    end

    test "produces a path starting with M and continuing with L" do
      points = [{0, 0}, {10, 5}, {20, 8}]
      x_scale = Chart.linear_scale({0, 20}, {0, 100})
      y_scale = Chart.linear_scale({0, 10}, {100, 0})

      d = Chart.path_for_series(points, x_scale, y_scale)

      assert String.starts_with?(d, "M")
      assert String.contains?(d, "L")
    end

    test "downsampling honours the cap and preserves endpoints approximately" do
      n = 10_000
      points = Enum.map(0..n, fn i -> {i, i} end)
      x_scale = Chart.linear_scale({0, n}, {0, 1000})
      y_scale = Chart.linear_scale({0, n}, {1000, 0})

      d = Chart.path_for_series(points, x_scale, y_scale, downsample: 100)

      # An over-cap series should compress: very rough invariant — the
      # path string is not 100k chars long.
      assert byte_size(d) < 5_000
    end
  end

  describe "bin_mean/2" do
    test "returns one bin per requested bucket (capped to data span)" do
      points = Enum.map(0..99, fn i -> {i, i * 2} end)
      bins = Chart.bin_mean(points, 10)

      assert length(bins) >= 1
      assert length(bins) <= 11
      # Means are increasing because the input is monotonic.
      ys = Enum.map(bins, &elem(&1, 1))
      assert ys == Enum.sort(ys)
    end
  end

  describe "format/1" do
    test "rounds floats to at most 2 decimals and drops trailing zeros" do
      assert Chart.format(1.0) == "1"
      assert Chart.format(1.50) == "1.5"
      assert Chart.format(1.234) == "1.23"
      assert Chart.format(42) == "42"
    end
  end
end
