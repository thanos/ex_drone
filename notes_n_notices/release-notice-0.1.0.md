# ex_drone v0.1.0 — BEAM-native drone control for Elixir

A safety-first library for controlling programmable drones with supervised processes, telemetry, and a built-in simulator. No hardware needed to get started.

## Why?

Drones are dangerous when software fails. ex_drone puts a validation pipeline in front of every command — altitude limits, geofencing, battery checks, mode enforcement, and an emergency stop that bypasses everything. Fly a real Tello or the simulator with the same API.

## What's in the box

- **Simulator adapter** — test everything without a drone
- **Tello adapter** — DJI Tello / Tello EDU over UDP
- **Safety pipeline** — 8-stage validation before every command
- **Geofencing** — circle and polygon boundaries
- **Mission DSL** — script command sequences
- **Dry-run mode** — validate without flying
- **Telemetry events** — `:telemetry` for observability

```elixir
{:ok, drone} = Drone.connect(:sim, name: :my_drone)
Drone.connect_sdk(drone)
Drone.takeoff(drone)
Drone.move(drone, :forward, 100)
Drone.land(drone)
```

## Links

- **Hex**: https://hex.pm/packages/ex_drone
- **GitHub**: https://github.com/thanos/ex_drone
- **Docs**: https://hexdocs.pm/ex_drone

253 tests, 90% coverage. Elixir ~> 1.17, OTP 26+. MIT license.