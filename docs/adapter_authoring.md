# Adapter Authoring

This guide explains how to create a custom drone adapter for ex_drone.

## The Adapter Behaviour

All adapters must implement `Drone.Adapter`:

```elixir
defmodule Drone.Adapter do
  @callback connect(opts :: keyword()) :: {:ok, state()} | {:error, term()}
  @callback command(state(), command()) :: {:ok, reply, new_state} | {:error, reason, new_state}
  @callback telemetry(state()) :: {:ok, map(), state()} | {:error, term(), state()}
  @callback disconnect(state()) :: :ok
end
```

## Creating an Adapter

### 1. Define the Module

```elixir
defmodule Drone.Adapters.MyDrone do
  @behaviour Drone.Adapter

  defstruct [:connection, :position]

  @impl Drone.Adapter
  def connect(opts) do
    # Open connection, return initial state
    {:ok, %__MODULE__{position: {0, 0, 0}}}
  end

  @impl Drone.Adapter
  def command(state, %Drone.Command{type: :takeoff}) do
    # Send takeoff command, update state
    {:ok, :ok, %{state | position: {0, 0, 30}}}
  end

  # ... implement other command types

  @impl Drone.Adapter
  def telemetry(state) do
    {:ok, %{x: state.position.x, y: state.position.y}, state}
  end

  @impl Drone.Adapter
  def disconnect(state) do
    # Close connection
    :ok
  end
end
```

### 2. Register the Adapter

Users can pass the module directly:

```elixir
{:ok, drone} = Drone.connect(Drone.Adapters.MyDrone, name: :my_drone)
```

Or add it to the built-in map in `Drone.Adapter.resolve/1`.

### 3. Handle All Command Types

Your adapter must handle (or gracefully reject) all command types:

- `:sdk_mode`, `:takeoff`, `:land`, `:emergency`
- `:move` (with direction and distance)
- `:rotate` (with direction and degrees)
- `:flip` (with direction)
- `:hover` (with seconds)
- `:speed` (with speed value)
- `:stop`
- `:query` (with type: battery, height, speed, time, wifi, sdk_version, serial_number)

### 4. State Management Rules

- The `state` term is opaque. Use a struct for clarity.
- Always return `new_state` from `command/2`, even on error.
- The `telemetry/1` callback should return at minimum: `x`, `y`, `z`, `yaw`, `battery`, `flying`, `mode`.

### 5. Error Conventions

Return errors as `{:error, reason, new_state}`:

- `:timeout` -- No response from drone
- `:connection_error` -- Connection failed
- `:not_in_sdk_mode` -- Command sent before SDK mode
- `:not_flying` -- Movement when grounded
- `:already_flying` -- Takeoff when airborne

## Testing

Test your adapter using the simulator pattern:

```elixir
# Connect
{:ok, state} = MyAdapter.connect([])

# Send commands
{:ok, _, state} = MyAdapter.command(state, Drone.Command.takeoff())

# Check telemetry
{:ok, telemetry, _} = MyAdapter.telemetry(state)
assert telemetry.flying == true

# Disconnect
:ok = MyAdapter.disconnect(state)
```