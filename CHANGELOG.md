# Changelog

## v0.1.0 (2026-06-09)

### Added

- `Drone` public API module for connecting, flying, and disconnecting drones
- `Drone.Vehicle` supervised GenServer per drone process
- `Drone.Adapter` behaviour for pluggable drone adapters
- `Drone.Adapters.Sim` simulator adapter (in-process state machine, no hardware needed)
- `Drone.Adapters.Tello` Tello UDP adapter with command encoding and response parsing
- `Drone.Command` struct with constructors for all Tello SDK commands
- `Drone.Safety` pure validation module with altitude, distance, battery, geofence, and allowlist checks
- `Drone.Safety.Policy` struct with default, indoor, and unrestricted presets
- `Drone.Safety.Geofence` circle and polygon geofence support
- `Drone.Telemetry` event helpers emitting `:telemetry` events
- `Drone.Mission` DSL for scripting command sequences
- `Drone.Error` error type helpers
- `Drone.Supervisor` dynamic supervisor for vehicle processes
- `Drone.Application` OTP application starting Registry and Supervisor
- Emergency stop command bypassing all safety checks
- Dry-run mode for validating missions without sending commands
- Command history tracking in simulator
- Configurable battery drain simulation
- Configurable failure injection in simulator
- Position tracking (x, y, z, yaw) in simulator and vehicle state
- 148 passing tests