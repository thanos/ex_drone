# Safety Pipeline Design

## Overview

The safety pipeline is a critical component of ex_drone. It processes every command before it reaches the adapter, ensuring that dangerous operations are prevented by default.

## Pipeline Architecture

```mermaid
flowchart TD
    Request[Command Requested] --> Normalize[Normalize Command]
    Normalize --> Validate[Validate Command Shape]
    Validate --> CheckEmergency{Emergency?}
    CheckEmergency -->|Yes| EmitEmergency[Emit :emergency telemetry]
    CheckEmergency -->|No| CheckPolicy[Check Safety Policy]
    EmitEmergency --> SendAdapter[Send to Adapter]
    CheckPolicy --> CheckAllowlist{In Allowlist?}
    CheckAllowlist -->|No| RejectAllowlist[Reject: :command_not_allowed]
    CheckAllowlist -->|Yes| CheckState{Validate State}
    CheckState --> CheckFlying{Requires Flying?}
    CheckFlying -->|Not Flying| RejectFlying[Reject: :not_flying]
    CheckFlying -->|Is Flying| CheckAltitude{Exceeds Max Alt?}
    CheckAltitude -->|Yes| RejectAlt[Reject: :max_altitude]
    CheckAltitude -->|No| CheckDistance{Exceeds Max Dist?}
    CheckDistance -->|Yes| RejectDist[Reject: :max_distance]
    CheckDistance -->|No| CheckBattery{Low Battery?}
    CheckBattery -->|Critical| RejectBattery[Reject: :low_battery]
    CheckBattery -->|Warning| WarnBattery[Warn but Allow]
    CheckBattery -->|OK| CheckGeofence{Geofence Violation?}
    WarnBattery --> CheckGeofence
    CheckGeofence -->|Yes| RejectGeofence[Reject: :geofence_violation]
    CheckGeofence -->|No| EmitStart[Emit :command, :start telemetry]
    EmitStart --> SendAdapter
    RejectAllowlist --> EmitReject[Emit :safety, :reject telemetry]
    RejectFlying --> EmitReject
    RejectAlt --> EmitReject
    RejectDist --> EmitReject
    RejectBattery --> EmitReject
    RejectGeofence --> EmitReject
    EmitReject --> ReturnError[Return {:error, :safety, reason}]
    SendAdapter --> ParseResult[Parse Result]
    ParseResult --> UpdateState[Update Vehicle State]
    UpdateState --> EmitStop[Emit :command, :stop telemetry]
    EmitStop --> ReturnOk[Return {:ok, result}]
```

## Drone.Safety Module

### API

```elixir
defmodule Drone.Safety do
  @type policy :: Drone.Safety.Policy.t()
  @type state :: Drone.Vehicle.state()
  @type command :: Drone.Command.t()
  @type rejection_reason ::
          :command_not_allowed
          | :not_in_sdk_mode
          | :not_flying
          | :already_flying
          | :max_altitude
          | :max_distance
          | :low_battery
          | :geofence_violation
          | :dangerous_without_prop_guards

  @spec check(command(), policy(), state()) ::
          {:ok, command()}
          | {:ok, command(), [atom()]}
          | {:error, :safety, rejection_reason()}
  def check(command, policy, state)
end
```

The `{:ok, command, warnings}` return type carries soft warnings (like low battery warning, missing prop guards). The Vehicle module can log these and emit telemetry.

### Check Ordering

Checks are performed in this specific order. If a check rejects the command, no subsequent checks are performed:

1. **Emergency bypass**: If the command is `:emergency`, return `{:ok, command}` immediately
2. **SDK mode check**: Commands other than `:sdk_mode` and `:emergency` require `:sdk_mode` or `:flying` state
3. **Allowlist check**: If a command allowlist is defined, reject commands not on the list (emergency always passes)
4. **State validation**: Check the command is appropriate for the current state (e.g., `:takeoff` requires `:sdk_mode`, movement requires `:flying`)
5. **Altitude check**: If the command would increase altitude beyond `max_altitude_cm`, reject
6. **Distance check**: If the command would move the drone beyond `max_distance_cm` from origin, reject
7. **Battery check (takeoff)**: If `battery < min_battery_percent`, reject takeoff
8. **Battery check (warning)**: If `battery < battery_warning_percent`, add a warning
9. **Geofence check**: If a geofence is defined and the command would leave it, reject
10. **Prop guards check**: If `prop_guards: false` and the command is `:flip`, add a warning

