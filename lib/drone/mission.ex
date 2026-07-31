defmodule Drone.Mission do
  @moduledoc """
  Mission DSL for scripting drone command sequences.

  A mission is an ordered list of `Drone.Command` values that can be built
  with a pipe-friendly API and executed sequentially against a named drone.

  Commands are stored newest-first internally and reversed for execution /
  inspection via `commands/1` and `run/2`.

  ## Example

      mission =
        Drone.Mission.new(name: "square")
        |> Drone.Mission.sdk_mode()
        |> Drone.Mission.takeoff()
        |> Drone.Mission.hover(seconds: 3)
        |> Drone.Mission.move(:up, 40)
        |> Drone.Mission.move(:forward, 100)
        |> Drone.Mission.rotate(:cw, 90)
        |> Drone.Mission.land()

      {:ok, results} = Drone.Mission.run(mission, :my_drone)
  """

  alias Drone.{Command, Vehicle}

  @typedoc """
  A scripted sequence of drone commands.

  ## Fields

  | Field | Type | Default | Meaning |
  |-------|------|---------|---------|
  | `commands` | `[Drone.Command.t()]` | `[]` | Commands in reverse insertion order |
  | `name` | `String.t() \\| nil` | `nil` | Optional label for logging / demos |

  ## Example

      %Drone.Mission{
        name: "hover-demo",
        commands: [
          %Drone.Command{type: :land, args: [], raw: nil},
          %Drone.Command{type: :takeoff, args: [], raw: nil}
        ]
      }
  """
  @type t :: %__MODULE__{
          commands: [Command.t()],
          name: String.t() | nil
        }

  defstruct commands: [], name: nil

  @doc """
  Creates a new empty mission.

  ## Parameters

    * `opts` (`keyword()`) — options:
      * `:name` (`String.t()`) — optional mission label

  ## Returns

  `%Drone.Mission{}`

  ## Examples

      Drone.Mission.new()
      Drone.Mission.new(name: "patrol-loop")
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{name: Keyword.get(opts, :name)}
  end

  @doc """
  Adds an SDK mode activation command.

  ## Parameters

    * `mission` (`t:t/0`) — mission to extend

  ## Returns

  Updated `t:t/0`.

  ## Example

      Drone.Mission.new() |> Drone.Mission.sdk_mode()
  """
  @spec sdk_mode(t()) :: t()
  def sdk_mode(%__MODULE__{commands: commands} = mission) do
    %{mission | commands: [Command.sdk_mode() | commands]}
  end

  @doc """
  Adds a takeoff command.

  ## Parameters

    * `mission` (`t:t/0`)

  ## Returns

  Updated `t:t/0`.

  ## Example

      mission |> Drone.Mission.takeoff()
  """
  @spec takeoff(t()) :: t()
  def takeoff(%__MODULE__{commands: commands} = mission) do
    %{mission | commands: [Command.takeoff() | commands]}
  end

  @doc """
  Adds a land command.

  ## Parameters

    * `mission` (`t:t/0`)

  ## Returns

  Updated `t:t/0`.

  ## Example

      mission |> Drone.Mission.land()
  """
  @spec land(t()) :: t()
  def land(%__MODULE__{commands: commands} = mission) do
    %{mission | commands: [Command.land() | commands]}
  end

  @doc """
  Adds an emergency stop command.

  ## Parameters

    * `mission` (`t:t/0`)

  ## Returns

  Updated `t:t/0`.

  ## Example

      mission |> Drone.Mission.emergency()
  """
  @spec emergency(t()) :: t()
  def emergency(%__MODULE__{commands: commands} = mission) do
    %{mission | commands: [Command.emergency() | commands]}
  end

  @doc """
  Adds a movement command.

  ## Parameters

    * `mission` (`t:t/0`)
    * `direction` (`Drone.Command.direction()`) — `:up` \| `:down` \| `:left` \|
      `:right` \| `:forward` \| `:back`
    * `distance` (`pos_integer()`) — centimeters (SDK range 20..500)

  ## Returns

  Updated `t:t/0`.

  ## Example

      mission |> Drone.Mission.move(:forward, 100)
  """
  @spec move(t(), Command.direction(), pos_integer()) :: t()
  def move(%__MODULE__{commands: commands} = mission, direction, distance) do
    %{mission | commands: [Command.move(direction, distance) | commands]}
  end

  @doc """
  Adds a rotation command.

  ## Parameters

    * `mission` (`t:t/0`)
    * `direction` (`Drone.Command.rotation()`) — `:cw` or `:ccw`
    * `degrees` (`pos_integer()`) — 1..3600

  ## Returns

  Updated `t:t/0`.

  ## Example

      mission |> Drone.Mission.rotate(:cw, 90)
  """
  @spec rotate(t(), Command.rotation(), pos_integer()) :: t()
  def rotate(%__MODULE__{commands: commands} = mission, direction, degrees) do
    %{mission | commands: [Command.rotate(direction, degrees) | commands]}
  end

  @doc """
  Adds a flip command.

  ## Parameters

    * `mission` (`t:t/0`)
    * `direction` (`Drone.Command.flip_direction()`) — `:left` \| `:right` \|
      `:forward` \| `:back`

  ## Returns

  Updated `t:t/0`.

  ## Example

      mission |> Drone.Mission.flip(:left)
  """
  @spec flip(t(), Command.flip_direction()) :: t()
  def flip(%__MODULE__{commands: commands} = mission, direction) do
    %{mission | commands: [Command.flip(direction) | commands]}
  end

  @doc """
  Adds a hover command.

  ## Parameters

    * `mission` (`t:t/0`)
    * `opts` (`keyword()`) — `:seconds` (`pos_integer()`, default `1`)

  ## Returns

  Updated `t:t/0`.

  ## Example

      mission |> Drone.Mission.hover(seconds: 3)
  """
  @spec hover(t(), keyword()) :: t()
  def hover(%__MODULE__{commands: commands} = mission, opts \\ []) do
    seconds = Keyword.get(opts, :seconds, 1)
    %{mission | commands: [Command.hover(seconds) | commands]}
  end

  @doc """
  Adds a speed-setting command.

  ## Parameters

    * `mission` (`t:t/0`)
    * `speed` (`pos_integer()`) — cm/s (SDK range 10..100)

  ## Returns

  Updated `t:t/0`.

  ## Example

      mission |> Drone.Mission.speed(50)
  """
  @spec speed(t(), pos_integer()) :: t()
  def speed(%__MODULE__{commands: commands} = mission, speed) do
    %{mission | commands: [Command.speed(speed) | commands]}
  end

  @doc """
  Adds a stop (hover in place) command.

  ## Parameters

    * `mission` (`t:t/0`)

  ## Returns

  Updated `t:t/0`.

  ## Example

      mission |> Drone.Mission.stop()
  """
  @spec stop(t()) :: t()
  def stop(%__MODULE__{commands: commands} = mission) do
    %{mission | commands: [Command.stop() | commands]}
  end

  @doc """
  Adds a query command.

  ## Parameters

    * `mission` (`t:t/0`)
    * `type` (`Drone.Command.query_type()`) — `:battery`, `:height`, `:speed`,
      `:time`, `:wifi`, `:sdk_version`, or `:serial_number`

  ## Returns

  Updated `t:t/0`.

  ## Example

      mission |> Drone.Mission.query(:battery)
  """
  @spec query(t(), Command.query_type()) :: t()
  def query(%__MODULE__{commands: commands} = mission, type) do
    %{mission | commands: [Command.query(type) | commands]}
  end

  @doc """
  Returns commands in execution order (oldest first).

  ## Parameters

    * `mission` (`t:t/0`)

  ## Returns

  `[Drone.Command.t()]`

  ## Example

      [sdk, takeoff | _] = Drone.Mission.commands(mission)
  """
  @spec commands(t()) :: [Command.t()]
  def commands(%__MODULE__{commands: commands}), do: Enum.reverse(commands)

  @doc """
  Returns the number of commands in the mission.

  ## Parameters

    * `mission` (`t:t/0`)

  ## Returns

  `non_neg_integer()`

  ## Example

      4 = Drone.Mission.length(mission)
  """
  @spec length(t()) :: non_neg_integer()
  def length(%__MODULE__{commands: commands}), do: Kernel.length(commands)

  @doc """
  Runs a mission against a named drone process.

  Each command is sent sequentially. On the first failure the mission stops.

  ## Parameters

    * `mission` (`t:t/0`) — mission to execute
    * `drone_name` (`atom()`) — registered vehicle name (e.g. `:my_drone`)

  ## Returns

    * `{:ok, [term()]}` — per-command replies in execution order
    * `{:error, Drone.Command.t(), term()}` — failing command and reason
      (reason may be `{:safety, atom()}`, `:not_in_sdk_mode`, etc.)
    * `{:error, command, {:no_process, atom()}}` — drone not registered

  ## Example

      {:ok, drone} = Drone.connect(:sim, name: :demo)
      Drone.connect_sdk(drone)

      mission =
        Drone.Mission.new()
        |> Drone.Mission.takeoff()
        |> Drone.Mission.move(:up, 20)
        |> Drone.Mission.land()

      {:ok, [_takeoff, _move, _land]} = Drone.Mission.run(mission, :demo)
  """
  @spec run(t(), atom()) :: {:ok, [term()]} | {:error, Command.t(), term()}
  def run(%__MODULE__{commands: commands}, drone_name) do
    pid = Vehicle.whereis(drone_name)

    if pid do
      run_commands(Enum.reverse(commands), pid, [])
    else
      {:error, Command.sdk_mode(), {:no_process, drone_name}}
    end
  end

  defp run_commands([], _pid, results), do: {:ok, Enum.reverse(results)}

  defp run_commands([cmd | rest], pid, results) do
    case GenServer.call(pid, {:command, cmd}) do
      {:ok, reply} ->
        run_commands(rest, pid, [reply | results])

      {:error, :safety, reason} ->
        {:error, cmd, {:safety, reason}}

      {:error, reason} ->
        {:error, cmd, reason}
    end
  end
end
