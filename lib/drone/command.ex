defmodule Drone.Command do
  @moduledoc """
  Command struct and helpers for drone operations.

  Every command sent through the ex_drone pipeline is represented as a
  `Drone.Command` struct. This provides a unified representation regardless
  of which adapter handles the command.

  ## Example

      cmd = Drone.Command.move(:forward, 100)
      cmd.type
      #=> :move
      cmd.args
      #=> [direction: :forward, distance: 100]
  """

  @typedoc """
  Horizontal / vertical move direction relative to current yaw.

  Possible values: `:up`, `:down`, `:left`, `:right`, `:forward`, `:back`.

  ## Example

      :forward
  """
  @type direction :: :up | :down | :left | :right | :forward | :back

  @typedoc """
  Yaw rotation direction.

  Possible values: `:cw` (clockwise), `:ccw` (counter-clockwise).

  ## Example

      :cw
  """
  @type rotation :: :cw | :ccw

  @typedoc """
  Flip direction while flying.

  Possible values: `:left`, `:right`, `:forward`, `:back`.

  ## Example

      :left
  """
  @type flip_direction :: :left | :right | :forward | :back

  @typedoc """
  Telemetry / status query kind.

  Possible values: `:battery`, `:height`, `:speed`, `:time`, `:wifi`,
  `:sdk_version`, `:serial_number`.

  ## Example

      :battery
  """
  @type query_type :: :battery | :height | :speed | :time | :wifi | :sdk_version | :serial_number

  @typedoc """
  Discriminator for the command struct's `:type` field.

  Possible values: `:sdk_mode`, `:takeoff`, `:land`, `:emergency`, `:move`,
  `:rotate`, `:flip`, `:hover`, `:speed`, `:stop`, `:query`.

  ## Example

      :takeoff
  """
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

  @typedoc """
  A single drone command.

  ## Fields

  | Field | Type | Required | Meaning |
  |-------|------|----------|---------|
  | `type` | `t:command_type/0` | yes | What to execute |
  | `args` | `keyword()` | no (`[]`) | Type-specific args, e.g. `[direction: :up, distance: 40]` |
  | `raw` | `String.t() \\| nil` | no | Optional wire string (Tello encoding may fill this) |

  ## Examples

      %Drone.Command{type: :takeoff, args: [], raw: nil}

      %Drone.Command{
        type: :move,
        args: [direction: :forward, distance: 100],
        raw: nil
      }

      %Drone.Command{type: :query, args: [type: :battery], raw: nil}
  """
  @type t :: %__MODULE__{
          type: command_type(),
          args: keyword(),
          raw: String.t() | nil
        }

  @enforce_keys [:type]
  defstruct [:type, args: [], raw: nil]

  @doc """
  Creates a new command struct.

  ## Parameters

    * `type` (`t:command_type/0`) — command discriminant
    * `args` (`keyword()`, default `[]`) — type-specific arguments

  ## Returns

  `%Drone.Command{}`

  ## Example

      Drone.Command.new(:hover, seconds: 2)
  """
  @spec new(command_type(), keyword()) :: t()
  def new(type, args \\ []) do
    %__MODULE__{type: type, args: args}
  end

  @doc """
  Creates an SDK mode activation command (`command` on Tello).

  ## Returns

  `%Drone.Command{type: :sdk_mode}`

  ## Example

      Drone.Command.sdk_mode()
  """
  @spec sdk_mode() :: t()
  def sdk_mode, do: new(:sdk_mode)

  @doc """
  Creates a takeoff command.

  ## Returns

  `%Drone.Command{type: :takeoff}`

  ## Example

      Drone.Command.takeoff()
  """
  @spec takeoff() :: t()
  def takeoff, do: new(:takeoff)

  @doc """
  Creates a land command.

  ## Returns

  `%Drone.Command{type: :land}`

  ## Example

      Drone.Command.land()
  """
  @spec land() :: t()
  def land, do: new(:land)

  @doc """
  Creates an emergency motor-stop command.

  ## Returns

  `%Drone.Command{type: :emergency}`

  ## Example

      Drone.Command.emergency()
  """
  @spec emergency() :: t()
  def emergency, do: new(:emergency)

  @doc """
  Creates a movement command.

  ## Parameters

    * `direction` (`t:direction/0`) — `:up` \| `:down` \| `:left` \| `:right` \|
      `:forward` \| `:back`
    * `distance` (`pos_integer()`) — centimeters (validated later as 20..500)

  ## Returns

  `%Drone.Command{type: :move, args: [direction: ..., distance: ...]}`

  ## Example

      Drone.Command.move(:forward, 100)
  """
  @spec move(direction(), pos_integer()) :: t()
  def move(direction, distance) when direction in [:up, :down, :left, :right, :forward, :back] do
    new(:move, direction: direction, distance: distance)
  end

  @doc """
  Creates a rotation command.

  ## Parameters

    * `direction` (`t:rotation/0`) — `:cw` or `:ccw`
    * `degrees` (`pos_integer()`) — 1..3600 (validated in safety)

  ## Returns

  `%Drone.Command{type: :rotate, ...}`

  ## Example

      Drone.Command.rotate(:cw, 90)
  """
  @spec rotate(rotation(), pos_integer()) :: t()
  def rotate(direction, degrees) when direction in [:cw, :ccw] do
    new(:rotate, direction: direction, degrees: degrees)
  end

  @doc """
  Creates a flip command.

  ## Parameters

    * `direction` (`t:flip_direction/0`) — `:left` \| `:right` \| `:forward` \| `:back`

  ## Returns

  `%Drone.Command{type: :flip, ...}`

  ## Example

      Drone.Command.flip(:forward)
  """
  @spec flip(flip_direction()) :: t()
  def flip(direction) when direction in [:left, :right, :forward, :back] do
    new(:flip, direction: direction)
  end

  @doc """
  Creates a hover command.

  ## Parameters

    * `seconds` (`pos_integer()`) — hover duration

  ## Returns

  `%Drone.Command{type: :hover, args: [seconds: seconds]}`

  ## Example

      Drone.Command.hover(3)
  """
  @spec hover(pos_integer()) :: t()
  def hover(seconds) do
    new(:hover, seconds: seconds)
  end

  @doc """
  Creates a speed setting command.

  ## Parameters

    * `speed` (`pos_integer()`) — cm/s (validated as 10..100)

  ## Returns

  `%Drone.Command{type: :speed, args: [speed: speed]}`

  ## Example

      Drone.Command.speed(50)
  """
  @spec speed(pos_integer()) :: t()
  def speed(speed) do
    new(:speed, speed: speed)
  end

  @doc """
  Creates a stop command (hover in place / cancel velocity).

  ## Returns

  `%Drone.Command{type: :stop}`

  ## Example

      Drone.Command.stop()
  """
  @spec stop() :: t()
  def stop, do: new(:stop)

  @doc """
  Creates a query command.

  ## Parameters

    * `type` (`t:query_type/0`) — `:battery`, `:height`, `:speed`, `:time`,
      `:wifi`, `:sdk_version`, or `:serial_number`

  ## Returns

  `%Drone.Command{type: :query, args: [type: type]}`

  ## Example

      Drone.Command.query(:battery)
  """
  @spec query(query_type()) :: t()
  def query(type)
      when type in [:battery, :height, :speed, :time, :wifi, :sdk_version, :serial_number] do
    new(:query, type: type)
  end

  @doc """
  Returns whether the command is an emergency stop.

  ## Parameters

    * `command` (`t:t/0`)

  ## Returns

  `boolean()`

  ## Example

      true = Drone.Command.emergency?(Drone.Command.emergency())
  """
  @spec emergency?(t()) :: boolean()
  def emergency?(%__MODULE__{type: :emergency}), do: true
  def emergency?(_), do: false

  @doc """
  Returns whether the command is a movement-class command (`:move`, `:rotate`, `:flip`).

  ## Parameters

    * `command` (`t:t/0`)

  ## Returns

  `boolean()`

  ## Example

      true = Drone.Command.movement?(Drone.Command.move(:up, 40))
  """
  @spec movement?(t()) :: boolean()
  def movement?(%__MODULE__{type: type}) when type in [:move, :rotate, :flip], do: true
  def movement?(_), do: false

  @doc """
  Returns whether the command is a query.

  ## Parameters

    * `command` (`t:t/0`)

  ## Returns

  `boolean()`

  ## Example

      true = Drone.Command.query?(Drone.Command.query(:height))
  """
  @spec query?(t()) :: boolean()
  def query?(%__MODULE__{type: :query}), do: true
  def query?(_), do: false

  @doc """
  Returns whether the command requires the drone to already be flying.

  ## Parameters

    * `command` (`t:t/0`)

  ## Returns

  `boolean()`

  ## Example

      true = Drone.Command.requires_flying?(Drone.Command.move(:forward, 50))
  """
  @spec requires_flying?(t()) :: boolean()
  def requires_flying?(%__MODULE__{type: type})
      when type in [:move, :rotate, :flip, :hover, :stop],
      do: true

  def requires_flying?(%__MODULE__{type: :land}), do: true
  def requires_flying?(_), do: false

  @doc """
  Returns whether the command is considered safe to auto-retry.

  Only queries and SDK-mode activation are retryable by default. Movement
  commands must never be retried automatically.

  ## Parameters

    * `command` (`t:t/0`)

  ## Returns

  `boolean()`

  ## Example

      true = Drone.Command.safe_to_retry?(Drone.Command.query(:battery))
      false = Drone.Command.safe_to_retry?(Drone.Command.move(:forward, 50))
  """
  @spec safe_to_retry?(t()) :: boolean()
  def safe_to_retry?(%__MODULE__{type: :query}), do: true
  def safe_to_retry?(%__MODULE__{type: :sdk_mode}), do: true
  def safe_to_retry?(_), do: false

  @doc """
  Returns all valid command type atoms.

  ## Returns

  `[t:command_type/0]`

  ## Example

      :takeoff in Drone.Command.types()
  """
  @spec types() :: [command_type()]
  def types do
    [:sdk_mode, :takeoff, :land, :emergency, :move, :rotate, :flip, :hover, :speed, :stop, :query]
  end
end
