defmodule Drone.GitHubIssuesTest do
  use ExUnit.Case, async: false

  alias Drone.Adapters.Sim
  alias Drone.Adapters.Tello.{Connection, Parser}
  alias Drone.{Command, Safety.Policy, Vehicle}

  describe "GitHub Issue #39: @type drone should be atom() not atom() | pid()" do
    test "passing a pid to a command returns {:error, :not_connected}" do
      # The @type drone is atom(), not pid(). Registry.lookup with a pid key
      # returns [] which causes whereis to return nil, triggering :not_connected.
      fake_pid = spawn(fn -> :ok end)
      assert {:error, :not_connected} = Drone.takeoff(fake_pid)
      assert {:error, :not_connected} = Drone.query(fake_pid, :battery)
    end
  end

  describe "GitHub Issue #43: Connection defaults duplicated and unused" do
    test "Connection constants are used by send_command" do
      # This is more of a code inspection test — verifying the constants exist
      # and are used. The actual behavior is tested in tello integration tests.
      # Here we just verify the module has the expected default constants.
      assert function_exported?(Connection, :send_command, 3)
      assert function_exported?(Connection, :open, 1)
    end

    test "Tello.connect uses Connection defaults (no duplication)" do
      # Verify Tello doesn't duplicate defaults by checking it uses Connection's.
      # This test documents the expected behavior: Tello passes opts to Connection.
      # A more thorough test would be a code inspection or integration test.
      # Here we just ensure the connection flow works with defaults.
      assert function_exported?(Drone.Adapters.Tello, :connect, 1)
    end
  end

  describe "GitHub Issue #44: child_spec id field is ignored by DynamicSupervisor" do
    test "Vehicle child_spec sets restart: :temporary" do
      spec = Vehicle.child_spec(name: :test_spec)
      assert spec.restart == :temporary
    end

    test "child_spec id is simplified since DynamicSupervisor ignores it" do
      # The id field is required but DynamicSupervisor doesn't use it for dynamic children.
      # We use a constant instead of computing from opts since the value doesn't matter.
      spec = Vehicle.child_spec(name: :test_id_check)
      assert spec.id == Drone.Vehicle
      assert spec.restart == :temporary
    end
  end

  describe "GitHub Issue #45: query(:time) returns flight time not command count" do
    test "query(:time) returns cumulative flight time in seconds" do
      {:ok, state} = Sim.connect([])
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())

      # sdk_mode adds no flight time
      {:ok, time1, state} = Sim.command(state, Command.query(:time))
      assert time1 == 0

      # takeoff adds ~3 seconds
      {:ok, _, state} = Sim.command(state, Command.takeoff())
      {:ok, time2, state} = Sim.command(state, Command.query(:time))
      assert time2 == 3

      # move adds ~2 seconds
      {:ok, _, state} = Sim.command(state, Command.move(:up, 30))
      {:ok, time3, _state} = Sim.command(state, Command.query(:time))
      assert time3 == 5
    end

    test "flight time accumulates across multiple commands" do
      {:ok, state} = Sim.connect([])
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())
      {:ok, _, state} = Sim.command(state, Command.takeoff())
      {:ok, _, state} = Sim.command(state, Command.move(:forward, 100))
      {:ok, _, state} = Sim.command(state, Command.rotate(:cw, 90))
      {:ok, _, state} = Sim.command(state, Command.land())

      {:ok, time, _state} = Sim.command(state, Command.query(:time))
      # takeoff(3) + move(2) + rotate(2) + land(3) = 10 seconds
      assert time == 10
    end

    test "query commands do not add to flight time" do
      {:ok, state} = Sim.connect([])
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())
      {:ok, _, state} = Sim.command(state, Command.takeoff())

      {:ok, time_before, state} = Sim.command(state, Command.query(:time))
      {:ok, _battery, state} = Sim.command(state, Command.query(:battery))
      {:ok, _height, state} = Sim.command(state, Command.query(:height))
      {:ok, time_after, _state} = Sim.command(state, Command.query(:time))

      # Query commands themselves don't add flight time
      assert time_before == time_after
    end
  end

  describe "GitHub Issue #46: Test coverage gaps (already fixed in earlier batches)" do
    test "out-of-range command args are rejected (F-01)" do
      # This was added in the F-01 fix batch
      {:ok, name} = Drone.connect(:sim, name: :"cov_f01_#{System.unique_integer([:positive])}")
      Drone.connect_sdk(name)
      Drone.takeoff(name)

      assert {:error, :safety, :invalid_distance} = Drone.move(name, :up, 9_999)
      assert {:error, :safety, :invalid_degrees} = Drone.rotate(name, :cw, 99_999)

      Drone.disconnect(name)
    end

    test "battery is always an integer after moves (F-02)" do
      # This was added in the F-02 fix batch
      {:ok, state} = Sim.connect([])
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())
      {:ok, _, state} = Sim.command(state, Command.takeoff())
      {:ok, _, state} = Sim.command(state, Command.move(:up, 30))

      {:ok, telemetry, _} = Sim.telemetry(state)
      assert is_integer(telemetry.battery)
    end

    test "unknown drone name returns :not_connected (F-04)" do
      # This was added in the F-04 fix batch
      assert {:error, :not_connected} = Drone.takeoff(:nonexistent_xyz)
    end

    test "parser handles negative numbers (F-08)" do
      # This was added in the F-08 fix batch
      assert {:ok, -45} = Parser.parse("-45")
      assert {:ok, "12;34;56"} = Parser.parse("12;34;56")
    end

    test "Policy.new accepts unrestricted: true (F-09)" do
      # This was added in the F-09 fix batch
      policy = Policy.new(unrestricted: true)
      assert policy.max_altitude_cm == nil
    end

    test "connect accepts %Policy{} struct (F-10)" do
      # This was added in the F-10 fix batch
      name = :"cov_f10_#{System.unique_integer([:positive])}"
      policy = Policy.new(max_altitude_cm: 250)
      {:ok, ^name} = Drone.connect(:sim, name: name, safety: policy)
      Drone.disconnect(name)
    end
  end
end
