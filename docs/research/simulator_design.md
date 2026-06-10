# Simulator Design Research

## Overview

This document covers the design of `Drone.Adapters.Sim`, the simulator adapter for ex_drone. The simulator must be usable without any hardware and must enforce the same safety rules as real adapters.

## Why Simulator-First

1. **Testable without hardware**: All tests run on any machine without a drone
2. **Safe development**: Catch safety violations before connecting to real hardware
3. **Deterministic testing**: The simulator's state is exact, enabling reproducible tests
4. **Mission validation**: Run mission scripts in simulation before flying them
5. **Educational**: Students learn and experiment without risk
6. **Documentation examples**: All examples work in simulation

## Simulator Architecture

The simulator implements the `Drone.Adapter` behaviour, replacing UDP communication with an in-process state machine.

```
Drone.Vehicle (GenServer)
    |
    v
Drone.Adapter behaviour
    |
    v
Drone.Adapters.Sim (in-process state machine)
```

No UDP, no network, no external dependencies. The GenServer calls the adapter module directly.

## Simulator State

```elixir
defstruct [
  x: 0,              # cm from launch point
  y: 0,              # cm from launch point
  z: 0,              # cm altitude
  yaw: 0,            # degrees (0-360)
  flying: false,
  battery: 100,      # percent
  speed: 0,          # current speed in cm/s
  state: :idle,      # :idle | :sdk_mode | :flying | :emergency
  last_command: nil,
  command_history: [],
  config: %{}         # simulator configuration
]
```

### State Transitions

```
:idle --("command")--> :sdk_mode --("takeoff")--> :flying --("land")--> :sdk_mode
  ^                                                  |                        |
  +-------("emergency")<-----------------------------+                        |
  +<-------("emergency")<---------------------+------+-------+
                                             |
                                        :sdk_mode --("emergency")--> :idle
```

- `:idle` -- Drone is powered on but not in SDK mode
- `:sdk_mode` -- In SDK mode, accepting commands, but not flying
- `:flying` -- In the air, accepting movement and query commands
- `:emergency` -- Emergency stop (transitions to `:idle`)

### Position Tracking

The simulator tracks exact position, something real drones cannot do reliably:

- `takeoff`: Sets `z` to 30 (Tello default hover height in cm), `flying` to true
- `up x`: Increases `z` by `x`
- `down x`: Decreases `z` by `x` (minimum 20)
- `forward x`: Calculates new position based on current `yaw`, moves `x` cm in that direction
- `back x`: Moves `x` cm opposite to `yaw`
- `left x`: Moves `x` cm perpendicular to `yaw` (left)
- `right x`: Moves `x` cm perpendicular to `yaw` (right)
- `cw x`: Increases `yaw` by `x` (mod 360)
- `ccw x`: Decreases `yaw` by `x` (mod 360)
- `land`: Sets `z` to 0, `flying` to false

Position calculation for forward/back/left/right:

```elixir
# Forward direction based on yaw (0 = north, increases clockwise)
radians = yaw * :math.pi() / 180

# Forward
new_x = x + distance * :math.sin(radians)
new_y = y + distance * :math.cos(radians)

# Back
new_x = x - distance * :math.sin(radians)
new_y = y - distance * :math.cos(radians)

# Left
new_x = x - distance * :math.cos(radians)
new_y = y + distance * :math.sin(radians)

# Right (opposite of left)
new_x = x + distance * :math.cos(radians)
new_y = y - distance * :math.sin(radians)
```

Wait -- this is a simplified model. The Tello SDK spec defines:

- `forward/back`: movement along the front/back axis (the direction the camera faces)
- `left/right`: strafing left/right
- `up/down`: vertical movement

