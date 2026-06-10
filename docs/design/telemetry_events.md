# Telemetry Events Design

## Overview

ex_drone uses the standard Elixir `:telemetry` library to emit events for observability. All events follow the `[:drone, namespace, action]` naming convention.

## Event Naming Convention

Events are organized by namespace:

| Namespace  | Purpose                              |
|------------|--------------------------------------|
| `:drone`   | Top-level drone namespace            |
| `connect`  | Connection lifecycle                  |
| `command`  | Command execution                    |
| `safety`   | Safety validations and rejections     |
| `telemetry`| Telemetry data updates               |
| `vehicle`  | Vehicle state changes                |

## Events

### Connection Events

#### `[:drone, :connect, :start]`

Emitted when a connection attempt begins.

```elixir
:telemetry.execute(
  [:drone, :connect, :start],
  %{timestamp: System.monotonic_time()},
  %{adapter: :sim | :tello, name: atom()}
)
```

#### `[:drone, :connect, :stop]`

Emitted when a connection succeeds.

```elixir
:telemetry.execute(
  [:drone, :connect, :stop],
  %{duration: non_neg_integer(), timestamp: System.monotonic_time()},
  %{adapter: :sim | :tello, name: atom()}
)
```

#### `[:drone, :connect, :error]`

Emitted when a connection fails.

```elixir
:telemetry.execute(
  [:drone, :connect, :error],
  %{timestamp: System.monotonic_time()},
  %{adapter: :sim | :tello, name: atom(), reason: term()}
)
```

#### `[:drone, :disconnect]`

Emitted when a drone is disconnected.

```elixir
:telemetry.execute(
  [:drone, :disconnect],
  %{timestamp: System.monotonic_time()},
  %{adapter: :sim | :tello, name: atom()}
)
```

### Command Events

#### `[:drone, :command, :start]`

Emitted when a command is sent to the adapter (after passing safety checks).

```elixir
:telemetry.execute(
  [:drone, :command, :start],
  %{command: atom(), args: keyword(), timestamp: System.monotonic_time()},
  %{adapter: :sim | :tello, name: atom()}
)
```

#### `[:drone, :command, :stop]`

Emitted when a command succeeds.

```elixir
:telemetry.execute(
  [:drone, :command, :stop],
  %{command: atom(), duration: non_neg_integer(), result: :ok | :dry_run, timestamp: System.monotonic_time()},
  %{adapter: :sim | :tello, name: atom()}
)
```

#### `[:drone, :command, :error]`

Emitted when a command fails at the adapter level (after passing safety).

```elixir
:telemetry.execute(
  [:drone, :command, :error],
  %{command: atom(), duration: non_neg_integer(), reason: atom(), timestamp: System.monotonic_time()},
  %{adapter: :sim | :tello, name: atom()}
)
```

### Safety Events

#### `[:drone, :safety, :reject]`

Emitted when the safety pipeline rejects a command.

```elixir
:telemetry.execute(
  [:drone, :safety, :reject],
  %{command: atom(), reason: atom(), timestamp: System.monotonic_time()},
  %{adapter: :sim | :tello, name: atom()}
)
```

Possible reasons: `:command_not_allowed`, `:not_in_sdk_mode`, `:not_flying`, `:already_flying`, `:max_altitude`, `:max_distance`, `:low_battery`, `:geofence_violation`

#### `[:drone, :safety, :warning]`

Emitted when the safety pipeline allows a command but with a warning.

```elixir
:telemetry.execute(
  [:drone, :safety, :warning],
  %{command: atom(), warning: atom(), timestamp: System.monotonic_time()},
  %{adapter: :sim | :tello, name: atom()}
)
```

Possible warnings: `:low_battery`, `:no_prop_guards`

### Telemetry Data Events

#### `[:drone, :telemetry, :update]`

Emitted when telemetry data is retrieved from the vehicle.

```elixir
:telemetry.execute(
  [:drone, :telemetry, :update],
  %{
    x: integer(),
    y: integer(),
    z: integer(),
    yaw: integer(),
    battery: integer(),
    speed: integer(),
    flying: boolean(),
    mode: atom(),
    timestamp: System.monotonic_time()
  },
  %{adapter: :sim | :tello, name: atom()}
)
```

### Emergency Events

#### `[:drone, :emergency]`

Emitted when an emergency stop is triggered.

```elixir
:telemetry.execute(
  [:drone, :emergency],
  %{timestamp: System.monotonic_time()},
  %{adapter: :sim | :tello, name: atom()}
)
```