### Range Validation

Before safety checks, commands are validated for correct argument ranges:

| Command Type    | Validation                                              |
|-----------------|---------------------------------------------------------|
| `:move`         | Direction must be valid, distance 20-500 cm             |
| `:rotate`       | Direction must be :cw or :ccw, degrees 1-3600           |
| `:flip`         | Direction must be :left, :right, :forward, :back        |
| `:speed`        | Speed 10-100 cm/s                                        |
| `:hover`        | Seconds must be positive                                 |

Invalid commands return `{:error, :invalid_command, details}` before reaching safety checks.

## Drone.Safety.Policy Struct

```elixir
defmodule Drone.Safety.Policy do
  @type t :: %__MODULE__{
    max_altitude_cm: pos_integer() | nil,
    max_distance_cm: pos_integer() | nil,
    min_battery_percent: non_neg_integer(),
    battery_warning_percent: non_neg_integer(),
    allowlist: [atom()] | nil,
    dry_run: boolean(),
    indoor: boolean(),
    prop_guards: boolean(),
    geofence: Drone.Safety.Geofence.t() | nil
  }

  defstruct [
    max_altitude_cm: 300,
    max_distance_cm: 1000,
    min_battery_percent: 15,
    battery_warning_percent: 20,
    allowlist: nil,
    dry_run: false,
    indoor: false,
    prop_guards: false,
    geofence: nil
  ]

  @spec indoor() :: t()
  def indoor do
    %__MODULE__{
      max_altitude_cm: 200,
      max_distance_cm: 500,
      min_battery_percent: 20,
      battery_warning_percent: 25,
      indoor: true,
      prop_guards: true
    }
  end

  @spec unrestricted() :: t()
  def unrestricted do
    %__MODULE__{
      max_altitude_cm: nil,
      max_distance_cm: nil,
      min_battery_percent: 0,
      battery_warning_percent: 0,
      allowlist: nil,
      dry_run: false,
      indoor: false,
      prop_guards: true
    }
  end
end
```

## Geofence

```elixir
defmodule Drone.Safety.Geofence do
  @type t :: %__MODULE__{
    type: :circle | :polygon,
    center: {float(), float()} | nil,
    radius_cm: pos_integer() | nil,
    points: [{float(), float()}] | nil
  }

  defstruct [:type, :center, :radius_cm, :points]

  @spec circle(center :: {float(), float()}, radius_cm :: pos_integer()) :: t()
  def circle(center, radius_cm) do
    %__MODULE__{type: :circle, center: center, radius_cm: radius_cm}
  end

  @spec polygon(points :: [{float(), float()}]) :: t()
  def polygon(points) do
    %__MODULE__{type: :polygon, points: points}
  end

  @spec contains?(geofence :: t(), point :: {float(), float()}) :: boolean()
  def contains?(%__MODULE__{type: :circle, center: {cx, cy}, radius_cm: r}, {px, py}) do
    dx = px - cx
    dy = py - cy
    :math.sqrt(dx * dx + dy * dy) <= r
  end

  def contains?(%__MODULE__{type: :polygon, points: points}, point) do
    # Ray casting algorithm
    point_in_polygon?(point, points)
  end
end
```

## How Safety Integrates with Vehicle

