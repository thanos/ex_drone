defmodule Drone.Telemetry do
  @moduledoc """
  Telemetry event helpers for ex_drone.

  Emits standard Elixir `:telemetry` events for vehicle and swarm lifecycle.
  Event names follow `[:drone, namespace, action]`.

  Attach handlers with `:telemetry.attach/4` or `:telemetry.attach_many/4`.

  ## Vehicle events

    * `[:drone, :connect, :start | :stop | :error]`
    * `[:drone, :disconnect]`
    * `[:drone, :command, :start | :stop | :error]`
    * `[:drone, :safety, :reject | :warning]`
    * `[:drone, :telemetry, :update]`
    * `[:drone, :emergency]`

  ## Swarm events

    * `[:drone, :swarm, :start | :stop]`
    * `[:drone, :swarm, :command, :start | :stop | :error]`
    * `[:drone, :swarm, :emergency]`

  ## Example

      :telemetry.attach(
        "drone-logger",
        [:drone, :command, :stop],
        fn _event, measurements, metadata, _config ->
          IO.inspect({measurements.command, metadata.name})
        end,
        nil
      )
  """

  @doc """
  Emits `[:drone, :connect, :start]`.

  ## Parameters

    * `adapter` (`atom()`) — e.g. `:sim`, `:tello`
    * `name` (`atom()`) — vehicle name

  ## Returns

  `:ok`
  """
  @spec emit_connect_start(atom(), atom()) :: :ok
  def emit_connect_start(adapter, name) do
    :telemetry.execute(
      [:drone, :connect, :start],
      %{timestamp: System.monotonic_time()},
      %{adapter: adapter, name: name}
    )
  end

  @doc """
  Emits `[:drone, :connect, :stop]` after a successful connect.

  ## Parameters

    * `adapter` (`atom()`)
    * `name` (`atom()`)
    * `duration` (`non_neg_integer()`) — monotonic time units

  ## Returns

  `:ok`
  """
  @spec emit_connect_stop(atom(), atom(), non_neg_integer()) :: :ok
  def emit_connect_stop(adapter, name, duration) do
    :telemetry.execute(
      [:drone, :connect, :stop],
      %{duration: duration, timestamp: System.monotonic_time()},
      %{adapter: adapter, name: name}
    )
  end

  @doc """
  Emits `[:drone, :connect, :error]`.

  ## Parameters

    * `adapter` (`atom()`)
    * `name` (`atom()`)
    * `reason` (`term()`)

  ## Returns

  `:ok`
  """
  @spec emit_connect_error(atom(), atom(), term()) :: :ok
  def emit_connect_error(adapter, name, reason) do
    :telemetry.execute(
      [:drone, :connect, :error],
      %{timestamp: System.monotonic_time()},
      %{adapter: adapter, name: name, reason: reason}
    )
  end

  @doc """
  Emits `[:drone, :disconnect]`.

  ## Parameters

    * `adapter` (`atom()`)
    * `name` (`atom()`)

  ## Returns

  `:ok`
  """
  @spec emit_disconnect(atom(), atom()) :: :ok
  def emit_disconnect(adapter, name) do
    :telemetry.execute(
      [:drone, :disconnect],
      %{timestamp: System.monotonic_time()},
      %{adapter: adapter, name: name}
    )
  end

  @doc """
  Emits `[:drone, :command, :start]` after safety approval.

  ## Parameters

    * `adapter` (`atom()`)
    * `name` (`atom()`)
    * `command` (`Drone.Command.t()`)

  ## Returns

  `:ok`
  """
  @spec emit_command_start(atom(), atom(), Drone.Command.t()) :: :ok
  def emit_command_start(adapter, name, %Drone.Command{} = command) do
    :telemetry.execute(
      [:drone, :command, :start],
      %{command: command.type, timestamp: System.monotonic_time()},
      %{adapter: adapter, name: name}
    )
  end

  @doc """
  Emits `[:drone, :command, :stop]` on success.

  ## Parameters

    * `adapter` (`atom()`)
    * `name` (`atom()`)
    * `command_type` (`atom()`) — e.g. `:takeoff`
    * `result` (`atom()`) — e.g. `:ok`, `:dry_run`
    * `duration` (`non_neg_integer()`)

  ## Returns

  `:ok`
  """
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

  @doc """
  Emits `[:drone, :command, :error]` when the adapter fails.

  ## Parameters

    * `adapter` (`atom()`)
    * `name` (`atom()`)
    * `command_type` (`atom()`)
    * `reason` (`atom()` | `term()`)
    * `duration` (`non_neg_integer()`)

  ## Returns

  `:ok`
  """
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

  @doc """
  Emits `[:drone, :safety, :reject]`.

  ## Parameters

    * `adapter` (`atom()`)
    * `name` (`atom()`)
    * `command_type` (`atom()`)
    * `reason` (`atom()`) — e.g. `:max_altitude`, `:low_battery`

  ## Returns

  `:ok`
  """
  @spec emit_safety_reject(atom(), atom(), atom(), atom()) :: :ok
  def emit_safety_reject(adapter, name, command_type, reason) do
    :telemetry.execute(
      [:drone, :safety, :reject],
      %{command: command_type, reason: reason, timestamp: System.monotonic_time()},
      %{adapter: adapter, name: name}
    )
  end

  @doc """
  Emits `[:drone, :safety, :warning]` when a command is allowed with warnings.

  ## Parameters

    * `adapter` (`atom()`)
    * `name` (`atom()`)
    * `command_type` (`atom()`)
    * `warning` (`atom()`) — e.g. `:no_prop_guards`

  ## Returns

  `:ok`
  """
  @spec emit_safety_warning(atom(), atom(), atom(), atom()) :: :ok
  def emit_safety_warning(adapter, name, command_type, warning) do
    :telemetry.execute(
      [:drone, :safety, :warning],
      %{command: command_type, warning: warning, timestamp: System.monotonic_time()},
      %{adapter: adapter, name: name}
    )
  end

  @doc """
  Emits `[:drone, :telemetry, :update]` with pose / battery measurements.

  ## Parameters

    * `adapter` (`atom()`)
    * `name` (`atom()`)
    * `telemetry` (`map()`) — typically includes `:x`, `:y`, `:z`, `:yaw`, `:battery`

  ## Returns

  `:ok`
  """
  @spec emit_telemetry_update(atom(), atom(), map()) :: :ok
  def emit_telemetry_update(adapter, name, telemetry) do
    :telemetry.execute(
      [:drone, :telemetry, :update],
      Map.merge(telemetry, %{timestamp: System.monotonic_time()}),
      %{adapter: adapter, name: name}
    )
  end

  @doc """
  Emits `[:drone, :emergency]` when an emergency stop is requested.

  ## Parameters

    * `adapter` (`atom()`)
    * `name` (`atom()`)

  ## Returns

  `:ok`
  """
  @spec emit_emergency(atom(), atom()) :: :ok
  def emit_emergency(adapter, name) do
    :telemetry.execute(
      [:drone, :emergency],
      %{timestamp: System.monotonic_time()},
      %{adapter: adapter, name: name}
    )
  end

  @doc """
  Emits `[:drone, :swarm, :start]` when a swarm coordinator starts.

  ## Parameters

    * `swarm` (`atom() | nil`) — registered swarm name, or `nil` if anonymous
    * `members` (`[atom()]`) — ordered member drone names

  ## Returns

  `:ok`

  ## Example

      Drone.Telemetry.emit_swarm_start(:advisors, [:good, :bad])
  """
  @spec emit_swarm_start(atom() | nil, [atom()]) :: :ok
  def emit_swarm_start(swarm, members) do
    :telemetry.execute(
      [:drone, :swarm, :start],
      %{timestamp: System.monotonic_time()},
      %{swarm: swarm, members: members}
    )
  end

  @doc """
  Emits `[:drone, :swarm, :stop]` when a swarm coordinator terminates.

  ## Parameters

    * `swarm` (`atom() | nil`)
    * `members` (`[atom()]`)
    * `reason` (`term()`, optional) — OTP terminate reason (`:normal`,
      `:shutdown`, crash reason, etc.)

  ## Returns

  `:ok`
  """
  @spec emit_swarm_stop(atom() | nil, [atom()], term()) :: :ok
  def emit_swarm_stop(swarm, members, reason \\ :normal) do
    :telemetry.execute(
      [:drone, :swarm, :stop],
      %{timestamp: System.monotonic_time()},
      %{swarm: swarm, members: members, reason: reason}
    )
  end

  @doc """
  Emits `[:drone, :swarm, :command, :start]` before a coordinated op.

  ## Parameters

    * `swarm` (`atom() | nil`)
    * `members` (`[atom()]`)
    * `command` (`atom()`) — e.g. `:takeoff`, `:land`, `:run`, `:connect_sdk`

  ## Returns

  `:ok`
  """
  @spec emit_swarm_command_start(atom() | nil, [atom()], atom()) :: :ok
  def emit_swarm_command_start(swarm, members, command) do
    :telemetry.execute(
      [:drone, :swarm, :command, :start],
      %{command: command, timestamp: System.monotonic_time()},
      %{swarm: swarm, members: members}
    )
  end

  @doc """
  Emits `[:drone, :swarm, :command, :stop]` after a successful coordinated op.

  ## Parameters

    * `swarm` (`atom() | nil`)
    * `members` (`[atom()]`)
    * `command` (`atom()`)
    * `duration` (`non_neg_integer()`)

  ## Returns

  `:ok`
  """
  @spec emit_swarm_command_stop(atom() | nil, [atom()], atom(), non_neg_integer()) :: :ok
  def emit_swarm_command_stop(swarm, members, command, duration) do
    :telemetry.execute(
      [:drone, :swarm, :command, :stop],
      %{command: command, duration: duration, timestamp: System.monotonic_time()},
      %{swarm: swarm, members: members}
    )
  end

  @doc """
  Emits `[:drone, :swarm, :command, :error]` on partial or plan failure.

  ## Parameters

    * `swarm` (`atom() | nil`)
    * `members` (`[atom()]`)
    * `command` (`atom()`)
    * `reason` (`term()`) — e.g. `:partial`, `:separation_violation`
    * `duration` (`non_neg_integer()`)

  ## Returns

  `:ok`
  """
  @spec emit_swarm_command_error(atom() | nil, [atom()], atom(), term(), non_neg_integer()) :: :ok
  def emit_swarm_command_error(swarm, members, command, reason, duration) do
    :telemetry.execute(
      [:drone, :swarm, :command, :error],
      %{
        command: command,
        reason: reason,
        duration: duration,
        timestamp: System.monotonic_time()
      },
      %{swarm: swarm, members: members}
    )
  end

  @doc """
  Emits `[:drone, :swarm, :emergency]` when swarm-wide emergency is requested.

  ## Parameters

    * `swarm` (`atom() | nil`)
    * `members` (`[atom()]`)

  ## Returns

  `:ok`
  """
  @spec emit_swarm_emergency(atom() | nil, [atom()]) :: :ok
  def emit_swarm_emergency(swarm, members) do
    :telemetry.execute(
      [:drone, :swarm, :emergency],
      %{timestamp: System.monotonic_time()},
      %{swarm: swarm, members: members}
    )
  end
end
