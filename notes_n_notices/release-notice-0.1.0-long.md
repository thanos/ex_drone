# ex_drone v0.1.0 — Release Notice

**Date:** 2026-06-10
**Version:** 0.1.0
**Elixir:** ~> 1.17 | **OTP:** 26+
**License:** MIT
**Author:** Thanos Vassilakis

---

## Summary

ex_drone is a BEAM-native drone control library for Elixir. It provides a supervised, safety-first API for controlling programmable drones with pluggable adapters, a built-in simulator, and end-to-end telemetry.

This is the first public release. The API is considered **stable but not frozen** — breaking changes will be documented and versioned per semver.

## Safety Notice

**Drones are physical devices that can cause injury or property damage.**

- Always test in the simulator first
- Use prop guards
- Do not fly near faces or people
- Have an emergency stop ready at all times
- Understand and follow local laws and regulations

The safety pipeline validates every command before it reaches the drone. Emergency commands (`Drone.emergency/1`) bypass all safety checks and stop motors immediately.

## Installation

```elixir
def deps do
  [{:ex_drone, "~> 0.1.0"}]
end
```

## Quick Start

```elixir
{:ok, drone} = Drone.connect(:sim, name: :my_drone)
Drone.connect_sdk(drone)
Drone.takeoff(drone)
Drone.move(drone, :forward, 100)
Drone.land(drone)
Drone.disconnect(drone)
```

## What's Included

- Full Tello SDK command set (14 command types)
- In-process simulator with position tracking, battery drain, and failure injection
- Safety pipeline with 8 validation stages
- Geofencing (circle and polygon)
- Mission DSL for scripting command sequences
- `:telemetry` events for observability
- DJI Tello UDP adapter
- CI/CD (lint, test matrix, coverage, sobelow, dialyzer, docs, Hex.pm publish)

## What's Not Included

- Async mission execution
- Video stream handling
- Multi-drone coordination or swarm APIs
- Crazyflie, MAVLink, or other drone adapters
- Retry mechanism for failed commands

## Reporting Issues

File bugs, feature requests, and questions at:
https://github.com/thanos/ex_drone/issues