```elixir
defmodule Drone.Vehicle do
  use GenServer

  def handle_call({:command, cmd}, _from, state) do
    # 1. Check safety
    case Drone.Safety.check(cmd, state.safety_policy, state.vehicle_state) do
      {:error, :safety, reason} ->
        :telemetry.execute([:drone, :safety, :reject], %{
          reason: reason,
          command: cmd.type
        })
        {:reply, {:error, :safety, reason}, state}

      {:ok, cmd} ->
        execute_command(cmd, state)

      {:ok, cmd, warnings} ->
        # Log warnings, emit telemetry
        for warning <- warnings do
          :telemetry.execute([:drone, :safety, :warning], %{warning: warning, command: cmd.type})
        end
        execute_command(cmd, state)
    end
  end

  def handle_call(:emergency, _from, state) do
    # Emergency bypasses ALL safety checks
    :telemetry.execute([:drone, :emergency], %{})
    cmd = %Drone.Command{type: :emergency}
    {:ok, _, new_adapter_state} = state.adapter_module.command(state.adapter_state, cmd)
    new_vehicle_state = %{state.vehicle_state | mode: :emergency}
    {:reply, :ok, %{state | adapter_state: new_adapter_state, vehicle_state: new_vehicle_state}}
  end

  defp execute_command(cmd, state) do
    :telemetry.execute([:drone, :command, :start], %{command: cmd.type})

    if state.safety_policy.dry_run do
      :telemetry.execute([:drone, :command, :stop], %{command: cmd.type, result: :dry_run})
      {:reply, {:ok, :dry_run}, state}
    else
      case state.adapter_module.command(state.adapter_state, cmd) do
        {:ok, reply, new_adapter_state} ->
          new_vehicle_state = update_vehicle_state(state.vehicle_state, cmd, reply)
          :telemetry.execute([:drone, :command, :stop], %{command: cmd.type, result: :ok})
          {:reply, {:ok, reply}, %{state | adapter_state: new_adapter_state, vehicle_state: new_vehicle_state}}

        {:error, reason, new_adapter_state} ->
          :telemetry.execute([:drone, :command, :error], %{command: cmd.type, reason: reason})
          {:reply, {:error, reason}, %{state | adapter_state: new_adapter_state}}
      end
    end
  end
end
```

## Dry-Run Mode

When `dry_run: true`:

- All commands pass through the full safety pipeline
- After safety approval, commands are NOT sent to the adapter
- Returns `{:ok, :dry_run}` instead of the adapter's response
- The vehicle state is NOT updated
- This allows testing entire missions with safety validation without a drone

## Indoor Mode

Indoor mode is a convenience preset that sets:

```elixir
%Drone.Safety.Policy{
  max_altitude_cm: 200,    # 2 meters
  max_distance_cm: 500,    # 5 meters
  min_battery_percent: 20, # Higher threshold for indoor
  battery_warning_percent: 25,
  indoor: true,
  prop_guards: true        # Assume prop guards for indoor
}
```

This is a preset only -- individual values can still be overridden:

```elixir
Drone.connect(:tello, safety: [indoor: true, max_altitude_cm: 500])
```

## Testing the Safety Pipeline

The safety module is pure and should be exhaustively tested:

```elixir
describe "altitude safety" do
  test "rejects movement above max altitude" do
    policy = %Drone.Safety.Policy{max_altitude_cm: 100}
    state = %{mode: :flying, z: 80, battery: 100, flying: true}
    cmd = %Drone.Command{type: :move, args: [direction: :up, distance: 30]}

    assert {:error, :safety, :max_altitude} = Drone.Safety.check(cmd, policy, state)
  end

  test "allows movement within max altitude" do
    policy = %Drone.Safety.Policy{max_altitude_cm: 100}
    state = %{mode: :flying, z: 50, battery: 100, flying: true}
    cmd = %Drone.Command{type: :move, args: [direction: :up, distance: 30]}

    assert {:ok, ^cmd} = Drone.Safety.check(cmd, policy, state)
  end
end

describe "emergency bypass" do
  test "always allows emergency" do
    policy = %Drone.Safety.Policy{allowlist: [:battery?]}  # Only queries allowed
    state = %{mode: :emergency, z: 50, battery: 5, flying: true}
    cmd = %Drone.Command{type: :emergency}

    assert {:ok, ^cmd} = Drone.Safety.check(cmd, policy, state)
  end
end
```