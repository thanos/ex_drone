defmodule Drone.Safety.GeofenceTest do
  use ExUnit.Case, async: true

  alias Drone.Safety.Geofence

  describe "circle/2" do
    test "creates a circular geofence" do
      gf = Geofence.circle({0, 0}, 500)
      assert gf.type == :circle
      assert gf.center == {0, 0}
      assert gf.radius_cm == 500
    end
  end

  describe "polygon/1" do
    test "creates a polygon geofence" do
      gf = Geofence.polygon([{0, 0}, {100, 0}, {100, 100}, {0, 100}])
      assert gf.type == :polygon
      assert Enum.count(gf.points) == 4
    end

    test "requires at least 3 points" do
      assert_raise FunctionClauseError, fn ->
        Geofence.polygon([{0, 0}, {100, 0}])
      end
    end
  end

  describe "radius/1" do
    test "creates a circular geofence at origin" do
      gf = Geofence.radius(500)
      assert gf.type == :circle
      assert gf.center == {0, 0}
      assert gf.radius_cm == 500
    end
  end

  describe "contains?/2" do
    test "nil geofence always contains point" do
      assert Geofence.contains?(nil, {1000, 1000})
    end

    test "circular geofence contains point inside" do
      gf = Geofence.circle({0, 0}, 500)
      assert Geofence.contains?(gf, {300, 300})
    end

    test "circular geofence rejects point outside" do
      gf = Geofence.circle({0, 0}, 100)
      refute Geofence.contains?(gf, {200, 200})
    end

    test "circular geofence contains point on boundary" do
      gf = Geofence.circle({0, 0}, 100)
      assert Geofence.contains?(gf, {100, 0})
    end

    test "polygon geofence contains point inside" do
      gf = Geofence.polygon([{0, 0}, {100, 0}, {100, 100}, {0, 100}])
      assert Geofence.contains?(gf, {50, 50})
    end

    test "polygon geofence rejects point outside" do
      gf = Geofence.polygon([{0, 0}, {100, 0}, {100, 100}, {0, 100}])
      refute Geofence.contains?(gf, {200, 200})
    end
  end
end
