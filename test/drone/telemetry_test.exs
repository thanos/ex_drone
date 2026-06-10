defmodule Drone.TelemetryTest do
  use ExUnit.Case, async: false

  alias Drone.Telemetry

  test "emits command start event" do
    handler_name = :"test_cmd_start_#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler_name,
      [:drone, :command, :start],
      fn _name, measurements, metadata, _config ->
        send(self(), {:telemetry, [:drone, :command, :start], measurements, metadata})
      end,
      nil
    )

    Telemetry.emit_command_start(:sim, :test, Drone.Command.takeoff())

    assert_receive {:telemetry, [:drone, :command, :start], %{command: :takeoff},
                    %{adapter: :sim, name: :test}}

    :telemetry.detach(handler_name)
  end

  test "emits connect start event" do
    handler_name = :"test_conn_start_#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler_name,
      [:drone, :connect, :start],
      fn _name, measurements, metadata, _config ->
        send(self(), {:telemetry, [:drone, :connect, :start], measurements, metadata})
      end,
      nil
    )

    Telemetry.emit_connect_start(:sim, :test)

    assert_receive {:telemetry, [:drone, :connect, :start], %{timestamp: _},
                    %{adapter: :sim, name: :test}}

    :telemetry.detach(handler_name)
  end

  test "emits safety reject event" do
    handler_name = :"test_safety_reject_#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler_name,
      [:drone, :safety, :reject],
      fn _name, measurements, metadata, _config ->
        send(self(), {:telemetry, [:drone, :safety, :reject], measurements, metadata})
      end,
      nil
    )

    Telemetry.emit_safety_reject(:sim, :test, :move, :max_altitude)

    assert_receive {:telemetry, [:drone, :safety, :reject],
                    %{command: :move, reason: :max_altitude}, %{adapter: :sim, name: :test}}

    :telemetry.detach(handler_name)
  end

  test "emits emergency event" do
    handler_name = :"test_emergency_#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler_name,
      [:drone, :emergency],
      fn _name, measurements, metadata, _config ->
        send(self(), {:telemetry, [:drone, :emergency], measurements, metadata})
      end,
      nil
    )

    Telemetry.emit_emergency(:sim, :test)

    assert_receive {:telemetry, [:drone, :emergency], %{timestamp: _},
                    %{adapter: :sim, name: :test}}

    :telemetry.detach(handler_name)
  end
end
