# Safety Model Research

## Overview

This document defines the safety model for ex_drone. Safety is a first-class concern, not an afterthought. The library must prevent dangerous operations by default and make safe operations easy.

## Why Safety Matters

Drones are physical devices that can cause injury or property damage. A software bug should never result in:

- A drone flying into a person
- A drone exceeding safe altitude
- A drone flying out of range or control
- A drone continuing to fly with low battery
- Uncontrolled motor operation

The BEAM's supervision model gives us a natural advantage: we can enforce safety at the process level and ensure safety checks cannot be bypassed by user code.

## Safety Principles

1. **Default to safe**: All APIs should default to the safest possible configuration
2. **Explicit opt-in for danger**: Dangerous operations require explicit flags, not just missing safety flags
3. **Emergency always works**: The emergency stop command must bypass all checks and always be sent to the drone
4. **No automatic retry of movement commands**: If a movement command fails, the drone should not automatically try again
5. **Fail safe on disconnection**: If communication is lost, the drone should land (handled by Tello's auto-land, enforced by our state tracking)
6. **State-aware validation**: Safety checks consider the current known state of the drone

## Command Classification

### Safe Commands (may be retried)

| Command     | Reason                                          |
|-------------|-------------------------------------------------|
| `battery?`  | Query only, no side effects                     |
| `height?`   | Query only, no side effects                     |
| `speed?`    | Query only, no side effects                     |
| `time?`     | Query only, no side effects                     |
| `wifi?`     | Query only, no side effects                     |
| `sdk?`      | Query only, no side effects                     |
| `sn?`       | Query only, no side effects                     |

### Dangerous Commands (must not be auto-retried)

| Command     | Reason                                          |
|-------------|-------------------------------------------------|
| `takeoff`   | Changes state from ground to air                |
| `land`      | Changes state from air to ground                |
| `up`        | Physical movement                               |
| `down`      | Physical movement                               |
| `left`      | Physical movement                               |
| `right`     | Physical movement                               |
| `forward`   | Physical movement                               |
| `back`      | Physical movement                               |
| `cw`        | Physical movement                               |
| `ccw`       | Physical movement                               |
| `flip`      | Physical movement, unpredictable trajectory     |
| `go`        | Physical movement to coordinates                 |
| `speed`     | Affects subsequent movement safety              |

### Emergency Commands (always pass through)

| Command     | Reason                                          |
|-------------|-------------------------------------------------|
| `emergency` | Must stop motors immediately, regardless of any safety state |

## Safety Policies

### Max Altitude

- Default: 3 meters (300 cm)
- Configurable per-drone
- Prevents `up` commands that would exceed the limit
- Indoor mode defaults to 2 meters

### Max Distance

- Default: 10 meters (1000 cm) from launch point
- Configurable per-drone
- Prevents movement commands that would exceed the limit
- Indoor mode defaults to 5 meters

### Min Battery

- Default: 15%
- Land warning at: 20%
- Prevents takeoff below minimum
- Warns on movement commands below warning threshold
- Does NOT prevent movement commands below minimum (too dangerous to freeze the drone mid-air) -- but logs/telemetry should flag it

### Command Allowlist

- By default, all commands are allowed
- Users can restrict to a specific set of commands (e.g., only queries + emergency for observation mode)
- Useful for educational settings where students should not have full control
- `emergency` is ALWAYS on the allowlist, even if the user omits it

### Dry-Run Mode

- When enabled, commands pass through safety validation but are not actually sent to the drone
- Useful for testing mission scripts without a real drone
- Returns `{:ok, :dry_run}` instead of `{:ok, result}`
- Safety rejections still return `{:error, :safety, reason}`

### Indoor Mode

A preset that tightens safety limits:

- Max altitude: 2 meters
- Max distance: 5 meters
- Max speed: 30 cm/s
- Requires prop guards flag (warning only)

### Emergency Stop

- Immediately sends `emergency` to the drone
- Bypasses all safety checks (including allowlist)
- Bypasses command queue
- Sets vehicle state to `:emergency`
- Emits `[:drone, :emergency]` telemetry event
- After emergency, the drone must be reconnected

### Geofence

- Define an allowed area as a polygon or radius from launch point
- Movement commands that would take the drone outside the geofence are rejected
- Geofence violations are reported via telemetry
- Default: no geofence (infinite range, subject to max_distance)

### Prop Guards Flag

- A boolean indicating whether prop guards are installed
- When `false`, certain commands may trigger warnings (e.g., `flip`)
- Does not prevent commands, only warns
- Intended for educational settings where instructors verify safety

## Safety Pipeline

The safety pipeline processes every command before it reaches the adapter:

```
Command Requested
    |
    v
Normalize Command
    |
    v
Validate Command Shape (correct arguments, ranges)
    |
    v
Check Safety Policy
    |--- Emergency? --> Bypass all, send immediately
    |--- Allowlist?  --> Reject if not allowed
    |--- Altitude?   --> Reject if would exceed max
    |--- Distance?   --> Reject if would exceed max
    |--- Battery?    --> Warn if low, reject takeoff if critical
    |--- Geofence?   --> Reject if would leave area
    |
    v
Emit Telemetry ([:drone, :command, :start])
    |
    v
Send to Adapter
    |
    v
Parse Result
    |
    v
Update Vehicle State
    |
    v
Emit Telemetry ([:drone, :command, :stop] or [:drone, :command, :error])
```

## Implementation as a Module

`Drone.Safety` should be a pure module (no process, no state) that takes a command and a safety policy, and returns either `{:ok, command}` or `{:error, :safety, reason}`.

```elixir
@spec check(command :: Command.t(), policy :: Safety.policy(), state :: Vehicle.state()) ::
        {:ok, Command.t()} | {:error, :safety, atom()}
```

This design:

- Is deterministic and testable
- Has no hidden state
- Can be composed (check policy A, then check policy B)
- Can be used in dry-run mode without a drone
- Allows the Vehicle GenServer to hold the policy and state, passing both to Safety

## Safety Configuration

```elixir
%Drone.Safety.Policy{
  max_altitude_cm: 300,
  max_distance_cm: 1000,
  min_battery_percent: 15,
  battery_warning_percent: 20,
  allowlist: nil,          # nil = all allowed
  dry_run: false,
  indoor: false,
  prop_guards: false,
  geofence: nil            # nil = no geofence
}
```

The `Drone.connect/2` function accepts a `:safety` keyword list that maps to this struct:

```elixir
{:ok, drone} = Drone.connect(:tello,
  name: :tello_1,
  safety: [
    max_altitude_cm: 300,
    indoor: true,
    prop_guards: true
  ]
)
```

## Safety in the Simulator

The simulator must enforce the same safety rules as real adapters. This ensures:

- Missions tested in the simulator respect safety limits
- Safety violations are caught before connecting to a real drone
- Educational scenarios work identically in simulation and reality

The simulator should also be able to simulate safety events:

- Battery drain (configurable rate)
- Simulated command failures (for testing error handling)
- Geofence violations (for testing rejection logic)
- Connection loss (for testing timeout handling)

## Warning vs Rejection

Safety checks produce two types of results:

1. **Rejection** (`{:error, :safety, reason}`): The command is not sent. Used for hard limits like max_altitude, geofence, allowlist.

2. **Warning** (`{:ok, command, warnings}`): The command is sent but a warning is logged and emitted as telemetry. Used for soft limits like battery_warning, missing prop_guards.

This distinction is important:

- Warnings should never prevent a command that could be safe
- Rejections should always prevent a command that could be dangerous
- Users must be able to configure which checks are warnings vs rejections

## State Tracking for Safety

The `Drone.Vehicle` GenServer maintains estimated state:

```elixir
%{
  x: 0,           # cm from launch point
  y: 0,           # cm from launch point
  z: 0,           # cm (altitude)
  yaw: 0,         # degrees
  flying: false,
  battery: 100,   # percent
  last_command: nil,
  command_history: [],
  state: :idle | :sdk_mode | :flying | :emergency
}
```

Position estimation is approximate:

- Movement commands represent intended distances, not guaranteed distances
- Real-world drift is expected
- Safety margins should account for estimation error
- The simulator's position is exact, which is useful for deterministic testing

## Summary

| Safety Feature       | Type        | Default           | Emergency Bypass |
|----------------------|-------------|-------------------|------------------|
| Max altitude         | Hard limit  | 300 cm            | Yes              |
| Max distance         | Hard limit  | 1000 cm           | Yes              |
| Min battery (takeoff)| Hard limit  | 15%               | Yes              |
| Battery warning      | Soft warning| 20%               | Yes              |
| Command allowlist    | Hard limit  | All allowed       | Yes (emergency always) |
| Dry-run mode         | Mode switch | Off               | No (no commands sent) |
| Indoor mode          | Preset      | Off               | N/A              |
| Prop guards          | Soft warning| false             | N/A              |
| Geofence             | Hard limit  | None              | Yes              |