defmodule Drone.Safety.CrazyflieExtrasTest do
  use ExUnit.Case, async: true

  alias Drone.{Command, Safety, Safety.Policy}

  test "rejects motion when estimator is not ready" do
    policy = Policy.new(require_estimator: true)
    state = %{mode: :sdk_mode, flying: false, battery: 100, estimator_ready: false}

    assert {:error, :safety, :estimator_not_ready} =
             Safety.check(Command.takeoff(), policy, state)
  end

  test "rejects motion when telemetry is stale" do
    policy = Policy.new(max_telemetry_age_ms: 100)
    old = System.monotonic_time(:millisecond) - 500

    state = %{
      mode: :flying,
      flying: true,
      x: 0,
      y: 0,
      z: 50,
      yaw: 0,
      battery: 100,
      telemetry_at: old
    }

    assert {:error, :safety, :stale_telemetry} =
             Safety.check(Command.move(:forward, 50), policy, state)
  end

  test "allows motion when telemetry is fresh" do
    policy = Policy.new(max_telemetry_age_ms: 1_000)

    state = %{
      mode: :flying,
      flying: true,
      x: 0,
      y: 0,
      z: 50,
      yaw: 0,
      battery: 100,
      telemetry_at: System.monotonic_time(:millisecond)
    }

    assert {:ok, _} = Safety.check(Command.move(:forward, 50), policy, state)
  end

  test "rejects motion when telemetry_at is missing and age limit is set" do
    policy = Policy.new(max_telemetry_age_ms: 100)

    state = %{
      mode: :flying,
      flying: true,
      x: 0,
      y: 0,
      z: 50,
      yaw: 0,
      battery: 100
    }

    assert {:error, :safety, :stale_telemetry} =
             Safety.check(Command.move(:forward, 50), policy, state)
  end

  test "takeoff altitude uses takeoff_height_cm from vehicle state" do
    policy = Policy.new(max_altitude_cm: 100)
    state = %{mode: :sdk_mode, flying: false, battery: 100, takeoff_height_cm: 200}

    assert {:error, :safety, :max_altitude} =
             Safety.check(Command.takeoff(), policy, state)
  end
end
