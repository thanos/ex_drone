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

    test "updates tracked position (altitude and forward distance)" do
      name = :"move_state_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name)
      Drone.connect_sdk(name)
      :ok = Drone.takeoff(name)

      # Takeoff sets z to 30.
      {:ok, after_takeoff} = Drone.telemetry(name)
      assert after_takeoff.z == 30
      assert after_takeoff.y == 0

      # At yaw 0, forward moves +y; up moves +z.
      :ok = Drone.move(name, :forward, 100)
      :ok = Drone.move(name, :up, 40)

      {:ok, after_moves} = Drone.telemetry(name)
      assert after_moves.y == 100
      assert after_moves.z == 70

      :ok = Drone.land(name)
      :ok = Drone.disconnect(name)
    end

    test "rotation changes the heading used for subsequent moves" do
      name = :"move_rot_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name)
      Drone.connect_sdk(name)
      :ok = Drone.takeoff(name)

      # Rotate 90 cw, then forward should move along +x instead of +y.
      :ok = Drone.rotate(name, :cw, 90)
      :ok = Drone.move(name, :forward, 100)

      {:ok, telemetry} = Drone.telemetry(name)
      assert telemetry.yaw == 90
      assert telemetry.x == 100
      assert telemetry.y == 0

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

  describe "unknown drone" do
    test "commands return {:error, :not_connected} instead of crashing" do
      assert {:error, :not_connected} = Drone.takeoff(:nonexistent_drone)
      assert {:error, :not_connected} = Drone.move(:nonexistent_drone, :up, 30)
      assert {:error, :not_connected} = Drone.query(:nonexistent_drone, :battery)
      assert {:error, :not_connected} = Drone.telemetry(:nonexistent_drone)
      assert {:error, :not_connected} = Drone.emergency(:nonexistent_drone)
      assert {:error, :not_connected} = Drone.disconnect(:nonexistent_drone)
    end

    test "passing a pid returns {:error, :not_connected} (pids are not supported handles)" do
      # The @type drone is atom(), not pid(). If a user tries to use a pid
      # (e.g., from whereis), it should gracefully return :not_connected.
      fake_pid = spawn(fn -> :ok end)
      assert {:error, :not_connected} = Drone.takeoff(fake_pid)
    end
  end

  describe "command range validation" do
    test "rejects out-of-range distance, degrees, and speed" do
      name = :"range_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name)
      Drone.connect_sdk(name)
      :ok = Drone.takeoff(name)

      assert {:error, :safety, :invalid_distance} = Drone.move(name, :up, 9999)
      assert {:error, :safety, :invalid_degrees} = Drone.rotate(name, :cw, 99_999)
      assert {:error, :safety, :invalid_speed} = Drone.set_speed(name, 999)

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
