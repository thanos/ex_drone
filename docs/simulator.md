# Simulator

The `Drone.Adapters.Sim` adapter provides a complete in-process simulator for development, testing, and education. No hardware or network connection needed.

## Using the Simulator

```elixir
{:ok, drone} = Drone.connect(:sim, name: :test)
Drone.connect_sdk(drone)
Drone.takeoff(drone)
Drone.move(drone, :forward, 100)
Drone.land(drone)
Drone.disconnect(drone)
```

## How It Works

The simulator implements the `Drone.Adapter` behaviour with an in-process state machine. It tracks position (x, y, z), yaw, battery, and mode. Since it runs in-process, commands execute instantly.

## State Machine

```
:idle --("command")--> :sdk_mode --("takeoff")--> :flying
  ^                    |                              |  |
  |                    |                              |  |
  +--------------------+--("land"/"emergency")---------+
```

## Battery Simulation

Battery drains at configurable rates:

- Movement commands: 0.5% per command (default)
- Takeoff: 2% (default)
- Landing: 1% (default)
- Queries: 0% (default)

Start with a specific battery level:

```elixir
{:ok, drone} = Drone.connect(:sim, name: :low_bat, battery: 30)
```

Battery is always reported as an integer (truncated from fractional drain):
```elixir
{:ok, battery} = Drone.query(drone, :battery)
# battery is an integer, e.g., 98
```

## Flight Time Simulation

The simulator tracks cumulative motor-on time in seconds, matching real Tello behavior:

- Takeoff adds 3 seconds
- Landing adds 3 seconds
- Movement (move/rotate) adds 2 seconds
- Flips add 2 seconds
- Hover adds the specified seconds

```elixir
{:ok, drone} = Drone.connect(:sim, name: :test)
Drone.connect_sdk(drone)
Drone.takeoff(drone)
{:ok, time} = Drone.query(drone, :time)
# time == 3 (seconds of flight time)
```

## Failure Injection

Test error handling by injecting failures:

```elixir
# Always fail
{:ok, drone} = Drone.connect(:sim, name: :fail, failure_rate: 1.0)

# Fail specific commands
{:ok, drone} = Drone.connect(:sim, name: :partial, fail_commands: [:takeoff])
```

## Position Tracking

The simulator tracks exact position using coordinate math:

- `forward/back` movement respects current yaw angle
- `left/right` strafing is perpendicular to heading
- `up/down` changes altitude

```elixir
{:ok, drone} = Drone.connect(:sim, name: :pos)
Drone.connect_sdk(drone)
Drone.takeoff(drone)
Drone.move(drone, :forward, 100)
Drone.rotate(drone, :cw, 90)
Drone.move(drone, :forward, 100)

{:ok, telemetry} = Drone.telemetry(drone)
# telemetry.x and telemetry.y reflect the position
```

## Same Safety Rules

The simulator enforces the same safety rules as real adapters. This means:

- Safety validation runs before every command
- Altitude limits, distance limits, and battery checks all apply
- Emergency commands bypass safety

```elixir
{:ok, drone} = Drone.connect(:sim, name: :safe, safety: [max_altitude_cm: 50])
Drone.connect_sdk(drone)
Drone.takeoff(drone)

{:error, :safety, :max_altitude} = Drone.move(drone, :up, 100)
```