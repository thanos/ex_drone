defmodule Drone.GeometryTest do
  use ExUnit.Case, async: true

  alias Drone.Geometry

  describe "move_delta/3" do
    test "vertical moves ignore yaw" do
      assert {0, 0, 50} = Geometry.move_delta(:up, 50, 0)
      assert {0, 0, -50} = Geometry.move_delta(:down, 50, 123)
    end

    test "forward at yaw 0 moves along +y" do
      assert {0, 100, 0} = Geometry.move_delta(:forward, 100, 0)
    end

    test "forward at yaw 90 moves along +x" do
      assert {100, 0, 0} = Geometry.move_delta(:forward, 100, 90)
    end

    test "back is the inverse of forward" do
      assert {0, -100, 0} = Geometry.move_delta(:back, 100, 0)
    end

    test "right at yaw 0 moves along +x" do
      assert {100, 0, 0} = Geometry.move_delta(:right, 100, 0)
    end

    test "left is the inverse of right" do
      assert {-100, 0, 0} = Geometry.move_delta(:left, 100, 0)
    end
  end

  describe "rotate_yaw/3" do
    test "clockwise adds degrees modulo 360" do
      assert Geometry.rotate_yaw(:cw, 350, 20) == 10
    end

    test "counter-clockwise subtracts degrees and wraps" do
      assert Geometry.rotate_yaw(:ccw, 10, 20) == 350
    end
  end

  describe "flip_delta/1" do
    test "returns horizontal deltas per direction" do
      assert {-20, 0} = Geometry.flip_delta(:left)
      assert {20, 0} = Geometry.flip_delta(:right)
      assert {0, 20} = Geometry.flip_delta(:forward)
      assert {0, -20} = Geometry.flip_delta(:back)
    end
  end
end
