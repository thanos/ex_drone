defmodule Drone.Mission do
  @moduledoc """
  Mission DSL for scripting drone command sequences.

  A mission is an ordered list of commands that can be validated and
  replayed against a drone or simulator.

  ## Example

      mission =
        Drone.Mission.new()
        |> Drone.Mission.sdk_mode()
        |> Drone.Mission.takeoff()
        |> Drone.Mission.hover(seconds: 3)
        |> Drone.Mission.move(:up, 40)
        |> Drone.Mission.move(:forward, 100)
        |> Drone.Mission.rotate(:cw, 90)
        |> Drone.Mission.land()

      Drone.Mission.run(mission, drone)
  """

  alias Drone.{Command, Vehicle}

  @type t :: %__MODULE__{
          commands: [Command.t()],
          name: String.t() | nil
        }

  defstruct commands: [], name: nil

  @doc """
  Creates a new empty mission.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{name: Keyword.get(opts, :name)}
  end

  @doc """
  Adds an SDK mode activation command to the mission.
  """
  @spec sdk_mode(t()) :: t()
  def sdk_mode(%__MODULE__{commands: commands} = mission) do
    %{mission | commands: [Command.sdk_mode() | commands]}
  end

  @doc """
  Adds a takeoff command to the mission.
  """
  @spec takeoff(t()) :: t()
  def takeoff(%__MODULE__{commands: commands} = mission) do
    %{mission | commands: [Command.takeoff() | commands]}
  end

  @doc """
  Adds a land command to the mission.
  """
  @spec land(t()) :: t()
  def land(%__MODULE__{commands: commands} = mission) do
    %{mission | commands: [Command.land() | commands]}
  end

  @doc """
  Adds an emergency stop command to the mission.
  """
  @spec emergency(t()) :: t()
  def emergency(%__MODULE__{commands: commands} = mission) do
    %{mission | commands: [Command.emergency() | commands]}
  end

  @doc """
  Adds a movement command to the mission.
  """
  @spec move(t(), Command.direction(), pos_integer()) :: t()
  def move(%__MODULE__{commands: commands} = mission, direction, distance) do
    %{mission | commands: [Command.move(direction, distance) | commands]}
  end

  @doc """
  Adds a rotation command to the mission.
  """
  @spec rotate(t(), Command.rotation(), pos_integer()) :: t()
  def rotate(%__MODULE__{commands: commands} = mission, direction, degrees) do
    %{mission | commands: [Command.rotate(direction, degrees) | commands]}
  end

  @doc """
  Adds a flip command to the mission.
  """
  @spec flip(t(), Command.flip_direction()) :: t()
  def flip(%__MODULE__{commands: commands} = mission, direction) do
    %{mission | commands: [Command.flip(direction) | commands]}
  end

  @doc """
  Adds a hover command to the mission.
  """
  @spec hover(t(), keyword()) :: t()
  def hover(%__MODULE__{commands: commands} = mission, opts \\ []) do
    seconds = Keyword.get(opts, :seconds, 1)
    %{mission | commands: [Command.hover(seconds) | commands]}
  end

  @doc """
  Adds a speed setting command to the mission.
  """
  @spec speed(t(), pos_integer()) :: t()
  def speed(%__MODULE__{commands: commands} = mission, speed) do
    %{mission | commands: [Command.speed(speed) | commands]}
  end

  @doc """
  Adds a stop command to the mission.
  """
  @spec stop(t()) :: t()
  def stop(%__MODULE__{commands: commands} = mission) do
    %{mission | commands: [Command.stop() | commands]}
  end

  @doc """
  Adds a query command to the mission.
  """
  @spec query(t(), Command.query_type()) :: t()
  def query(%__MODULE__{commands: commands} = mission, type) do
    %{mission | commands: [Command.query(type) | commands]}
  end

  @doc """
  Returns the list of commands in the mission in execution order.
  """
  @spec commands(t()) :: [Command.t()]
  def commands(%__MODULE__{commands: commands}), do: Enum.reverse(commands)

  @doc """
  Returns the number of commands in the mission.
  """
  @spec length(t()) :: non_neg_integer()
  def length(%__MODULE__{commands: commands}), do: Kernel.length(commands)

  @doc """
  Runs a mission against a drone process.

  Each command is sent sequentially. If any command fails, the mission
  stops and returns the error.

  Returns `{:ok, results}` with a list of results for each command,
  or `{:error, command, reason}` with the failing command and error.
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
