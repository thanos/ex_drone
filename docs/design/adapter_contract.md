# Adapter Contract Design

## Overview

The `Drone.Adapter` behaviour defines the contract between `Drone.Vehicle` and drone-specific implementations. Every adapter must implement this behaviour, enabling the Vehicle to be adapter-agnostic.

## The Behaviour

```elixir
defmodule Drone.Adapter do
  @type state :: term()

  @callback connect(opts :: keyword()) ::
              {:ok, state()}
              | {:error, term()}

  @callback command(state :: state(), command :: Drone.Command.t()) ::
              {:ok, reply :: term(), new_state :: state()}
              | {:error, reason :: term(), new_state :: state()}

  @callback telemetry(state :: state()) ::
              {:ok, map(), state()}
              | {:error, term(), state()}

  @callback disconnect(state :: state()) :: :ok
end
```

## Contract Details

### connect/1

Called when `Drone.connect/2` is invoked. The adapter receives all options passed to `Drone.connect/2` (except `:name` and `:safety`, which are consumed by the Vehicle).

**Returns:**
- `{:ok, state}` -- Connection successful. The `state` is an opaque term that will be passed to all subsequent callbacks.
- `{:error, reason}` -- Connection failed. The Vehicle process will not start.

**Responsibilities:**
- Open any necessary connections (UDP socket for Tello, nothing for Sim)
- Initialize adapter-specific state
- Perform initial handshake if required (e.g., sending `command` to enter SDK mode for Tello)

**Important:** The adapter should NOT enter SDK mode in `connect/1`. The Vehicle will call `command(state, %Command{type: :sdk_mode})` separately if needed. This separation allows testing the connection independently from the SDK mode activation.

However, for the Tello adapter specifically, the SDK mode `command` must be sent before any other command. The Vehicle handles this sequence.

### command/2

Called for every command after the safety pipeline has approved it (except `emergency`, which bypasses safety).

**Returns:**
- `{:ok, reply, new_state}` -- Command succeeded. `reply` is an adapter-specific response (typically `:ok` for movement commands, a value for queries).
- `{:error, reason, new_state}` -- Command failed. The error reason should be descriptive.

**Responsibilities:**
- Send the command to the drone (or simulate it)
- Parse the response
- Update adapter state (position, battery, etc.)
- Return the result

**Important:** `new_state` must always be returned, even on error. This allows partial state updates (e.g., updating battery drain even on a failed command).

### telemetry/1

Called to retrieve current telemetry data from the adapter.

**Returns:**
- `{:ok, telemetry_map, state}` -- Telemetry retrieved successfully.
- `{:error, reason, state}` -- Telemetry retrieval failed.

The telemetry map should include:

```elixir
%{
  x: integer(),           # cm from launch point
  y: integer(),           # cm from launch point
  z: integer(),           # cm altitude
  yaw: integer(),         # degrees (0-360)
  battery: integer(),     # percent (0-100)
  speed: integer(),       # cm/s
  flying: boolean(),      # whether the drone is in the air
  mode: atom(),           # :idle | :sdk_mode | :flying | :emergency
  last_command: Drone.Command.t() | nil,
  command_count: integer()
}
```

Adapters may include additional fields specific to their implementation.

### disconnect/1

Called when `Drone.disconnect/1` is invoked or when the Vehicle process is terminating.

**Returns:** `:ok`

**Responsibilities:**
- Close connections (UDP socket for Tello)
- Clean up resources
- No state update needed (the process is terminating)

## Adapter Registration

Adapters are referenced by atom in `Drone.connect/2`:

```elixir
Drone.connect(:sim, name: :test)      # -> Drone.Adapters.Sim
Drone.connect(:tello, name: :tello_1) # -> Drone.Adapters.Tello
```

The mapping is:

```elixir
@adapters %{
  sim: Drone.Adapters.Sim,
  tello: Drone.Adapters.Tello
}
```

Users can also pass a module directly:

```elixir
Drone.connect(MyCustomAdapter, name: :custom)
```

## Error Handling Contract

Adapters must follow these error conventions:

| Error Type              | When                                               |
|-------------------------|-----------------------------------------------------|
| `:timeout`              | No response from drone within timeout               |
| `:connection_error`     | Unable to establish connection                      |
| `:command_error`        | Drone returned `error` response                    |
| `:not_in_sdk_mode`      | Command sent before entering SDK mode               |
| `:not_flying`           | Movement command sent while not airborne            |
| `:already_flying`       | Takeoff sent while already flying                   |
| `:emergency_active`     | Command sent while in emergency state               |
| `:simulated_failure`    | Sim adapter configured to fail                      |

These are returned as `{:error, reason, new_state}` from `command/2`.

## State Isolation

Each adapter manages its own state independently. The Vehicle holds the adapter state as an opaque term and passes it to each callback. The adapter must not store state in process dictionaries, ETS, or other global state.

This design ensures:

1. Multiple drones can be controlled simultaneously
2. Adapters are testable in isolation
3. No hidden global state
4. Easy to swap adapters without changing user code

## Testing Contract

Adapters should be testable without real hardware. To enable this:

1. The Sim adapter should work with no external dependencies
2. The Tello adapter should support a fake UDP server for testing
3. All adapter callbacks should be pure functions of their state

Test pattern for any adapter:

```elixir
# Connect
{:ok, state} = MyAdapter.connect(opts)

# Send commands
{:ok, _, state} = MyAdapter.command(state, %Drone.Command{type: :takeoff})

# Check telemetry
{:ok, telemetry, _} = MyAdapter.telemetry(state)

# Disconnect
:ok = MyAdapter.disconnect(state)
```

## Future Adapters

The adapter contract must be stable enough for future adapters:

### Crazyflie (v0.3.0)

- Will use a Port/NIF for communication with cflib
- Connection will involve a URI (e.g., `radio://0/80/250K`)
- State will include more detailed telemetry (gyro, accel, etc.)
- Must implement the same behaviour

### MAVLink (v0.4.0)

- Will use a TCP/UDP connection to a MAVLink endpoint
- State will include full vehicle state (GPS, attitude, etc.)
- Must implement the same behaviour

The adapter contract should not need to change for these. If it does, that's a v2.0.0 concern.

## Mermaid: Adapter Architecture

```mermaid
classDiagram
    class Adapter {
        <<behaviour>>
        +connect(opts) {:ok, state} | {:error, reason}
        +command(state, command) {:ok, reply, state} | {:error, reason, state}
        +telemetry(state) {:ok, map, state} | {:error, reason, state}
        +disconnect(state) :ok
    }
    
    class Sim {
        +connect(opts)
        +command(state, command)
        +telemetry(state)
        +disconnect(state)
    }
    
    class Tello {
        +connect(opts)
        +command(state, command)
        +telemetry(state)
        +disconnect(state)
    }
    
    class Crazyflie {
        +connect(opts)
        +command(state, command)
        +telemetry(state)
        +disconnect(state)
    }
    
    class MAVLink {
        +connect(opts)
        +command(state, command)
        +telemetry(state)
        +disconnect(state)
    }
    
    Adapter <|.. Sim
    Adapter <|.. Tello
    Adapter <|.. Crazyflie
    Adapter <|.. MAVLink
    
    class Vehicle {
        -adapter: Adapter
        -adapter_state: term()
        -safety_policy: Policy
        -vehicle_state: map()
        +handle_call({:command, cmd}, from, state)
    }
    
    Vehicle --> Adapter : uses
    Vehicle --> Safety : validates through
```