This event is emitted regardless of the outcome of the emergency command. It signals intent.

## Telemetry Module

The `Drone.Telemetry` module provides helper functions for emitting events:

```elixir
defmodule Drone.Telemetry do
  @spec emit_connect_start(atom(), atom()) :: :ok
  def emit_connect_start(adapter, name)

  @spec emit_connect_stop(atom(), atom(), non_neg_integer()) :: :ok
  def emit_connect_stop(adapter, name, duration)

  @spec emit_connect_error(atom(), atom(), term()) :: :ok
  def emit_connect_error(adapter, name, reason)

  @spec emit_disconnect(atom(), atom()) :: :ok
  def emit_disconnect(adapter, name)

  @spec emit_command_start(atom(), atom(), Drone.Command.t()) :: :ok
  def emit_command_start(adapter, name, command)

  @spec emit_command_stop(atom(), atom(), Drone.Command.t(), atom(), non_neg_integer()) :: :ok
  def emit_command_stop(adapter, name, command, result, duration)

  @spec emit_command_error(atom(), atom(), Drone.Command.t(), atom(), non_neg_integer()) :: :ok
  def emit_command_error(adapter, name, command, reason, duration)

  @spec emit_safety_reject(atom(), atom(), atom(), atom()) :: :ok
  def emit_safety_reject(adapter, name, command_type, reason)

  @spec emit_safety_warning(atom(), atom(), atom(), atom()) :: :ok
  def emit_safety_warning(adapter, name, command_type, warning)

  @spec emit_telemetry_update(atom(), atom(), map()) :: :ok
  def emit_telemetry_update(adapter, name, telemetry)

  @spec emit_emergency(atom(), atom()) :: :ok
  def emit_emergency(adapter, name)
end
```

## Testing Telemetry

Use `:telemetry.attach/4` in tests to verify events are emitted:

```elixir
test "emits command start and stop events" do
  {:ok, drone} = Drone.connect(:sim, name: :test)
  Drone.connect_sdk(drone)

  events = []
  :telemetry.attach_many(
    :test_handler,
    [[:drone, :command, :start], [:drone, :command, :stop]],
    fn name, measurements, metadata, _config ->
      send(self(), {:telemetry_event, name, measurements, metadata})
    end,
    nil
  )

  Drone.takeoff(drone)

  assert_receive {:telemetry_event, [:drone, :command, :start], %{command: :takeoff}, _}
  assert_receive {:telemetry_event, [:drone, :command, :stop], %{command: :takeoff, result: :ok}, _}

  :telemetry.detach(:test_handler)
end
```

## Integration with Observability Tools

The telemetry events can be consumed by:

- **Telemetry Metrics**: Define metrics (counter, last value, distribution, summary) for use with Phoenix metrics or LiveDashboard
- **Logger**: Attach a handler that logs important events
- **StatsD**: Forward events to StatsD via `telemetry_metrics_statsd`
- **Livebook**: Visualize real-time drone telemetry

Example metrics definitions:

```elixir
[
  counter("drone.command.start.count", tags: [:adapter, :command]),
  counter("drone.command.stop.count", tags: [:adapter, :command]),
  counter("drone.command.error.count", tags: [:adapter, :command, :reason]),
  counter("drone.safety.reject.count", tags: [:adapter, :reason]),
  counter("drone.emergency.count", tags: [:adapter]),
  last_value("drone.telemetry.update.battery", tags: [:adapter]),
  last_value("drone.telemetry.update.altitude", tags: [:adapter]),
  distribution("drone.command.stop.duration", tags: [:adapter, :command])
]
```

## Event Flow Summary

```
User Code              Vehicle GenServer              :telemetry
   |                        |
   |-- Drone.takeoff() ---->|
   |                        |-- Safety.check()
   |                        |    |-- rejected --> [:drone, :safety, :reject] --> {:error, :safety, reason}
   |                        |    |-- approved --> [:drone, :command, :start] --> adapter.command()
   |                        |                                      |
   |                        |                      [:drone, :command, :stop] or [:drone, :command, :error]
   |<-- {:ok, :ok} --------|
   |                        |
   |-- Drone.emergency() ->|
   |                        |-- [:drone, :emergency] --> adapter.command() (bypass safety)
   |<-- {:ok, :ok} --------|
   |                        |
   |-- Drone.telemetry() -->|
   |                        |-- [:drone, :telemetry, :update] --> {:ok, map()}
   |<-- {:ok, map()} ------|
```