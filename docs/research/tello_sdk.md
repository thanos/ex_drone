# Tello SDK Research

## Overview

The DJI Tello and Tello EDU drones expose a Wi-Fi UDP text-based command protocol for control and telemetry queries. This document covers the protocol details relevant to building an Elixir adapter.

## Protocol Basics

- **Transport**: UDP
- **Drone IP**: `192.168.10.1` (default, when connected to drone's Wi-Fi)
- **Command Port**: `8889` (default)
- **Local Command Socket**: configurable (Tello SDK typically uses `8889` as well)
- **Encoding**: Plain ASCII text commands, newline-terminated
- **Response**: Plain ASCII text responses (`ok`, `error`, numeric values)

## Connection Sequence

1. Connect to drone's Wi-Fi access point (SSID: `TELLO-XXXXXX`)
2. Open UDP socket on local port (default `8889`)
3. Send `command` to enter SDK mode
4. Receive `ok` or `error` response
5. Drone is now ready to accept commands

The Tello EDU supports station mode where the drone connects to your network, but the primary connection model is direct Wi-Fi.

## SDK Mode Activation

```
Send:    "command"
Receive: "ok"
```

This must be sent before any other command. Without it, the drone ignores UDP packets.

## Movement Commands

All movement commands are blocking from the drone's perspective. The drone sends the response only after completing the movement.

| Command        | Arguments      | Response | Notes                          |
|----------------|----------------|----------|--------------------------------|
| `takeoff`      | none           | ok/error | Auto-start motors, hover      |
| `land`         | none           | ok/error | Descend and stop motors       |
| `emergency`    | none           | ok/error | Stop motors immediately       |
| `up x`         | x: 20-500 cm   | ok/error | Ascend x cm                   |
| `down x`       | x: 20-500 cm   | ok/error | Descend x cm                  |
| `left x`       | x: 20-500 cm   | ok/error | Strafe left x cm              |
| `right x`     | x: 20-500 cm   | ok/error | Strafe right x cm             |
| `forward x`    | x: 20-500 cm   | ok/error | Move forward x cm             |
| `back x`       | x: 20-500 cm   | ok/error | Move backward x cm            |
| `cw x`         | x: 1-3600 deg | ok/error | Rotate clockwise x degrees    |
| `ccw x`        | x: 1-3600 deg | ok/error | Rotate counter-clockwise      |
| `flip x`       | x: l/r/f/b    | ok/error | Flip in direction              |
| `go x y z s`   | coords + speed | ok/error | Go to relative position       |
| `stop`         | none           | ok/error | Hover in place                |
| `speed x`      | x: 10-100 cm/s | ok/error | Set speed                      |

### Movement Constraints

- Minimum distance: 20 cm, maximum: 500 cm
- Minimum rotation: 1 degree, maximum: 3600 degrees
- Speed range: 10-100 cm/s
- The drone hovers between commands -- there is no "continue moving" mode in the text SDK
- Commands are queued: sending a new command while one is executing will queue it

## Query Commands

Query commands return numeric values instead of `ok`.

| Command    | Response          | Notes                        |
|------------|-------------------|------------------------------|
| `battery?` | `20-100`          | Battery percentage           |
| `height?`  | `0-800` (dm)      | Height in decimeters         |
| `speed?`   | `0-100`           | Current speed in cm/s        |
| `time?`    | `0-3600`          | Motor-on time in seconds     |
| `wifi?`    | `ssid signal`     | Wi-Fi signal info            |
| `sdk?`     | version string    | SDK version                  |
| `sn?`      | serial number     | Drone serial number          |

## Response Format

- **Success**: `ok` (for commands) or numeric string (for queries)
- **Error**: `error` (generic error)
- **Timeout**: No response within the configured timeout period
- **Not in SDK mode**: No response at all

## Timing and Throttling

- Default command timeout: varies by implementation, typically 5-15 seconds
- Movement commands block until the drone completes the action
- Queries are fast (sub-second)
- The SDK documentation recommends sending commands at a reasonable rate
- Sending commands too rapidly can cause dropped packets (UDP has no backpressure)
- The drone has an internal command queue with limited capacity

## State Machine

```
[Idle] --command--> [SDK Mode] --takeoff--> [Flying]
  ^                    |                      |  |
  |                    |                      |  |
  +--------------------+--land/emergency------+--+
```

- In Idle, the drone ignores all UDP commands except `command`
- In SDK Mode, the drone accepts commands but is not flying
- In Flying, movement and query commands work
- `land` returns to SDK Mode
- `emergency` returns to Idle (motors stop, need `command` again)

## UDP Considerations

- UDP is connectionless -- there is no handshake
- Packet loss is possible, especially over Wi-Fi
- The drone does not guarantee command delivery
- Commands may arrive out of order if sent rapidly
- No built-in acknowledgment beyond the text response
- Socket should be bound to a specific local port and reused for the session

## Tello EDU vs Tello (Standard)

| Feature        | Tello            | Tello EDU                   |
|----------------|------------------|------------------------------|
| Station mode   | No               | Yes                          |
| Multi-drone    | No               | Yes (via router)             |
| Mission pad    | No               | Yes                          |
| Maximum range  | ~100m            | ~100m                        |
| Command port   | 8889             | 8889                         |
| SDK version    | 2.0              | 3.0                          |

The Tello EDU's station mode is essential for swarm control: it allows the drone to join a Wi-Fi network rather than creating its own access point.

## Safety Considerations

- **emergency** must always be available and bypass all normal safety checks
- **takeoff** and **land** are single-command actions that move the drone through critical state transitions
- Movement commands take time to complete -- retrying them automatically is dangerous
- The drone has no collision avoidance in the text SDK
- Battery state is only available via polling -- there is no push notification
- Wi-Fi range limitation means commands may silently fail
- The drone will auto-land at low battery regardless of commands

## Design Implications for ex_drone

1. **One UDP socket per drone**: Each drone connection needs its own `:gen_udp` socket bound to a local port.
2. **Sequential command model**: Commands must be sent one at a time, waiting for the response before sending the next. This maps naturally to a GenServer's sequential message processing.
3. **Timeout handling**: Every command needs a configurable timeout. Movement commands need longer timeouts than queries.
4. **No retry policy for movement**: Per the prompt, movement commands must not be automatically retried. Only query commands may be retried.
5. **State tracking required**: Since the drone only responds with `ok`/`error`/numeric, the Elixir side must track position state for safety validation.
6. **Emergency bypass**: The `emergency` command must bypass all safety checks and be sent regardless of current state.
7. **Command encoding is trivial**: Commands are simple ASCII strings. The main complexity is in timing, safety, and state management, not in protocol encoding.