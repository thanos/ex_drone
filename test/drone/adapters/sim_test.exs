defmodule Drone.Adapters.SimTest do
  use ExUnit.Case, async: true

  alias Drone.{Adapters.Sim, Adapters.Sim.State, Command}

  describe "connect/1" do
    test "connects with defaults" do
      assert {:ok, %State{} = state} = Sim.connect([])
      assert state.battery == 100
      assert state.mode == :idle
    end

    test "connects with custom battery" do
      assert {:ok, %State{} = state} = Sim.connect(battery: 50)
      assert state.battery == 50
    end

    test "connects with failure configuration" do
      assert {:ok, %State{} = state} = Sim.connect(failure_rate: 1.0)
      assert state.config.failure_rate == 1.0
    end
  end

  describe "battery reporting" do
    test "reports integer battery after fractional drain" do
      {:ok, state} = Sim.connect([])
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())
      {:ok, _, state} = Sim.command(state, Command.takeoff())
      {:ok, _, state} = Sim.command(state, Command.move(:up, 30))

      {:ok, telemetry, _} = Sim.telemetry(state)
      assert is_integer(telemetry.battery)

      {:ok, battery, _} = Sim.command(state, Command.query(:battery))
      assert is_integer(battery)
    end
  end

  describe "command/2 - SDK mode" do
    test "enters SDK mode from idle" do
      {:ok, state} = Sim.connect([])
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())
      assert state.mode == :sdk_mode
    end
  end

  describe "command/2 - takeoff" do
    test "takes off from SDK mode" do
      {:ok, state} = Sim.connect([])
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())
      {:ok, _, state} = Sim.command(state, Command.takeoff())
      assert state.flying == true
      assert state.z == 30
      assert state.mode == :flying
    end

    test "rejects takeoff from idle" do
      {:ok, state} = Sim.connect([])
      assert {:error, :not_in_sdk_mode, _} = Sim.command(state, Command.takeoff())
    end

    test "drains battery on takeoff" do
      {:ok, state} = Sim.connect(battery: 100)
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())
      {:ok, _, state} = Sim.command(state, Command.takeoff())
      assert state.battery < 100
    end
  end

  describe "command/2 - movement" do
    test "moves up" do
      {:ok, state} = Sim.connect([])
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())
      {:ok, _, state} = Sim.command(state, Command.takeoff())
      {:ok, _, new_state} = Sim.command(state, Command.move(:up, 50))
      assert new_state.z == 80
    end

    test "moves down" do
      {:ok, state} = Sim.connect([])
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())
      {:ok, _, state} = Sim.command(state, Command.takeoff())
      {:ok, _, state} = Sim.command(state, Command.move(:up, 50))
      {:ok, _, new_state} = Sim.command(state, Command.move(:down, 20))
      assert new_state.z == 60
    end

    test "moves forward" do
      {:ok, state} = Sim.connect([])
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())
      {:ok, _, state} = Sim.command(state, Command.takeoff())
      {:ok, _, new_state} = Sim.command(state, Command.move(:forward, 100))
      assert new_state.y == 100
    end

    test "rotates clockwise" do
      {:ok, state} = Sim.connect([])
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())
      {:ok, _, state} = Sim.command(state, Command.takeoff())
      {:ok, _, new_state} = Sim.command(state, Command.rotate(:cw, 90))
      assert new_state.yaw == 90
    end

    test "flips" do
      {:ok, state} = Sim.connect([])
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())
      {:ok, _, state} = Sim.command(state, Command.takeoff())
      {:ok, _, new_state} = Sim.command(state, Command.flip(:left))
      assert new_state.x == -20
    end
  end

  describe "command/2 - land" do
    test "lands from flying state" do
      {:ok, state} = Sim.connect([])
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())
      {:ok, _, state} = Sim.command(state, Command.takeoff())
      {:ok, _, state} = Sim.command(state, Command.land())
      assert state.flying == false
      assert state.z == 0
      assert state.mode == :sdk_mode
    end
  end

  describe "command/2 - emergency" do
    test "emergency always works" do
      {:ok, state} = Sim.connect([])
      {:ok, _, state} = Sim.command(state, Command.emergency())
      assert state.mode == :emergency
    end

    test "emergency sets flying to false" do
      {:ok, state} = Sim.connect([])
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())
      {:ok, _, state} = Sim.command(state, Command.takeoff())
      {:ok, _, state} = Sim.command(state, Command.emergency())
      assert state.flying == false
      assert state.mode == :emergency
    end

    test "emergency mode blocks all commands" do
      {:ok, state} = Sim.connect([])
      {:ok, _, state} = Sim.command(state, Command.emergency())
      assert {:error, :emergency_active, _} = Sim.command(state, Command.sdk_mode())
      assert {:error, :emergency_active, _} = Sim.command(state, Command.takeoff())
    end
  end

  describe "command/2 - hover" do
    test "hovers for specified seconds" do
      {:ok, state} = Sim.connect([])
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())
      {:ok, _, state} = Sim.command(state, Command.takeoff())
      {:ok, _, state} = Sim.command(state, Command.hover(5))
      assert state.last_command.type == :hover
    end
  end

  describe "command/2 - speed" do
    test "sets speed" do
      {:ok, state} = Sim.connect([])
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())
      {:ok, _, state} = Sim.command(state, Command.takeoff())
      {:ok, _, state} = Sim.command(state, Command.speed(50))
      assert state.speed == 50
    end
  end

  describe "command/2 - stop" do
    test "stops the drone" do
      {:ok, state} = Sim.connect([])
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())
      {:ok, _, state} = Sim.command(state, Command.takeoff())
      {:ok, _, state} = Sim.command(state, Command.speed(50))
      {:ok, _, state} = Sim.command(state, Command.stop())
      assert state.speed == 0
    end
  end

  describe "command/2 - queries" do
    test "returns battery percentage" do
      {:ok, state} = Sim.connect(battery: 75)
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())
      {:ok, value, _} = Sim.command(state, Command.query(:battery))
      assert value == 75
    end

    test "returns height" do
      {:ok, state} = Sim.connect([])
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())
      {:ok, _, state} = Sim.command(state, Command.takeoff())
      {:ok, value, _} = Sim.command(state, Command.query(:height))
      assert value == 30
    end

    test "returns speed" do
      {:ok, state} = Sim.connect([])
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())
      {:ok, _, state} = Sim.command(state, Command.takeoff())
      {:ok, _, state} = Sim.command(state, Command.speed(80))
      {:ok, value, _} = Sim.command(state, Command.query(:speed))
      assert value == 80
    end

    test "returns time" do
      {:ok, state} = Sim.connect([])
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())
      {:ok, _, state} = Sim.command(state, Command.takeoff())
      {:ok, value, _} = Sim.command(state, Command.query(:time))
      assert value == 3
    end

    test "returns wifi" do
      {:ok, state} = Sim.connect([])
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())
      {:ok, value, _} = Sim.command(state, Command.query(:wifi))
      assert value == "sim_wifi"
    end

    test "returns sdk version" do
      {:ok, state} = Sim.connect([])
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())
      {:ok, value, _} = Sim.command(state, Command.query(:sdk_version))
      assert value == "sim_1.0"
    end

    test "returns serial number" do
      {:ok, state} = Sim.connect([])
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())
      {:ok, value, _} = Sim.command(state, Command.query(:serial_number))
      assert value == "SIM001"
    end
  end

  describe "telemetry/1" do
    test "returns current state" do
      {:ok, state} = Sim.connect([])
      {:ok, telemetry, _} = Sim.telemetry(state)
      assert Map.has_key?(telemetry, :x)
      assert Map.has_key?(telemetry, :y)
      assert Map.has_key?(telemetry, :z)
      assert Map.has_key?(telemetry, :yaw)
      assert Map.has_key?(telemetry, :battery)
      assert Map.has_key?(telemetry, :flying)
      assert Map.has_key?(telemetry, :mode)
    end
  end

  describe "disconnect/1" do
    test "returns ok" do
      {:ok, state} = Sim.connect([])
      assert :ok == Sim.disconnect(state)
    end
  end

  describe "failure injection" do
    test "fails commands with fail_commands" do
      {:ok, state} = Sim.connect(fail_commands: [:takeoff])
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())
      assert {:error, :simulated_failure, _} = Sim.command(state, Command.takeoff())
    end

    test "fails commands with failure_rate 1.0" do
      {:ok, state} = Sim.connect(failure_rate: 1.0)
      # failure_rate affects all commands, so even sdk_mode will fail
      assert {:error, :simulated_failure, _} = Sim.command(state, Command.sdk_mode())
    end
  end

  describe "mission tracking" do
    test "tracks command history" do
      {:ok, state} = Sim.connect([])
      {:ok, _, state} = Sim.command(state, Command.sdk_mode())
      {:ok, _, state} = Sim.command(state, Command.takeoff())
      assert Enum.count(state.command_history) == 2
      assert state.last_command.type == :takeoff
    end
  end
end
