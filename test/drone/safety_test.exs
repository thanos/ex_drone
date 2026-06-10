defmodule Drone.SafetyTest do
  use ExUnit.Case, async: true

  alias Drone.{Command, Safety, Safety.Geofence, Safety.Policy}

  @flying_state %{
    mode: :flying,
    x: 0,
    y: 0,
    z: 30,
    yaw: 0,
    battery: 100,
    flying: true
  }

  @ground_state %{
    mode: :sdk_mode,
    x: 0,
    y: 0,
    z: 0,
    yaw: 0,
    battery: 100,
    flying: false
  }

  @idle_state %{
    mode: :idle,
    x: 0,
    y: 0,
    z: 0,
    yaw: 0,
    battery: 100,
    flying: false
  }

  describe "emergency bypass" do
    test "emergency always passes" do
      policy = Policy.unrestricted()
      state = %{@idle_state | battery: 0}
      assert {:ok, %Command{type: :emergency}} = Safety.check(Command.emergency(), policy, state)
    end

    test "emergency bypasses allowlist" do
      policy = %Policy{allowlist: [:battery?]}

      assert {:ok, %Command{type: :emergency}} =
               Safety.check(Command.emergency(), policy, @idle_state)
    end

    test "emergency passes even in emergency state" do
      policy = Policy.default()
      state = %{@idle_state | mode: :emergency}
      assert {:ok, %Command{type: :emergency}} = Safety.check(Command.emergency(), policy, state)
    end
  end

  describe "mode validation" do
    test "sdk_mode works in idle state" do
      policy = Policy.default()
      assert {:ok, _} = Safety.check(Command.sdk_mode(), policy, @idle_state)
    end

    test "commands rejected in idle state (except sdk_mode and emergency)" do
      policy = Policy.default()

      assert {:error, :safety, :not_in_sdk_mode} =
               Safety.check(Command.takeoff(), policy, @idle_state)

      assert {:error, :safety, :not_in_sdk_mode} =
               Safety.check(Command.move(:up, 50), policy, @idle_state)
    end

    test "emergency_active state rejects all non-emergency commands" do
      policy = Policy.default()
      state = %{@flying_state | mode: :emergency}
      assert {:error, :safety, :emergency_active} = Safety.check(Command.takeoff(), policy, state)
    end
  end

  describe "flying state validation" do
    test "takeoff rejected when already flying" do
      policy = Policy.default()

      assert {:error, :safety, :already_flying} =
               Safety.check(Command.takeoff(), policy, @flying_state)
    end

    test "takeoff accepted in sdk_mode when not flying" do
      policy = Policy.default()
      assert {:ok, _} = Safety.check(Command.takeoff(), policy, @ground_state)
    end

    test "land accepted when flying" do
      policy = Policy.default()
      assert {:ok, _} = Safety.check(Command.land(), policy, @flying_state)
    end

    test "land rejected when not flying" do
      policy = Policy.default()
      assert {:error, :safety, :not_flying} = Safety.check(Command.land(), policy, @ground_state)
    end

    test "movement commands require flying state" do
      policy = Policy.default()

      assert {:error, :safety, :not_flying} =
               Safety.check(Command.move(:forward, 100), policy, @ground_state)

      assert {:error, :safety, :not_flying} =
               Safety.check(Command.rotate(:cw, 90), policy, @ground_state)

      assert {:error, :safety, :not_flying} =
               Safety.check(Command.flip(:left), policy, @ground_state)
    end

    test "movement commands accepted when flying" do
      policy = Policy.default()
      assert {:ok, _} = Safety.check(Command.move(:forward, 100), policy, @flying_state)
      assert {:ok, _} = Safety.check(Command.rotate(:cw, 90), policy, @flying_state)
    end
  end

  describe "altitude safety" do
    test "rejects up movement that would exceed max altitude" do
      policy = %Policy{max_altitude_cm: 100}
      state = %{@flying_state | z: 80}
      cmd = Command.move(:up, 30)
      assert {:error, :safety, :max_altitude} = Safety.check(cmd, policy, state)
    end

    test "allows up movement within max altitude" do
      policy = %Policy{max_altitude_cm: 100}
      state = %{@flying_state | z: 50}
      cmd = Command.move(:up, 30)
      assert {:ok, _} = Safety.check(cmd, policy, state)
    end

    test "allows down movement regardless of max altitude" do
      policy = %Policy{max_altitude_cm: 100}
      state = %{@flying_state | z: 80}
      cmd = Command.move(:down, 30)
      assert {:ok, _} = Safety.check(cmd, policy, state)
    end

    test "nil max_altitude_cm disables altitude check" do
      policy = %Policy{max_altitude_cm: nil}
      state = %{@flying_state | z: 1000}
      cmd = Command.move(:up, 500)
      assert {:ok, _} = Safety.check(cmd, policy, state)
    end

    test "takeoff respects max altitude" do
      policy = %Policy{max_altitude_cm: 10}

      assert {:error, :safety, :max_altitude} =
               Safety.check(Command.takeoff(), policy, @ground_state)
    end
  end

  describe "distance safety" do
    test "rejects forward movement that would exceed max distance" do
      policy = %Policy{max_distance_cm: 100}
      state = %{@flying_state | y: 80}
      cmd = Command.move(:forward, 30)
      assert {:error, :safety, :max_distance} = Safety.check(cmd, policy, state)
    end

    test "allows forward movement within max distance" do
      policy = %Policy{max_distance_cm: 100}
      state = %{@flying_state | y: 50}
      cmd = Command.move(:forward, 30)
      assert {:ok, _} = Safety.check(cmd, policy, state)
    end

    test "nil max_distance_cm disables distance check" do
      policy = %Policy{max_distance_cm: nil}
      state = %{@flying_state | y: 1000}
      cmd = Command.move(:forward, 500)
      assert {:ok, _} = Safety.check(cmd, policy, state)
    end
  end

  describe "battery safety" do
    test "rejects takeoff below min battery" do
      policy = %Policy{min_battery_percent: 15}
      state = %{@ground_state | battery: 10}
      assert {:error, :safety, :low_battery} = Safety.check(Command.takeoff(), policy, state)
    end

    test "allows takeoff at or above min battery" do
      policy = %Policy{min_battery_percent: 15}
      state = %{@ground_state | battery: 20}
      assert {:ok, _} = Safety.check(Command.takeoff(), policy, state)
    end

    test "warns when battery is below warning level during movement" do
      policy = %Policy{battery_warning_percent: 25, min_battery_percent: 10}
      state = %{@flying_state | battery: 20}
      cmd = Command.move(:forward, 50)
      assert {:ok, _, [:low_battery]} = Safety.check(cmd, policy, state)
    end
  end

  describe "allowlist" do
    test "rejects commands not on allowlist" do
      policy = %Policy{allowlist: [:query]}
      state = %{@flying_state | mode: :flying}

      assert {:error, :safety, :command_not_allowed} =
               Safety.check(Command.move(:forward, 50), policy, state)
    end

    test "allows commands on allowlist" do
      policy = %Policy{allowlist: [:query]}
      cmd = Command.query(:battery)
      assert {:ok, _} = Safety.check(cmd, policy, @flying_state)
    end

    test "nil allowlist allows all commands" do
      policy = %Policy{allowlist: nil}
      assert {:ok, _} = Safety.check(Command.move(:forward, 50), policy, @flying_state)
    end
  end

  describe "prop guards warning" do
    test "warns on flip without prop guards" do
      policy = %Policy{prop_guards: false}

      assert {:ok, _, [:no_prop_guards]} =
               Safety.check(Command.flip(:left), policy, @flying_state)
    end

    test "no warning on flip with prop guards" do
      policy = %Policy{prop_guards: true}
      assert {:ok, %Command{}} = Safety.check(Command.flip(:left), policy, @flying_state)
    end
  end

  describe "geofence" do
    test "rejects movement that would leave geofence" do
      geofence = Geofence.radius(100)
      policy = %Policy{geofence: geofence}
      state = %{@flying_state | x: 0, y: 80}
      cmd = Command.move(:forward, 30)
      assert {:error, :safety, :geofence_violation} = Safety.check(cmd, policy, state)
    end

    test "allows movement within geofence" do
      geofence = Geofence.radius(100)
      policy = %Policy{geofence: geofence}
      state = %{@flying_state | x: 0, y: 0}
      cmd = Command.move(:forward, 50)
      assert {:ok, _} = Safety.check(cmd, policy, state)
    end
  end
end
