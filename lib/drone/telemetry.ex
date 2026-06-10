defmodule Drone.Telemetry do
  @moduledoc """
  Telemetry event helpers for ex_drone.

  This module provides convenience functions for emitting `:telemetry`
  events throughout the drone command pipeline. All events follow the
  naming convention `[:drone, namespace, action]`.
  """

  @spec emit_connect_start(atom(), atom()) :: :ok
  def emit_connect_start(adapter, name) do
    :telemetry.execute(
      [:drone, :connect, :start],
      %{timestamp: System.monotonic_time()},
      %{adapter: adapter, name: name}
    )
  end

  @spec emit_connect_stop(atom(), atom(), non_neg_integer()) :: :ok
  def emit_connect_stop(adapter, name, duration) do
    :telemetry.execute(
      [:drone, :connect, :stop],
      %{duration: duration, timestamp: System.monotonic_time()},
      %{adapter: adapter, name: name}
    )
  end

  @spec emit_connect_error(atom(), atom(), term()) :: :ok
  def emit_connect_error(adapter, name, reason) do
    :telemetry.execute(
      [:drone, :connect, :error],
      %{timestamp: System.monotonic_time()},
      %{adapter: adapter, name: name, reason: reason}
    )
  end

  @spec emit_disconnect(atom(), atom()) :: :ok
  def emit_disconnect(adapter, name) do
    :telemetry.execute(
      [:drone, :disconnect],
      %{timestamp: System.monotonic_time()},
      %{adapter: adapter, name: name}
    )
  end

  @spec emit_command_start(atom(), atom(), Drone.Command.t()) :: :ok
  def emit_command_start(adapter, name, %Drone.Command{} = command) do
    :telemetry.execute(
      [:drone, :command, :start],
      %{command: command.type, timestamp: System.monotonic_time()},
      %{adapter: adapter, name: name}
    )
  end

  @spec emit_command_stop(atom(), atom(), atom(), atom(), non_neg_integer()) :: :ok
  def emit_command_stop(adapter, name, command_type, result, duration) do
    :telemetry.execute(
      [:drone, :command, :stop],
      %{
        command: command_type,
        result: result,
        duration: duration,
        timestamp: System.monotonic_time()
      },
      %{adapter: adapter, name: name}
    )
  end

  @spec emit_command_error(atom(), atom(), atom(), atom(), non_neg_integer()) :: :ok
  def emit_command_error(adapter, name, command_type, reason, duration) do
    :telemetry.execute(
      [:drone, :command, :error],
      %{
        command: command_type,
        reason: reason,
        duration: duration,
        timestamp: System.monotonic_time()
      },
      %{adapter: adapter, name: name}
    )
  end

  @spec emit_safety_reject(atom(), atom(), atom(), atom()) :: :ok
  def emit_safety_reject(adapter, name, command_type, reason) do
    :telemetry.execute(
      [:drone, :safety, :reject],
      %{command: command_type, reason: reason, timestamp: System.monotonic_time()},
      %{adapter: adapter, name: name}
    )
  end

  @spec emit_safety_warning(atom(), atom(), atom(), atom()) :: :ok
  def emit_safety_warning(adapter, name, command_type, warning) do
    :telemetry.execute(
      [:drone, :safety, :warning],
      %{command: command_type, warning: warning, timestamp: System.monotonic_time()},
      %{adapter: adapter, name: name}
    )
  end

  @spec emit_telemetry_update(atom(), atom(), map()) :: :ok
  def emit_telemetry_update(adapter, name, telemetry) do
    :telemetry.execute(
      [:drone, :telemetry, :update],
      Map.merge(telemetry, %{timestamp: System.monotonic_time()}),
      %{adapter: adapter, name: name}
    )
  end

  @spec emit_emergency(atom(), atom()) :: :ok
  def emit_emergency(adapter, name) do
    :telemetry.execute(
      [:drone, :emergency],
      %{timestamp: System.monotonic_time()},
      %{adapter: adapter, name: name}
    )
  end
end
