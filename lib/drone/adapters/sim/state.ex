defmodule Drone.Adapters.Sim.State do
  @moduledoc false

  @type t :: %__MODULE__{
          x: integer(),
          y: integer(),
          z: integer(),
          yaw: integer(),
          flying: boolean(),
          battery: integer(),
          speed: integer(),
          mode: :idle | :sdk_mode | :flying | :emergency,
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
      battery: Keyword.get(opts, :battery, 100),
      config: config
    }
  end

  @spec drain_battery(t(), float()) :: t()
  def drain_battery(%__MODULE__{battery: battery} = state, amount) do
    %{state | battery: max(0, battery - amount)}
  end

  @spec push_command(t(), Drone.Command.t()) :: t()
  def push_command(%__MODULE__{command_history: history} = state, cmd) do
    %{state | last_command: cmd, command_history: [cmd | history]}
  end
end
