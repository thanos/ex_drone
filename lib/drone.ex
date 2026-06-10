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

  @type drone :: atom() | pid()
  @type connect_result :: {:ok, atom()} | {:error, term()}

  @doc """
  Connects to a drone and starts a supervised process.

  Accepts an adapter identifier (`:sim` or `:tello`) or a module that
  implements `Drone.Adapter`. Options are passed to the adapter and
  safety policy.

  ## Options

    - `:name` (required) -- a unique name for this drone process
    - `:safety` -- keyword list of safety policy options (see `Drone.Safety.Policy.new/1`)
    - All other options are passed to the adapter

  ## Examples

      {:ok, drone} = Drone.connect(:sim, name: :test)
      {:ok, drone} = Drone.connect(:tello, name: :tello_1, drone_ip: {192, 168, 10, 1})
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
  enters SDK mode automatically on connect.
  """
  @spec connect_sdk(drone()) :: :ok | {:error, term()}
  def connect_sdk(drone) do
    case GenServer.call(Vehicle.whereis(drone), {:command, Command.sdk_mode()}) do
      {:ok, :ok} -> :ok
      {:ok, :dry_run} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sends a takeoff command.

  The drone must be in SDK mode and not already flying. Safety checks
  are applied (battery, altitude, geofence, etc.).
  """
  @spec takeoff(drone()) :: :ok | {:error, term()}
  def takeoff(drone) do
    case GenServer.call(Vehicle.whereis(drone), {:command, Command.takeoff()}) do
      {:ok, :ok} -> :ok
      {:ok, :dry_run} -> :ok
      {:error, :safety, reason} -> {:error, :safety, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sends a land command.

  The drone must be flying.
  """
  @spec land(drone()) :: :ok | {:error, term()}
  def land(drone) do
    case GenServer.call(Vehicle.whereis(drone), {:command, Command.land()}) do
      {:ok, :ok} -> :ok
      {:ok, :dry_run} -> :ok
      {:error, :safety, reason} -> {:error, :safety, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sends an emergency stop command.

  This command bypasses all safety checks and immediately stops the
  drone's motors. Use only in actual emergencies.
  """
  @spec emergency(drone()) :: :ok | {:error, term()}
  def emergency(drone) do
    GenServer.call(Vehicle.whereis(drone), :emergency)
  end

  @doc """
  Sends a movement command.

  Direction must be one of: `:up`, `:down`, `:left`, `:right`,
  `:forward`, `:back`.
  Distance must be between 20 and 500 cm.
  """
  @spec move(drone(), Command.direction(), pos_integer()) :: :ok | {:error, term()}
  def move(drone, direction, distance) do
    case GenServer.call(Vehicle.whereis(drone), {:command, Command.move(direction, distance)}) do
      {:ok, :ok} -> :ok
      {:ok, :dry_run} -> :ok
      {:error, :safety, reason} -> {:error, :safety, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sends a rotation command.

  Direction must be `:cw` (clockwise) or `:ccw` (counter-clockwise).
  Degrees must be between 1 and 3600.
  """
  @spec rotate(drone(), Command.rotation(), pos_integer()) :: :ok | {:error, term()}
  def rotate(drone, direction, degrees) do
    case GenServer.call(Vehicle.whereis(drone), {:command, Command.rotate(direction, degrees)}) do
      {:ok, :ok} -> :ok
      {:ok, :dry_run} -> :ok
      {:error, :safety, reason} -> {:error, :safety, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sends a flip command.

  Direction must be one of: `:left`, `:right`, `:forward`, `:back`.
  The drone must be flying. A safety warning is emitted if prop guards
  are not installed.
  """
  @spec flip(drone(), Command.flip_direction()) :: :ok | {:error, term()}
  def flip(drone, direction) do
    case GenServer.call(Vehicle.whereis(drone), {:command, Command.flip(direction)}) do
      {:ok, :ok} -> :ok
      {:ok, :dry_run} -> :ok
      {:error, :safety, reason} -> {:error, :safety, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sends a hover command.

  The drone will hover in place for the specified number of seconds.
  """
  @spec hover(drone(), keyword()) :: :ok | {:error, term()}
  def hover(drone, opts \\ []) do
    seconds = Keyword.get(opts, :seconds, 1)

    case GenServer.call(Vehicle.whereis(drone), {:command, Command.hover(seconds)}) do
      {:ok, :ok} -> :ok
      {:ok, :dry_run} -> :ok
      {:error, :safety, reason} -> {:error, :safety, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sets the drone speed.

  Speed must be between 10 and 100 cm/s.
  """
  @spec set_speed(drone(), pos_integer()) :: :ok | {:error, term()}
  def set_speed(drone, speed) do
    case GenServer.call(Vehicle.whereis(drone), {:command, Command.speed(speed)}) do
      {:ok, :ok} -> :ok
      {:ok, :dry_run} -> :ok
      {:error, :safety, reason} -> {:error, :safety, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sends a stop command (hover in place).
  """
  @spec stop(drone()) :: :ok | {:error, term()}
  def stop(drone) do
    case GenServer.call(Vehicle.whereis(drone), {:command, Command.stop()}) do
      {:ok, :ok} -> :ok
      {:ok, :dry_run} -> :ok
      {:error, :safety, reason} -> {:error, :safety, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sends a query command to the drone.

  Query type must be one of: `:battery`, `:height`, `:speed`,
  `:time`, `:wifi`, `:sdk_version`, `:serial_number`.

  Returns `{:ok, value}` where value depends on the query type.
  """
  @spec query(drone(), Command.query_type()) :: {:ok, term()} | {:error, term()}
  def query(drone, type) do
    GenServer.call(Vehicle.whereis(drone), {:command, Command.query(type)})
  end

  @doc """
  Retrieves telemetry data from the drone.

  Returns a map with position, battery, and state information.
  """
  @spec telemetry(drone()) :: {:ok, map()} | {:error, term()}
  def telemetry(drone) do
    GenServer.call(Vehicle.whereis(drone), :telemetry)
  end

  @doc """
  Disconnects from the drone and stops the process.
  """
  @spec disconnect(drone()) :: :ok
  def disconnect(drone) do
    GenServer.call(Vehicle.whereis(drone), :disconnect)
  end
end