The coordinate system should be:
- X: right (from drone's initial forward direction)
- Y: forward (from drone's initial forward direction)
- Z: up

After rotation, the axes of movement rotate with the drone. But for the simulator's purpose, we can use a simpler model initially:

- Movement commands are relative to the drone's current heading
- We track absolute position (x, y, z) in a fixed frame
- Yaw rotations change the drone's heading

### Battery Simulation

Battery should drain to enable testing of low-battery scenarios:

- Default drain rate: configurable percentage per command
- Movement commands drain more than queries
- Takeoff and landing drain a fixed amount
- Battery cannot go below 0

```elixir
# Per command battery drain (configurable)
# Default: movement commands cost 0.5%, queries cost nothing
# Takeoff costs 2%, landing costs 1%
```

### Simulated Failures

The simulator should support configurable failure injection:

```elixir
%{
  failure_rate: 0.0,      # 0.0 to 1.0, probability of random failure
  fail_commands: [],       # list of command types that will always fail
  fail_after_n: nil,       # fail after N successful commands
  failure_pattern: nil     # function (command, state) -> :ok | :error
}
```

Failure modes:

- `{:error, :simulated_failure}` -- Random failures based on rate
- `{:error, :command_not_supported}` -- Specific command types configured to fail
- `{:error, :simulated_disconnect}` -- No response (timeout from client's perspective)
- `{:error, :simulated_low_battery}` -- Battery drops below threshold

## Adapter Implementation

```elixir
defmodule Drone.Adapters.Sim do
  @behaviour Drone.Adapter

  @impl Drone.Adapter
  def connect(opts) do
    state = %Drone.Adapters.Sim.State{
      battery: Keyword.get(opts, :battery, 100),
      config: %{
        battery_drain_per_move: Keyword.get(opts, :battery_drain_per_move, 0.5),
        battery_drain_per_takeoff: Keyword.get(opts, :battery_drain_per_takeoff, 2.0),
        battery_drain_per_land: Keyword.get(opts, :battery_drain_per_land, 1.0),
        failure_rate: Keyword.get(opts, :failure_rate, 0.0),
        fail_commands: Keyword.get(opts, :fail_commands, [])
      }
    }
    {:ok, state}
  end

  @impl Drone.Adapter
  def command(state, %Drone.Command{} = cmd) do
    # 1. Check if we should simulate a failure
    # 2. Validate command against state machine
    # 3. Apply command to state
    # 4. Drain battery
    # 5. Return result and new state
  end

  @impl Drone.Adapter
  def telemetry(state) do
    {:ok, %{
      x: state.x,
      y: state.y,
      z: state.z,
      yaw: state.yaw,
      battery: state.battery,
      flying: state.flying,
      speed: state.speed
    }, state}
  end

  @impl Drone.Adapter
  def disconnect(_state) do
    :ok
  end
end
```

## Testing with the Simulator

### Deterministic Mission Tests

```elixir
test "simulator tracks position correctly" do
  {:ok, drone} = Drone.connect(:sim, name: :test_drone)
  Drone.connect_sdk(drone)  # enter SDK mode
  Drone.takeoff(drone)
  Drone.move(drone, :forward, 100)
  Drone.rotate(drone, :cw, 90)
  Drone.move(drone, :forward, 100)

  assert %{x: 100, y: 100, z: 30} = Drone.telemetry(drone)
end
```

### Safety Validation Tests

```elixir
test "simulator respects max altitude" do
  {:ok, drone} = Drone.connect(:sim,
    name: :test_drone,
    safety: [max_altitude_cm: 50]
  )
  Drone.connect_sdk(drone)
  Drone.takeoff(drone)

  assert {:error, :safety, :max_altitude} = Drone.move(drone, :up, 50)
end
```

### Failure Injection Tests

```elixir
test "handles simulated command failure" do
  {:ok, drone} = Drone.connect(:sim,
    name: :test_drone,
    failure_rate: 1.0  # always fail
  )
  Drone.connect_sdk(drone)

  assert {:error, :simulated_failure} = Drone.takeoff(drone)
end
```

## Mission Replay

The simulator should support recording and replaying command sequences:

```elixir
# Record a mission
{:ok, drone} = Drone.connect(:sim, record: true)
Drone.takeoff(drone)
Drone.move(drone, :forward, 100)
Drone.land(drone)
history = Drone.Adapters.Sim.get_history(drone)

# Replay
{:ok, drone2} = Drone.connect(:sim, replay: history)
# Mission executes automatically
```

This is useful for:

- Testing mission scripts deterministically
- Debugging failed missions
- Creating test fixtures
- Educational demonstrations

## Differences Between Sim and Real Adapters

| Aspect              | Sim                    | Tello (Real)              |
|---------------------|------------------------|---------------------------|
| Communication       | In-process            | UDP over Wi-Fi            |
| Timing              | Instant                | Real-time (seconds)       |
| Position            | Exact                  | Estimated                  |
| Battery             | Mathematical model     | Real sensor               |
| Failures            | Configurable           | Unpredictable             |
| State transitions   | Same state machine     | Same state machine        |
| Safety rules        | Same pipeline          | Same pipeline              |

The key insight is: **the same safety pipeline, command pipeline, and state machine run regardless of the adapter**. The adapter only handles communication and response parsing. This means:

- Safety code is tested once, works everywhere
- Missions are tested in sim, fly on real hardware
- State tracking is adapter-independent

## Telemetry Snapshots

The simulator should be able to produce telemetry snapshots at any point:

```elixir
{:ok, telemetry} = Drone.telemetry(drone)
# => %{x: 0, y: 100, z: 30, yaw: 90, battery: 85, flying: true, speed: 50}
```

These snapshots enable:

- Assertions in tests
- Logging and debugging
- Dashboard displays
- Safety validation (checking pre-conditions)

## Summary

The simulator must:

1. Implement `Drone.Adapter` behaviour
2. Track position (x, y, z, yaw)
3. Track state (idle, sdk_mode, flying, emergency)
4. Track battery (with configurable drain)
5. Support state machine transitions matching Tello
6. Support configurable failure injection
7. Support mission recording and replay
8. Produce telemetry snapshots
9. Enforce the same safety rules as real adapters
10. Enable fully deterministic, hardware-free testing