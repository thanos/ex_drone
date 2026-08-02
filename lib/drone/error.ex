defmodule Drone.Error do
  @moduledoc """
  Error types and helpers for ex_drone.

  All errors in ex_drone follow explicit tuple conventions:

    - `{:error, reason}` for simple errors
    - `{:error, :safety, reason}` for safety rejections
    - `{:error, :invalid_command, details}` for command validation errors

  ## Examples

      {:error, :safety, :low_battery} = Drone.Error.safety(:low_battery)
      true = Drone.Error.safety_error?({:error, :safety, :low_battery})
      :timeout = Drone.Error.reason({:error, :timeout})
  """

  @typedoc """
  Reasons returned inside `{:error, :safety, reason}` from the safety pipeline.

  | Value | Typical cause |
  | --- | --- |
  | `:command_not_allowed` | Command not in the policy allowlist |
  | `:not_in_sdk_mode` | Flight command before SDK mode |
  | `:not_flying` / `:already_flying` | Mode mismatch for takeoff/land/move |
  | `:emergency_active` | Vehicle is in emergency mode |
  | `:max_altitude` / `:max_distance` | Policy ceiling / radius exceeded |
  | `:low_battery` | Battery below hard minimum |
  | `:geofence_violation` | Projected position outside geofence |
  | `:dangerous_without_prop_guards` | Flip without prop guards when required |
  | `:invalid_distance` / `:invalid_degrees` / `:invalid_speed` / `:invalid_seconds` | Arg out of SDK range |
  | `:stale_telemetry` | Telemetry older than policy max age |
  | `:estimator_not_ready` | Crazyflie estimator gate |

  ## Examples

      :geofence_violation
      :estimator_not_ready
  """
  @type safety_reason ::
          :command_not_allowed
          | :not_in_sdk_mode
          | :not_flying
          | :already_flying
          | :emergency_active
          | :max_altitude
          | :max_distance
          | :low_battery
          | :geofence_violation
          | :dangerous_without_prop_guards
          | :invalid_distance
          | :invalid_degrees
          | :invalid_speed
          | :invalid_seconds
          | :stale_telemetry
          | :estimator_not_ready

  @typedoc """
  Adapter / link failure reasons commonly returned as `{:error, reason}`.

  | Value | Typical cause |
  | --- | --- |
  | `:timeout` | UDP / IO timeout |
  | `:connection_error` / `:command_error` | Transport or protocol failure |
  | `:simulated_failure` | Sim adapter injected fault |
  | `:unsupported_command` | Adapter does not implement the command |
  | `:link_lost` / `:no_ack` | Crazyradio link failure |
  | `:usb_backend_unavailable` | Missing USB backend for `radio://` |
  | `:crazyradio_not_found` | No matching USB radio |
  | `:estimator_not_ready` | Adapter readiness gate |

  ## Examples

      :usb_backend_unavailable
      :link_lost
  """
  @type adapter_reason ::
          :timeout
          | :connection_error
          | :command_error
          | :not_in_sdk_mode
          | :not_flying
          | :already_flying
          | :emergency_active
          | :simulated_failure
          | :unsupported_command
          | :estimator_not_ready
          | :link_lost
          | :usb_backend_unavailable
          | :no_ack
          | :crazyradio_not_found

  @typedoc """
  Command construction validation reasons in
  `{:error, :invalid_command, reason}`.

  ## Examples

      :invalid_direction
      :invalid_flip_direction
  """
  @type command_reason ::
          :invalid_direction
          | :invalid_distance
          | :invalid_rotation
          | :invalid_degrees
          | :invalid_speed
          | :invalid_flip_direction
          | :invalid_query_type

  @typedoc """
  Any error reason atom (or opaque `term()`) found in error tuples.

  ## Examples

      :timeout
      :low_battery
      {:unsupported_protocol, 99}
  """
  @type reason :: safety_reason() | adapter_reason() | command_reason() | term()

  @doc """
  Creates a safety error tuple.

  ## Parameters

    * `reason` (`t:safety_reason/0`) — rejection reason

  ## Returns

  `{:error, :safety, reason}`.

  ## Examples

      {:error, :safety, :max_altitude} = Drone.Error.safety(:max_altitude)
  """
  @spec safety(safety_reason()) :: {:error, :safety, safety_reason()}
  def safety(reason), do: {:error, :safety, reason}

  @doc """
  Creates an adapter error tuple.

  ## Parameters

    * `reason` (`t:adapter_reason/0`) — adapter failure reason

  ## Returns

  `{:error, reason}`.

  ## Examples

      {:error, :timeout} = Drone.Error.adapter(:timeout)
  """
  @spec adapter(adapter_reason()) :: {:error, adapter_reason()}
  def adapter(reason), do: {:error, reason}

  @doc """
  Creates an invalid command error tuple.

  ## Parameters

    * `reason` (`t:command_reason/0`) — validation failure

  ## Returns

  `{:error, :invalid_command, reason}`.

  ## Examples

      {:error, :invalid_command, :invalid_distance} =
        Drone.Error.invalid_command(:invalid_distance)
  """
  @spec invalid_command(command_reason()) :: {:error, :invalid_command, command_reason()}
  def invalid_command(reason), do: {:error, :invalid_command, reason}

  @doc """
  Checks if an error is a safety error.

  ## Parameters

    * `error` (`term()`) — candidate error tuple or other value

  ## Returns

  `boolean()`.

  ## Examples

      true = Drone.Error.safety_error?({:error, :safety, :low_battery})
      false = Drone.Error.safety_error?({:error, :timeout})
  """
  @spec safety_error?(term()) :: boolean()
  def safety_error?({:error, :safety, _}), do: true
  def safety_error?(_), do: false

  @doc """
  Checks if an error is a simple adapter-style `{:error, atom()}` tuple.

  ## Parameters

    * `error` (`term()`)

  ## Returns

  `boolean()`.

  ## Examples

      true = Drone.Error.adapter_error?({:error, :link_lost})
      false = Drone.Error.adapter_error?({:error, :safety, :low_battery})
  """
  @spec adapter_error?(term()) :: boolean()
  def adapter_error?({:error, reason}) when is_atom(reason), do: true
  def adapter_error?(_), do: false

  @doc """
  Checks if an error is an invalid command error.

  ## Parameters

    * `error` (`term()`)

  ## Returns

  `boolean()`.

  ## Examples

      true =
        Drone.Error.invalid_command_error?(
          {:error, :invalid_command, :invalid_speed}
        )
  """
  @spec invalid_command_error?(term()) :: boolean()
  def invalid_command_error?({:error, :invalid_command, _}), do: true
  def invalid_command_error?(_), do: false

  @doc """
  Extracts the reason from any error tuple.

  ## Parameters

    * `error` — `{:error, atom()}`, `{:error, :safety, atom()}`, or
      `{:error, :invalid_command, atom()}`

  ## Returns

  The inner `atom()` reason.

  ## Examples

      :low_battery = Drone.Error.reason({:error, :safety, :low_battery})
      :timeout = Drone.Error.reason({:error, :timeout})
      :invalid_distance =
        Drone.Error.reason({:error, :invalid_command, :invalid_distance})
  """
  @spec reason({:error, atom()} | {:error, :safety, atom()} | {:error, :invalid_command, atom()}) ::
          atom()
  def reason({:error, :safety, r}), do: r
  def reason({:error, :invalid_command, r}), do: r
  def reason({:error, r}), do: r
end
