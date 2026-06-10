defmodule Drone.Safety do
  @moduledoc """
  Safety validation for drone commands.

  `Drone.Safety.check/3` is the primary entry point. It receives a command,
  a safety policy, and the current vehicle state, and returns either
  `{:ok, command}` if the command is approved, `{:ok, command, warnings}`
  if approved with warnings, or `{:error, :safety, reason}` if rejected.

  The safety pipeline is a pure function with no side effects. It is called
  by the `Drone.Vehicle` GenServer before sending any command to the adapter.

  Emergency commands bypass all safety checks.
  """

  alias Drone.{Command, Safety.Geofence, Safety.Policy}

  @type rejection_reason ::
          :command_not_allowed
          | :not_in_sdk_mode
          | :not_flying
          | :already_flying
          | :max_altitude
          | :max_distance
          | :low_battery
          | :geofence_violation

  @type warning :: :low_battery | :no_prop_guards

  @type vehicle_state :: %{
          mode: :idle | :sdk_mode | :flying | :emergency,
          x: integer(),
          y: integer(),
          z: integer(),
          yaw: integer(),
          battery: integer(),
          flying: boolean()
        }

  @doc """
  Validates a command against a safety policy and vehicle state.

  Returns:

    - `{:ok, command}` -- the command is approved
    - `{:ok, command, warnings}` -- the command is approved with warnings
    - `{:error, :safety, reason}` -- the command is rejected

  Emergency commands always pass.
  """
  @spec check(Command.t(), Policy.t(), vehicle_state()) ::
          {:ok, Command.t()}
          | {:ok, Command.t(), [warning()]}
          | {:error, :safety, rejection_reason()}
  def check(%Command{type: :emergency}, _policy, _state), do: {:ok, Command.emergency()}

  def check(%Command{} = cmd, %Policy{} = policy, %{} = state) do
    warnings = []

    with :ok <- validate_mode(cmd, state),
         :ok <- validate_allowlist(cmd, policy),
         :ok <- validate_flying_requirement(cmd, state),
         :ok <- validate_altitude(cmd, policy, state),
         :ok <- validate_distance(cmd, policy, state),
         :ok <- validate_battery(cmd, policy, state),
         :ok <- validate_geofence(cmd, policy, state),
         {:ok, extra_warnings} <- check_prop_guards(cmd, policy) do
      warnings = warnings ++ battery_warning(cmd, policy, state) ++ extra_warnings

      case warnings do
        [] -> {:ok, cmd}
        _ -> {:ok, cmd, warnings}
      end
    end
  end

  defp validate_mode(%Command{type: :sdk_mode}, %{mode: :idle}), do: :ok
  defp validate_mode(%Command{type: :sdk_mode}, %{mode: :sdk_mode}), do: :ok

  defp validate_mode(%Command{type: :query}, %{mode: mode}) when mode in [:sdk_mode, :flying],
    do: :ok

  defp validate_mode(_cmd, %{mode: :emergency}), do: {:error, :safety, :emergency_active}
  defp validate_mode(_cmd, %{mode: :idle}), do: {:error, :safety, :not_in_sdk_mode}
  defp validate_mode(_cmd, %{mode: :sdk_mode}), do: :ok
  defp validate_mode(_cmd, %{mode: :flying}), do: :ok

  defp validate_allowlist(%Command{type: :emergency}, _policy), do: :ok
  defp validate_allowlist(%Command{type: :sdk_mode}, _policy), do: :ok
  defp validate_allowlist(%Command{}, %Policy{allowlist: nil}), do: :ok

  defp validate_allowlist(%Command{type: type}, %Policy{allowlist: allowlist})
       when is_list(allowlist) do
    if type in allowlist or :emergency in allowlist do
      :ok
    else
      {:error, :safety, :command_not_allowed}
    end
  end

  defp validate_flying_requirement(%Command{type: :takeoff}, %{flying: false}), do: :ok

  defp validate_flying_requirement(%Command{type: :takeoff}, %{flying: true}),
    do: {:error, :safety, :already_flying}

  defp validate_flying_requirement(%Command{type: :land}, %{flying: true}), do: :ok

  defp validate_flying_requirement(%Command{type: :land}, %{flying: false}),
    do: {:error, :safety, :not_flying}

  defp validate_flying_requirement(%Command{type: type}, %{flying: true})
       when type in [:move, :rotate, :flip, :hover, :stop],
       do: :ok

  defp validate_flying_requirement(%Command{type: type}, %{flying: false})
       when type in [:move, :rotate, :flip, :hover, :stop],
       do: {:error, :safety, :not_flying}

  defp validate_flying_requirement(%Command{type: type}, %{flying: _})
       when type in [:sdk_mode, :query, :speed, :emergency],
       do: :ok

  defp validate_flying_requirement(_cmd, _state), do: :ok

  defp validate_altitude(
         %Command{type: :move, args: _args},
         %Policy{max_altitude_cm: nil},
         _state
       ),
       do: :ok

  defp validate_altitude(
         %Command{type: :move, args: args},
         %Policy{max_altitude_cm: max_z},
         %{} = state
       ) do
    direction = Keyword.get(args, :direction)
    distance = Keyword.get(args, :distance, 0)

    new_z =
      case direction do
        :up -> state[:z] + distance
        :down -> max(state[:z] - distance, 0)
        _ -> state[:z]
      end

    if new_z <= max_z do
      :ok
    else
      {:error, :safety, :max_altitude}
    end
  end

  defp validate_altitude(%Command{type: :takeoff}, %Policy{max_altitude_cm: nil}, _state), do: :ok

  defp validate_altitude(%Command{type: :takeoff}, %Policy{max_altitude_cm: max_z}, _state) do
    takeoff_height = 30

    if takeoff_height <= max_z do
      :ok
    else
      {:error, :safety, :max_altitude}
    end
  end

  defp validate_altitude(_cmd, _policy, _state), do: :ok

  defp validate_distance(%Command{type: type}, %Policy{max_distance_cm: nil}, _state)
       when type in [:move, :takeoff],
       do: :ok

  defp validate_distance(
         %Command{type: :move, args: args},
         %Policy{max_distance_cm: max_dist},
         %{} = state
       ) do
    distance = Keyword.get(args, :distance, 0)
    direction = Keyword.get(args, :direction)

    {dx, dy} =
      case direction do
        :forward -> {0, distance}
        :back -> {0, -distance}
        :left -> {-distance, 0}
        :right -> {distance, 0}
        _ -> {0, 0}
      end

    new_x = (state[:x] || 0) + dx
    new_y = (state[:y] || 0) + dy
    current_dist = :math.sqrt(new_x * new_x + new_y * new_y)

    if current_dist <= max_dist do
      :ok
    else
      {:error, :safety, :max_distance}
    end
  end

  defp validate_distance(%Command{type: :takeoff}, %Policy{max_distance_cm: _}, _state), do: :ok
  defp validate_distance(_cmd, _policy, _state), do: :ok

  defp validate_battery(
         %Command{type: :takeoff},
         %Policy{min_battery_percent: min_battery},
         %{} = state
       ) do
    battery = state[:battery] || 100

    if battery >= min_battery do
      :ok
    else
      {:error, :safety, :low_battery}
    end
  end

  defp validate_battery(_cmd, _policy, _state), do: :ok

  defp validate_geofence(%Command{type: :move, args: _args}, %Policy{geofence: nil}, _state),
    do: :ok

  defp validate_geofence(
         %Command{type: :move, args: args},
         %Policy{geofence: %Geofence{} = gf},
         %{} = state
       ) do
    distance = Keyword.get(args, :distance, 0)
    direction = Keyword.get(args, :direction)

    {dx, dy} =
      case direction do
        :forward -> {0, distance}
        :back -> {0, -distance}
        :left -> {-distance, 0}
        :right -> {distance, 0}
        _ -> {0, 0}
      end

    new_x = (state[:x] || 0) + dx
    new_y = (state[:y] || 0) + dy

    if Geofence.contains?(gf, {new_x, new_y}) do
      :ok
    else
      {:error, :safety, :geofence_violation}
    end
  end

  defp validate_geofence(_cmd, _policy, _state), do: :ok

  defp check_prop_guards(%Command{type: :flip}, %Policy{prop_guards: false}) do
    {:ok, [:no_prop_guards]}
  end

  defp check_prop_guards(_cmd, _policy), do: {:ok, []}

  defp battery_warning(
         %Command{type: :takeoff},
         %Policy{battery_warning_percent: warn_pct, min_battery_percent: min_pct},
         %{} = state
       ) do
    battery = state[:battery] || 100

    if battery < warn_pct and battery >= min_pct do
      [:low_battery]
    else
      []
    end
  end

  defp battery_warning(
         %Command{type: type},
         %Policy{battery_warning_percent: warn_pct},
         %{} = state
       )
       when type in [:move, :rotate, :flip, :hover] do
    battery = state[:battery] || 100

    if battery < warn_pct do
      [:low_battery]
    else
      []
    end
  end

  defp battery_warning(_cmd, _policy, _state), do: []
end
