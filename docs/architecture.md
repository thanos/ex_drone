# Architecture

ex_drone is a BEAM-native drone control library built on OTP principles.

## Module Overview

```
Drone (Public API)
  |
  +-- Drone.Swarm (GenServer coordinator)
  |     |
  |     +-- Drone.Formation (pure planners)
  |     +-- Drone.Mission (per-drone scripts)
  |     +-- Drone public API (fan-out to members)
  |
  +-- Drone.Vehicle (GenServer, one per drone)
  |     |
  |     +-- Drone.Safety (pure validation)
  |     +-- Drone.Telemetry (event helpers)
  |     +-- Drone.Geometry (position math)
  |     +-- Drone.Adapter (behaviour)
  |           |
  |           +-- Drone.Adapters.Sim (in-process state machine)
  |           +-- Drone.Adapters.Tello (UDP connection)
  |           +-- Drone.Adapters.Crazyflie (CRTP / Crazyradio or mock)
  |
  +-- Drone.Command (struct and encoding)
  +-- Drone.Error (error types)
  +-- Drone.Mission (sequence DSL)
  +-- Drone.Safety.Policy (policy configuration)
  +-- Drone.Safety.Geofence (area restrictions)
```

## Supervision Tree

```
Drone.Supervisor.Root (Supervisor)
  |
  +-- Drone.Vehicle.Registry (Registry)
  +-- Drone.Swarm.Registry (Registry)
  +-- Drone.Supervisor (DynamicSupervisor)
  |     |
  |     +-- Drone.Vehicle :good
  |     +-- Drone.Vehicle :bad
  |     +-- ...
  +-- Drone.Swarm.Supervisor (DynamicSupervisor)
        |
        +-- Drone.Swarm :advisors
```

Each `Drone.Vehicle` is a supervised GenServer that:

- Owns the adapter state for one drone
- Runs every command through the safety pipeline
- Emits telemetry events
- Updates vehicle state from adapter responses
- Can be started and stopped dynamically

## Command Pipeline

```
User -> Drone.takeoff(drone)
       |
       v
Drone.Vehicle.handle_call({:command, cmd})
       |
       v
Emergency? -> Bypass all, send immediately to adapter
       |
       v
Drone.Safety.check(cmd, policy, state)
       |
       +-- Validate Args -> Reject if out of Tello SDK range
       +-- Check Mode -> Reject if not in valid state
       +-- Check Allowlist -> Reject if not allowed
       +-- Check Flying Requirement -> Reject if state does not match
       +-- Check Altitude -> Reject if exceeds max
       +-- Check Distance -> Reject if exceeds max
       +-- Check Battery -> Reject takeoff if too low
       +-- Check Geofence -> Reject if outside area
       |
       +-- {:error, :safety, reason} -> emit [:drone, :safety, :reject] -> return error
       |
       +-- {:ok, cmd} or {:ok, cmd, warnings}
              |
              v
       (dry_run?) -> return {:ok, :dry_run}
              |
              v
       emit [:drone, :command, :start]
              |
              v
       Adapter.command(state, cmd)
              |
              +-- {:ok, reply, new_state} -> update state -> emit [:drone, :command, :stop]
              +-- {:error, reason, new_state} -> emit [:drone, :command, :error]
```

Emergency commands bypass the entire safety pipeline.

## Adapter Behaviour

All adapters implement `Drone.Adapter`:

```elixir
@callback connect(opts :: keyword()) :: {:ok, state()} | {:error, term()}
@callback command(state(), command()) :: {:ok, reply, new_state} | {:error, reason, new_state}
@callback telemetry(state()) :: {:ok, map(), state()} | {:error, term(), state()}
@callback disconnect(state()) :: :ok
```

This allows swapping adapters without changing user code.

## Why One GenServer Per Drone?

- Each drone has independent state (position, battery, mode)
- Sequential command processing matches the Tello UDP protocol
- A crash in one drone process does not affect others
- Supervision enables automatic restart
- Named processes via Registry provide easy lookup

## Why Adapters as Behaviours?

- Simulator adapts the same API for testing
- Tello adapter handles UDP communication
- Crazyflie adapter speaks CRTP over Crazyradio (or `mock://`)
- Future adapters (MAVLink, …) use the same contract
- User code is adapter-agnostic

## Why Simulator-First?

- Test all APIs without hardware
- Safety validation in simulation shows identical behavior
- Fast iteration cycle
- Educational value
- Mission replay and failure injection

## Further Reading

- Guides: [Crazyflie](crazyflie.md), [Swarms](swarm.md), [Formations](formations.md), [Adapter Authoring](adapter_authoring.md)
- Design: [Adapter Contract](design/adapter_contract.md), [Safety Pipeline](design/safety_pipeline.md), [Telemetry Events](design/telemetry_events.md), [v0.3.0 Deferred](design/v0_3_0_deferred.md)
- OTP and telemetry background: [Further Reading](further_reading.md#beam-otp-and-telemetry)
