defmodule Drone.PublicAPITest do
  use ExUnit.Case, async: false

  describe "connect/2 with adapter module" do
    test "connects using adapter module directly" do
      name = :"adapter_mod_#{System.unique_integer([:positive])}"
      assert {:ok, ^name} = Drone.connect(Drone.Adapters.Sim, name: name)
      :ok = Drone.disconnect(name)
    end
  end

  describe "move/3" do
    test "moves in all directions" do
      name = :"move_dirs_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name)
      Drone.connect_sdk(name)
      :ok = Drone.takeoff(name)

      :ok = Drone.move(name, :up, 30)
      :ok = Drone.move(name, :down, 20)
      :ok = Drone.move(name, :forward, 50)
      :ok = Drone.move(name, :back, 20)
      :ok = Drone.move(name, :left, 30)
      :ok = Drone.move(name, :right, 30)

      :ok = Drone.land(name)
      :ok = Drone.disconnect(name)
    end
  end

  describe "rotate/3" do
    test "rotates both directions" do
      name = :"rotate_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name)
      Drone.connect_sdk(name)
      :ok = Drone.takeoff(name)

      :ok = Drone.rotate(name, :cw, 90)
      :ok = Drone.rotate(name, :ccw, 45)

      :ok = Drone.land(name)
      :ok = Drone.disconnect(name)
    end
  end

  describe "flip/1" do
    test "flips in all directions" do
      name = :"flip_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name)
      Drone.connect_sdk(name)
      :ok = Drone.takeoff(name)

      :ok = Drone.flip(name, :left)
      :ok = Drone.flip(name, :right)
      :ok = Drone.flip(name, :forward)
      :ok = Drone.flip(name, :back)

      :ok = Drone.land(name)
      :ok = Drone.disconnect(name)
    end
  end

  describe "hover/2" do
    test "hovers for specified seconds" do
      name = :"hover_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name)
      Drone.connect_sdk(name)
      :ok = Drone.takeoff(name)

      :ok = Drone.hover(name, seconds: 2)

      :ok = Drone.land(name)
      :ok = Drone.disconnect(name)
    end
  end

  describe "set_speed/2" do
    test "sets the drone speed" do
      name = :"speed_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name)
      Drone.connect_sdk(name)
      :ok = Drone.takeoff(name)

      :ok = Drone.set_speed(name, 50)

      :ok = Drone.land(name)
      :ok = Drone.disconnect(name)
    end
  end

  describe "stop/1" do
    test "stops the drone" do
      name = :"stop_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name)
      Drone.connect_sdk(name)
      :ok = Drone.takeoff(name)

      :ok = Drone.stop(name)

      :ok = Drone.land(name)
      :ok = Drone.disconnect(name)
    end
  end

  describe "query/2" do
    test "queries battery" do
      name = :"query_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name)
      Drone.connect_sdk(name)

      assert {:ok, 100} = Drone.query(name, :battery)

      :ok = Drone.disconnect(name)
    end

    test "queries height after takeoff" do
      name = :"query_h_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name)
      Drone.connect_sdk(name)
      :ok = Drone.takeoff(name)

      assert {:ok, _} = Drone.query(name, :height)

      :ok = Drone.land(name)
      :ok = Drone.disconnect(name)
    end
  end

  describe "safety errors" do
    test "returns safety error tuple for rejected commands" do
      name = :"safety_err_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name)
      Drone.connect_sdk(name)

      assert {:error, :safety, :not_flying} = Drone.move(name, :forward, 100)

      :ok = Drone.takeoff(name)
      assert {:error, :safety, :already_flying} = Drone.takeoff(name)

      :ok = Drone.land(name)
      :ok = Drone.disconnect(name)
    end

    test "returns adapter error tuple for simulated failures" do
      name = :"sim_fail_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name, fail_commands: [:takeoff])
      Drone.connect_sdk(name)

      assert {:error, :simulated_failure} = Drone.takeoff(name)

      :ok = Drone.disconnect(name)
    end
  end
end
