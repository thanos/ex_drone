defmodule Drone.Command do
  @moduledoc """
  Command struct and helpers for drone operations.

  Every command sent through the ex_drone pipeline is represented as a
  `Drone.Command` struct. This provides a unified representation regardless
  of which adapter handles the command.
  """

  @type direction :: :up | :down | :left | :right | :forward | :back
  @type rotation :: :cw | :ccw
  @type flip_direction :: :left | :right | :forward | :back
  @type query_type :: :battery | :height | :speed | :time | :wifi | :sdk_version | :serial_number
  @type command_type ::
          :sdk_mode
          | :takeoff
          | :land
          | :emergency
          | :move
          | :rotate
          | :flip
          | :hover
          | :speed
          | :stop
          | :query

  @type t :: %__MODULE__{
          type: command_type(),
          args: keyword(),
          raw: String.t() | nil
        }

  @enforce_keys [:type]
  defstruct [:type, :args, :raw]

  @doc """
  Creates a new command struct.
  """
  @spec new(command_type(), keyword()) :: t()
  def new(type, args \\ []) do
    %__MODULE__{type: type, args: args}
  end

  @doc """
  Creates an SDK mode activation command.
  """
  @spec sdk_mode() :: t()
  def sdk_mode, do: new(:sdk_mode)

  @doc """
  Creates a takeoff command.
  """
  @spec takeoff() :: t()
  def takeoff, do: new(:takeoff)

  @doc """
  Creates a land command.
  """
  @spec land() :: t()
  def land, do: new(:land)

  @doc """
  Creates an emergency stop command.
  """
  @spec emergency() :: t()
  def emergency, do: new(:emergency)

  @doc """
  Creates a movement command.

  Direction must be one of: `:up`, `:down`, `:left`, `:right`, `:forward`, `:back`.
  Distance must be between 20 and 500 cm.
  """
  @spec move(direction(), pos_integer()) :: t()
  def move(direction, distance) when direction in [:up, :down, :left, :right, :forward, :back] do
    new(:move, direction: direction, distance: distance)
  end

  @doc """
  Creates a rotation command.

  Direction must be `:cw` (clockwise) or `:ccw` (counter-clockwise).
  Degrees must be between 1 and 3600.
  """
  @spec rotate(rotation(), pos_integer()) :: t()
  def rotate(direction, degrees) when direction in [:cw, :ccw] do
    new(:rotate, direction: direction, degrees: degrees)
  end

  @doc """
  Creates a flip command.

  Direction must be one of: `:left`, `:right`, `:forward`, `:back`.
  """
  @spec flip(flip_direction()) :: t()
  def flip(direction) when direction in [:left, :right, :forward, :back] do
    new(:flip, direction: direction)
  end

  @doc """
  Creates a hover command.

  Seconds must be a positive integer.
  """
  @spec hover(pos_integer()) :: t()
  def hover(seconds) do
    new(:hover, seconds: seconds)
  end

  @doc """
  Creates a speed setting command.

  Speed must be between 10 and 100 cm/s.
  """
  @spec speed(pos_integer()) :: t()
  def speed(speed) do
    new(:speed, speed: speed)
  end

  @doc """
  Creates a stop command (hover in place).
  """
  @spec stop() :: t()
  def stop, do: new(:stop)

  @doc """
  Creates a query command.

  Query type must be one of: `:battery`, `:height`, `:speed`, `:time`,
  `:wifi`, `:sdk_version`, `:serial_number`.
  """
  @spec query(query_type()) :: t()
  def query(type)
      when type in [:battery, :height, :speed, :time, :wifi, :sdk_version, :serial_number] do
    new(:query, type: type)
  end

  @doc """
  Checks if a command is an emergency command.
  """
  @spec emergency?(t()) :: boolean()
  def emergency?(%__MODULE__{type: :emergency}), do: true
  def emergency?(_), do: false

  @doc """
  Checks if a command is a movement command.
  """
  @spec movement?(t()) :: boolean()
  def movement?(%__MODULE__{type: type}) when type in [:move, :rotate, :flip], do: true
  def movement?(_), do: false

  @doc """
  Checks if a command is a query command.
  """
  @spec query?(t()) :: boolean()
  def query?(%__MODULE__{type: :query}), do: true
  def query?(_), do: false

  @doc """
  Checks if a command requires the drone to be flying.
  """
  @spec requires_flying?(t()) :: boolean()
  def requires_flying?(%__MODULE__{type: type})
      when type in [:move, :rotate, :flip, :hover, :stop],
      do: true

  def requires_flying?(%__MODULE__{type: :land}), do: true
  def requires_flying?(_), do: false

  @doc """
  Checks if a command is a safe (retryable) command.
  """
  @spec safe_to_retry?(t()) :: boolean()
  def safe_to_retry?(%__MODULE__{type: :query}), do: true
  def safe_to_retry?(%__MODULE__{type: :sdk_mode}), do: true
  def safe_to_retry?(_), do: false

  @doc """
  Returns all valid command types.
  """
  @spec types() :: [command_type()]
  def types do
    [:sdk_mode, :takeoff, :land, :emergency, :move, :rotate, :flip, :hover, :speed, :stop, :query]
  end
end
