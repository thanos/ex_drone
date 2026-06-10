defmodule Drone.Error do
  @moduledoc """
  Error types and helpers for ex_drone.

  All errors in ex_drone follow explicit tuple conventions:

    - `{:error, reason}` for simple errors
    - `{:error, :safety, reason}` for safety rejections
    - `{:error, :invalid_command, details}` for command validation errors
  """

  @type safety_reason ::
          :command_not_allowed
          | :not_in_sdk_mode
          | :not_flying
          | :already_flying
          | :max_altitude
          | :max_distance
          | :low_battery
          | :geofence_violation
          | :dangerous_without_prop_guards

  @type adapter_reason ::
          :timeout
          | :connection_error
          | :command_error
          | :not_in_sdk_mode
          | :not_flying
          | :already_flying
          | :emergency_active
          | :simulated_failure

  @type command_reason ::
          :invalid_direction
          | :invalid_distance
          | :invalid_rotation
          | :invalid_degrees
          | :invalid_speed
          | :invalid_flip_direction
          | :invalid_query_type

  @type reason :: safety_reason() | adapter_reason() | command_reason() | term()

  @doc """
  Creates a safety error tuple.
  """
  @spec safety(safety_reason()) :: {:error, :safety, safety_reason()}
  def safety(reason), do: {:error, :safety, reason}

  @doc """
  Creates an adapter error tuple.
  """
  @spec adapter(adapter_reason()) :: {:error, adapter_reason()}
  def adapter(reason), do: {:error, reason}

  @doc """
  Creates an invalid command error tuple.
  """
  @spec invalid_command(command_reason()) :: {:error, :invalid_command, command_reason()}
  def invalid_command(reason), do: {:error, :invalid_command, reason}

  @doc """
  Checks if an error is a safety error.
  """
  @spec safety_error?(term()) :: boolean()
  def safety_error?({:error, :safety, _}), do: true
  def safety_error?(_), do: false

  @doc """
  Checks if an error is an adapter error.
  """
  @spec adapter_error?(term()) :: boolean()
  def adapter_error?({:error, reason}) when is_atom(reason), do: true
  def adapter_error?(_), do: false

  @doc """
  Checks if an error is an invalid command error.
  """
  @spec invalid_command_error?(term()) :: boolean()
  def invalid_command_error?({:error, :invalid_command, _}), do: true
  def invalid_command_error?(_), do: false

  @doc """
  Extracts the reason from any error tuple.
  """
  @spec reason({:error, atom()} | {:error, :safety, atom()} | {:error, :invalid_command, atom()}) ::
          atom()
  def reason({:error, :safety, r}), do: r
  def reason({:error, :invalid_command, r}), do: r
  def reason({:error, r}), do: r
end
