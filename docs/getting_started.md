# Getting Started

## Prerequisites

- Elixir 1.18 or later
- Erlang/OTP 25 or later
- A DJI Tello or Tello EDU (optional -- the simulator works without hardware)

## Installation

Add `ex_drone` to your dependencies:

```elixir
def deps do
  [
    {:ex_drone, "~> 0.1.0"}
  ]
end
```

Then run:

```shell
mix deps.get
```

## Your First Flight (Simulator)

The simulator requires no hardware and is the best way to learn ex_drone:

```elixir
{:ok, drone} = Drone.connect(:sim, name: :my_drone)
Drone.connect_sdk(drone)
Drone.takeoff(drone)
Drone.move(drone, :up, 40)
Drone.move(drone, :forward, 100)
Drone.rotate(drone, :cw, 90)
Drone.land(drone)
Drone.disconnect(drone)
```

## Querying State

```elixir
{:ok, drone} = Drone.connect(:sim, name: :test)
Drone.connect_sdk(drone)

{:ok, battery} = Drone.query(drone, :battery)
{:ok, telemetry} = Drone.telemetry(drone)
```

## Safety Policies

Configure safety limits at connection time:

```elixir
# Indoor mode (tight limits)
{:ok, drone} = Drone.connect(:sim, name: :indoor, safety: [indoor: true])

# Custom limits
{:ok, drone} = Drone.connect(:sim, name: :custom,
  safety: [
    max_altitude_cm: 200,
    max_distance_cm: 500,
    min_battery_percent: 20,
    prop_guards: true
  ]
)

# Dry-run mode (validate without flying)
{:ok, drone} = Drone.connect(:sim, name: :dry, safety: [dry_run: true])
```

## Emergency Stop

```elixir
Drone.emergency(drone)  # Bypasses all safety checks, stops motors immediately
```

## Connecting to a Tello

1. Power on your Tello drone
2. Connect to the Tello's Wi-Fi network (SSID: `TELLO-XXXXXX`)
3. Connect with ex_drone:

```elixir
{:ok, drone} = Drone.connect(:tello, name: :tello_1)
Drone.connect_sdk(drone)
Drone.takeoff(drone)
```

Always test your missions in the simulator first.