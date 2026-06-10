# Safety

Safety is a first-class concern in ex_drone. Every command passes through a safety pipeline before reaching the drone adapter.

## Why Safety Matters

Drones are physical devices that can cause injury. A software bug should never result in a dangerous flight. The safety pipeline enforces limits by default.

## Safety Pipeline

```
Command Requested
  -> Emergency? -> Bypass all, send immediately
  -> Validate Command Args -> Reject if out of Tello SDK range
  -> Check Mode -> Reject if not in a valid state
  -> Allowlist? -> Reject if not allowed
  -> Flying Requirement? -> Reject if state does not match
  -> Altitude? -> Reject if exceeds max
  -> Distance? -> Reject if exceeds max
  -> Battery? -> Reject takeoff if too low
  -> Geofence? -> Reject if outside area
  -> Emit Telemetry
  -> Send to Adapter
  -> Parse Result
  -> Update Vehicle State
```

## Command Argument Limits

Movement arguments are validated against the Tello SDK protocol ranges
before any policy checks. Out-of-range values are rejected with
`{:error, :safety, reason}`:

- `move/3` distance: 20-500 cm (`:invalid_distance`)
- `rotate/3` degrees: 1-3600 (`:invalid_degrees`)
- `set_speed/2` speed: 10-100 cm/s (`:invalid_speed`)
- `hover/2` seconds: must be a positive integer (`:invalid_seconds`)

## Safety Policy Configuration

```elixir
Drone.Safety.Policy.new(
  max_altitude_cm: 300,
  max_distance_cm: 1000,
  min_battery_percent: 15,
  battery_warning_percent: 20,
  indoor: false,
  prop_guards: false,
  dry_run: false,
  allowlist: nil,
  geofence: Drone.Safety.Geofence.radius(500)
)
```

## Presets

- `Drone.Safety.Policy.default()` -- Outdoor defaults (3m altitude, 10m distance)
- `Drone.Safety.Policy.indoor()` -- Indoor defaults (2m altitude, 5m distance)
- `Drone.Safety.Policy.unrestricted()` -- No limits (use with caution)

## Emergency Commands

Emergency commands always bypass the safety pipeline:

```elixir
Drone.emergency(drone)  # Always succeeds, stops motors immediately
```

## Dry-Run Mode

Validate missions without flying:

```elixir
{:ok, drone} = Drone.connect(:sim, name: :test, safety: [dry_run: true])
Drone.connect_sdk(drone)
Drone.takeoff(drone)  # Returns :ok, validated but no command sent to the drone
```

## Geofencing

Restrict flight to a circular area:

```elixir
geofence = Drone.Safety.Geofence.circle({0, 0}, 500)
{:ok, drone} = Drone.connect(:sim, name: :geofenced,
  safety: [geofence: geofence]
)
```

Or a polygon:

```elixir
geofence = Drone.Safety.Geofence.polygon([{0, 0}, {1000, 0}, {1000, 1000}, {0, 1000}])
```

## Command Allowlists

Restrict which commands are allowed:

```elixir
{:ok, drone} = Drone.connect(:sim, name: :observer,
  safety: [allowlist: [:sdk_mode, :query]]
)
```

The `:emergency` command is always allowed regardless of the allowlist.