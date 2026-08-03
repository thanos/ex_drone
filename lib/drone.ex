defmodule Drone do
  @moduledoc """
  BEAM-native drone control for Elixir.

  ex_drone provides a supervised, safety-first API for controlling programmable
  drones. It supports pluggable adapters (simulator, Tello, and more in the
  future), a safety pipeline that validates every command, and telemetry events
  for observability.

  ## Getting Started

      # Connect to the simulator (no hardware needed)
      {:ok, drone} = Drone.connect(:sim, name: :test)

      # Enter SDK mode (required for Tello, automatic for sim)
      Drone.connect_sdk(drone)

      # Fly
      Drone.takeoff(drone)
      Drone.move(drone, :up, 40)
      Drone.move(drone, :forward, 100)
      Drone.rotate(drone, :cw, 90)
      Drone.land(drone)

      # Disconnect
      Drone.disconnect(drone)

  ## Safety

  All commands pass through a safety pipeline before reaching the drone.
  Safety policies can be configured at connection time:

      {:ok, drone} = Drone.connect(:sim,
        name: :classroom,
        safety: [indoor: true, prop_guards: true]
      )

  See `Drone.Safety.Policy` for all safety options.

  **Safety warning**: Drones are physical devices that can cause injury.
  Always test in the simulator first. Use prop guards. Do not fly near
  faces. Have an emergency stop ready. Understand local laws and regulations.
  """

  alias Drone.{Command, Vehicle}

  @typedoc """
  Registered name of a connected drone vehicle.

  Always an atom looked up via `Drone.Vehicle.Registry` (pids are not accepted
  by the public API).

  ## Examples

      :my_drone
      :tello_1
      :good_advisor
  """
  @type drone :: atom()

  @typedoc """
  Result of `connect/2`.

  * `{:ok, atom()}` — connected; value is the drone name
  * `{:error, :name_already_taken}` — name already registered
  * `{:error, term()}` — adapter or supervisor failure

  ## Examples

      {:ok, :demo}
      {:error, :name_already_taken}
  """
  @type connect_result :: {:ok, atom()} | {:error, term()}

  @typedoc """
  Result of flight / control commands that go through the safety pipeline.

  * `:ok` — success with no payload
  * `{:ok, term()}` — success with a value (rare for flight cmds; used when
    the adapter returns a non-`:ok` reply)
  * `{:error, :safety, term()}` — rejected by `Drone.Safety`
  * `{:error, term()}` — adapter / connectivity failure

  ## Examples

      :ok
      {:error, :safety, :max_altitude}
      {:error, :not_connected}
  """
  @type command_result :: :ok | {:ok, term()} | {:error, :safety, term()} | {:error, term()}

  @doc """
  Connects to a drone and starts a supervised process.

  Accepts an adapter identifier (`:sim`, `:tello`, or `:crazyflie`) or a module that
  implements `Drone.Adapter`. Options are passed to the adapter and
  safety policy.

  ## Parameters

    * `adapter` (`atom() | module()`) — `:sim`, `:tello`, or adapter module
    * `opts` (`keyword()`) — connection options:
      * `:name` (`atom()`, required) — unique vehicle name
      * `:safety` (`keyword() | Drone.Safety.Policy.t()`) — safety policy
      * remaining keys — forwarded to the adapter (e.g. `:initial_x`,
        `:drone_ip`, `:battery`)

  ## Returns

  `t:connect_result/0`

  ## Examples

      {:ok, drone} = Drone.connect(:sim, name: :test)
      {:ok, drone} = Drone.connect(:tello, name: :tello_1, drone_ip: {192, 168, 10, 1})
      {:ok, drone} = Drone.connect(:sim, name: :left, initial_x: -50, safety: [indoor: true])
  """
  @spec connect(atom() | module(), keyword()) :: connect_result()
  def connect(adapter, opts) when is_atom(adapter) and is_list(opts) do
    name = Keyword.fetch!(opts, :name)
    opts = Keyword.put(opts, :adapter, adapter)

    case Drone.Supervisor.start_vehicle(opts) do
      {:ok, _pid} -> {:ok, name}
      {:error, {:already_started, _pid}} -> {:error, :name_already_taken}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sends the SDK mode activation command.

  Required for Tello drones before any other command. The simulator
  enters SDK mode automatically on connect but still accepts this command.

  ## Parameters

    * `drone` (`t:drone/0`) — registered vehicle name

  ## Returns

  `t:command_result/0`

  ## Example

      :ok = Drone.connect_sdk(:my_drone)
  """
  @spec connect_sdk(drone()) :: command_result()
  def connect_sdk(drone) do
    command(drone, Command.sdk_mode())
  end

  @doc """
  Sends a takeoff command.

  The drone must be in SDK mode and not already flying. Safety checks
  are applied (battery, altitude, geofence, etc.).

  ## Parameters

    * `drone` (`t:drone/0`)

  ## Returns

  `t:command_result/0`

  ## Example

      :ok = Drone.takeoff(:my_drone)
      {:error, :safety, :low_battery} = Drone.takeoff(:low_bat)
  """
  @spec takeoff(drone()) :: command_result()
  def takeoff(drone) do
    command(drone, Command.takeoff())
  end

  @doc """
  Sends a land command.

  The drone must be flying.

  ## Parameters

    * `drone` (`t:drone/0`)

  ## Returns

  `t:command_result/0`

  ## Example

      :ok = Drone.land(:my_drone)
  """
  @spec land(drone()) :: command_result()
  def land(drone) do
    command(drone, Command.land())
  end

  @doc """
  Sends an emergency stop command.

  Bypasses all safety checks and immediately stops the drone's motors.
  Use only in actual emergencies.

  ## Parameters

    * `drone` (`t:drone/0`)

  ## Returns

    * `:ok`
    * `{:error, term()}`

  ## Example

      :ok = Drone.emergency(:my_drone)
  """
  @spec emergency(drone()) :: :ok | {:error, term()}
  def emergency(drone) do
    call(drone, :emergency)
  end

  @doc """
  Sends a movement command.

  ## Parameters

    * `drone` (`t:drone/0`)
    * `direction` (`Drone.Command.direction()`) — `:up` \| `:down` \| `:left` \|
      `:right` \| `:forward` \| `:back`
    * `distance` (`pos_integer()`) — centimeters (20..500)

  ## Returns

  `t:command_result/0`

  ## Example

      :ok = Drone.move(:my_drone, :forward, 100)
  """
  @spec move(drone(), Command.direction(), pos_integer()) :: command_result()
  def move(drone, direction, distance) do
    command(drone, Command.move(direction, distance))
  end

  @doc """
  Sends a rotation command.

  ## Parameters

    * `drone` (`t:drone/0`)
    * `direction` (`Drone.Command.rotation()`) — `:cw` or `:ccw`
    * `degrees` (`pos_integer()`) — 1..3600

  ## Returns

  `t:command_result/0`

  ## Example

      :ok = Drone.rotate(:my_drone, :cw, 90)
  """
  @spec rotate(drone(), Command.rotation(), pos_integer()) :: command_result()
  def rotate(drone, direction, degrees) do
    command(drone, Command.rotate(direction, degrees))
  end

  @doc """
  Sends a flip command.

  ## Parameters

    * `drone` (`t:drone/0`)
    * `direction` (`Drone.Command.flip_direction()`) — `:left` \| `:right` \|
      `:forward` \| `:back`

  ## Returns

  `t:command_result/0` (may include a prop-guards warning path via telemetry)

  ## Example

      :ok = Drone.flip(:my_drone, :left)
  """
  @spec flip(drone(), Command.flip_direction()) :: command_result()
  def flip(drone, direction) do
    command(drone, Command.flip(direction))
  end

  @doc """
  Sends a hover command.

  ## Parameters

    * `drone` (`t:drone/0`)
    * `opts` (`keyword()`) — `:seconds` (`pos_integer()`, default `1`)

  ## Returns

  `t:command_result/0`

  ## Example

      :ok = Drone.hover(:my_drone, seconds: 5)
  """
  @spec hover(drone(), keyword()) :: command_result()
  def hover(drone, opts \\ []) do
    seconds = Keyword.get(opts, :seconds, 1)
    command(drone, Command.hover(seconds))
  end

  @doc """
  Sets the drone speed.

  ## Parameters

    * `drone` (`t:drone/0`)
    * `speed` (`pos_integer()`) — cm/s (10..100)

  ## Returns

  `t:command_result/0`

  ## Example

      :ok = Drone.set_speed(:my_drone, 50)
  """
  @spec set_speed(drone(), pos_integer()) :: command_result()
  def set_speed(drone, speed) do
    command(drone, Command.speed(speed))
  end

  @doc """
  Sends a stop command (hover in place / cancel velocity).

  ## Parameters

    * `drone` (`t:drone/0`)

  ## Returns

  `t:command_result/0`

  ## Example

      :ok = Drone.stop(:my_drone)
  """
  @spec stop(drone()) :: command_result()
  def stop(drone) do
    command(drone, Command.stop())
  end

  @doc """
  Sends a query command to the drone.

  ## Parameters

    * `drone` (`t:drone/0`)
    * `type` (`Drone.Command.query_type()`) — `:battery`, `:height`, `:speed`,
      `:time`, `:wifi`, `:sdk_version`, or `:serial_number`

  ## Returns

    * `{:ok, term()}` — query value
    * `{:error, :safety, term()}`
    * `{:error, term()}`

  ## Example

      {:ok, percent} = Drone.query(:my_drone, :battery)
  """
  @spec query(drone(), Command.query_type()) :: {:ok, term()} | {:error, term()}
  def query(drone, type) do
    call(drone, {:command, Command.query(type)})
  end

  @doc """
  Retrieves telemetry data from the drone.

  ## Parameters

    * `drone` (`t:drone/0`)

  ## Returns

    * `{:ok, map()}` — includes `:x`, `:y`, `:z`, `:yaw`, `:battery`, `:flying`, `:mode`, ...
    * `{:error, term()}`

  ## Example

      {:ok, tel} = Drone.telemetry(:my_drone)
      tel.z
      #=> 30
  """
  @spec telemetry(drone()) :: {:ok, map()} | {:error, term()}
  def telemetry(drone) do
    call(drone, :telemetry)
  end

  @doc """
  Returns capability metadata for the connected adapter.

  ## Parameters

    * `drone` (`t:drone/0`)

  ## Returns

  `Drone.Adapter.Capabilities.t()` map.

  ## Example

      caps = Drone.capabilities(:my_drone)
      caps.sdk_mode
  """
  @spec capabilities(drone()) :: Drone.Adapter.Capabilities.t()
  def capabilities(drone) do
    call(drone, :capabilities)
  end

  @doc """
  Disconnects from the drone and stops the vehicle process.

  ## Parameters

    * `drone` (`t:drone/0`)

  ## Returns

    * `:ok`
    * `{:error, :not_connected}`

  ## Example

      :ok = Drone.disconnect(:my_drone)
  """
  @spec disconnect(drone()) :: :ok | {:error, :not_connected}
  def disconnect(drone) do
    call(drone, :disconnect)
  end

  # Sends a command to the vehicle process and normalizes the reply.
  defp command(drone, %Command{} = cmd) do
    case call(drone, {:command, cmd}) do
      {:ok, :ok} -> :ok
      {:ok, :dry_run} -> :ok
      {:ok, value} -> {:ok, value}
      {:error, :safety, reason} -> {:error, :safety, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  # Resolves the drone process and issues a GenServer call, returning
  # {:error, :not_connected} when no process is registered for the name.
  defp call(drone, message) do
    case Vehicle.whereis(drone) do
      nil -> {:error, :not_connected}
      pid -> GenServer.call(pid, message)
    end
  end
end
