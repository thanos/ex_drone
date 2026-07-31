defmodule Drone.Adapters.Sim.State do
  @moduledoc """
  In-process simulator state for `Drone.Adapters.Sim`.

  Tracks pose, battery, mode, and command history without network I/O.
  Created via `new/1` from `Drone.Adapters.Sim.connect/1`.
  """

  @typedoc """
  Simulator adapter state.

  ## Fields

  | Field | Type | Default | Meaning |
  |-------|------|---------|---------|
  | `x` | `integer()` | `0` or `:initial_x` | World X cm |
  | `y` | `integer()` | `0` or `:initial_y` | World Y cm (yaw 0 faces +Y) |
  | `z` | `integer()` | `0` or `:initial_z` | Altitude cm |
  | `yaw` | `integer()` | `0` or `:initial_yaw` | Heading degrees |
  | `flying` | `boolean()` | `false` | Motors / airborne |
  | `battery` | `number()` | `100` | Percent (may be fractional internally) |
  | `speed` | `integer()` | `0` | cm/s |
  | `mode` | `:idle \\| :sdk_mode \\| :flying \\| :emergency` | `:idle` | State machine mode |
  | `flight_time_seconds` | `non_neg_integer()` | `0` | Cumulative motor-on time |
  | `last_command` | `Drone.Command.t() \\| nil` | `nil` | Most recent command |
  | `command_history` | `[Drone.Command.t()]` | `[]` | Newest-first history |
  | `config` | `map()` | drain / failure opts | Simulator configuration |

  ## Example

      %Drone.Adapters.Sim.State{
        x: -50,
        y: 0,
        z: 30,
        yaw: 0,
        flying: true,
        battery: 97.5,
        speed: 0,
        mode: :flying,
        flight_time_seconds: 8,
        last_command: %Drone.Command{type: :takeoff, args: [], raw: nil},
        command_history: [],
        config: %{failure_rate: 0.0, fail_commands: []}
      }
  """
  @type t :: %__MODULE__{
          x: integer(),
          y: integer(),
          z: integer(),
          yaw: integer(),
          flying: boolean(),
          battery: number(),
          speed: integer(),
          mode: :idle | :sdk_mode | :flying | :emergency,
          flight_time_seconds: non_neg_integer(),
          last_command: Drone.Command.t() | nil,
          command_history: [Drone.Command.t()],
          config: map()
        }

  defstruct x: 0,
            y: 0,
            z: 0,
            yaw: 0,
            flying: false,
            battery: 100,
            speed: 0,
            mode: :idle,
            flight_time_seconds: 0,
            last_command: nil,
            command_history: [],
            config: %{
              battery_drain_per_move: 0.5,
              battery_drain_per_takeoff: 2.0,
              battery_drain_per_land: 1.0,
              battery_drain_per_query: 0.0,
              failure_rate: 0.0,
              fail_commands: []
            }

  @doc """
  Builds a new simulator state from connection options.

  ## Parameters

    * `opts` (`keyword()`) — supported keys:
      * `:initial_x`, `:initial_y`, `:initial_z`, `:initial_yaw` (`integer()`)
      * `:battery` (`number()`)
      * `:battery_drain_per_move`, `:battery_drain_per_takeoff`,
        `:battery_drain_per_land`, `:battery_drain_per_query` (`float()`)
      * `:failure_rate` (`float()` 0.0..1.0)
      * `:fail_commands` (`[atom()]`) — always fail these command types

  ## Returns

  `t:t/0`

  ## Example

      state = Drone.Adapters.Sim.State.new(initial_x: -50, battery: 80)
      state.x
      #=> -50
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    config = %{
      battery_drain_per_move: Keyword.get(opts, :battery_drain_per_move, 0.5),
      battery_drain_per_takeoff: Keyword.get(opts, :battery_drain_per_takeoff, 2.0),
      battery_drain_per_land: Keyword.get(opts, :battery_drain_per_land, 1.0),
      battery_drain_per_query: Keyword.get(opts, :battery_drain_per_query, 0.0),
      failure_rate: Keyword.get(opts, :failure_rate, 0.0),
      fail_commands: Keyword.get(opts, :fail_commands, [])
    }

    %__MODULE__{
      x: Keyword.get(opts, :initial_x, 0),
      y: Keyword.get(opts, :initial_y, 0),
      z: Keyword.get(opts, :initial_z, 0),
      yaw: Keyword.get(opts, :initial_yaw, 0),
      battery: Keyword.get(opts, :battery, 100),
      config: config
    }
  end

  @doc """
  Decreases battery by `amount`, floored at 0.

  ## Parameters

    * `state` (`t:t/0`)
    * `amount` (`float()`)

  ## Returns

  Updated `t:t/0`.
  """
  @spec drain_battery(t(), float()) :: t()
  def drain_battery(%__MODULE__{battery: battery} = state, amount) do
    %{state | battery: max(0, battery - amount)}
  end

  @doc """
  Records `cmd` as the last command and prepends it to history.

  ## Parameters

    * `state` (`t:t/0`)
    * `cmd` (`Drone.Command.t()`)

  ## Returns

  Updated `t:t/0`.
  """
  @spec push_command(t(), Drone.Command.t()) :: t()
  def push_command(%__MODULE__{command_history: history} = state, cmd) do
    %{state | last_command: cmd, command_history: [cmd | history]}
  end

  @doc """
  Increments the flight time by the given number of seconds.

  Used to simulate time elapsed during command execution.

  ## Parameters

    * `state` (`t:t/0`)
    * `seconds` (`non_neg_integer()`)

  ## Returns

  Updated `t:t/0`.
  """
  @spec add_flight_time(t(), non_neg_integer()) :: t()
  def add_flight_time(%__MODULE__{flight_time_seconds: t} = state, seconds) do
    %{state | flight_time_seconds: t + seconds}
  end
end
