# Changelog

## v0.1.0 (2026-06-10)

### Added

- `Drone` public API module for connecting, flying, and disconnecting drones
- `Drone.Vehicle` supervised GenServer per drone process
- `Drone.Adapter` behaviour for pluggable drone adapters
- `Drone.Adapters.Sim` simulator adapter (in-process state machine, no hardware needed)
- `Drone.Adapters.Tello` Tello UDP adapter with command encoding and response parsing
- `Drone.Adapters.Tello.Connection` UDP connection handler with centralized defaults
- `Drone.Command` struct with constructors for all Tello SDK commands
- `Drone.Error` error type helpers with `safety/1`, `adapter/1`, `invalid_command/1`
- `Drone.Geometry` shared position math module (`move_delta/3`, `rotate_yaw/3`, `flip_delta/1`)
- `Drone.Safety` pure validation module with altitude, distance, battery, geofence, and allowlist checks
- `Drone.Safety.Policy` struct with default, indoor, and unrestricted presets
- `Drone.Safety.Geofence` circle and polygon geofence support
- `Drone.Telemetry` event helpers emitting `:telemetry` events
- `Drone.Mission` DSL for scripting command sequences
- `Drone.Supervisor` dynamic supervisor for vehicle processes
- `Drone.Application` OTP application starting Registry and Supervisor
- Emergency stop command bypassing all safety checks
- Dry-run mode for validating missions without sending commands
- Command history tracking in simulator and vehicle state
- Flight time simulation in simulator (`query(:time)` returns cumulative motor-on seconds)
- Configurable battery drain simulation
- Configurable failure injection in simulator
- Position tracking (x, y, z, yaw) in simulator and vehicle state
- Command argument validation enforcing Tello SDK ranges (distance 20-500cm, degrees 1-3600, speed 10-100cm/s, hover seconds >0)
- CI/CD pipeline (lint, test matrix, coverage, sobelow, dialyzer, docs, Hex.pm release)

### Changed

- `Drone.Vehicle.child_spec` simplified: `:id` is a constant since DynamicSupervisor ignores it
- `Drone.Adapters.Tello` now references `Connection.default_*()` accessor functions instead of duplicating defaults
- `Drone.Adapters.Sim.query(:time)` returns cumulative flight seconds (not command count), matching real Tello behavior
- `@type drone` narrowed from `atom() | pid()` to `atom()` (pids not supported)
- `Drone.Error.safety/1` used throughout Safety module (was inline tuples)
- Battery stored as `number()` internally in sim, exposed as `trunc(battery)` integer

### Fixed

- Command range validation (F-01): `move/3`, `rotate/3`, `set_speed/2`, `hover/2` reject out-of-range values
- Battery always reported as integer (F-02)
- Graceful `{:error, :not_connected}` for unknown drone names (F-04)
- Tello parser handles negative numbers (F-08)
- `Policy.new(unrestricted: true)` no longer crashes (F-09/F-10)
- `Drone.Vehicle.terminate/2` emits adapter key (`:sim`/`:tello`) not raw module name
- Telemetry metadata bug: terminate/2 was emitting adapter module instead of adapter key