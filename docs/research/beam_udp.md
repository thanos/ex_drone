# BEAM UDP Research

## Overview

This document covers how UDP networking works on the BEAM (Erlang VM) using `:gen_udp`, and how to design a robust UDP client for the Tello command protocol.

## :gen_udp Basics

Erlang's `:gen_udp` module provides a simple UDP interface:

```elixir
# Open a socket
{:ok, socket} = :gen_udp.open(8889, [:inet, {:active, true}])

# Send a datagram
:gen_udp.send(socket, {192, 168, 10, 1}, 8889, "command")

# Receive (when active mode)
# A message {:udp, socket, host, port, data} arrives in the process mailbox

# Close
:gen_udp.close(socket)
```

## Active vs Passive Mode

### Active Mode (`{:active, true}`)

- Incoming datagrams arrive as `{:udp, socket, host, port, data}` messages in the process mailbox
- Best for low-traffic UDP where the owning process handles messages directly
- Risk: mailbox overflow if messages arrive faster than they are processed
- Natural fit for GenServer -- handle_info/3 receives the UDP messages

### Active Once (`{:active, :once}`)

- After each received message, the socket reverts to passive mode
- The process must call `:inet.setopts(socket, active: :once)` to receive the next message
- Provides backpressure -- the process controls the receive rate
- Recommended pattern for most UDP applications in Elixir

### Passive Mode (`{:active, false}`)

- Must call `:gen_udp.recv/3` to read datagrams (blocking call)
- Provides natural backpressure
- Not suitable for GenServer-style event-driven programming
- Useful for testing or synchronous command-response patterns

### Recommended Approach for Tello

Use `{:active, :once}` mode. This gives us:

- Event-driven message handling in the GenServer
- Backpressure control to prevent mailbox overflow
- Ability to mix active receiving with synchronous reads

## Socket Ownership

- A UDP socket is owned by the process that opens it
- Only the owning process can receive messages from an active socket
- This aligns with one-drone-per-GeneServer: each `Drone.Vehicle` GenServer owns its own socket
- Socket ownership cannot be transferred (unlike TCP with `:gen_tcp.controlling_process/2`)

## Command-Response Pattern

The Tello protocol is fundamentally request-response over UDP:

```
Client sends command -> ... UDP transit ... -> Drone processes -> Drone sends response -> ... UDP transit ... -> Client receives response
```

This maps to a GenServer call pattern:

```elixir
def handle_call({:send_command, command}, _from, %{socket: socket} = state) do
  :gen_udp.send(socket, drone_ip, drone_port, command)
  # Wait for {:udp, socket, host, port, data} via handle_info
  # Use a timer for timeout
end
```

However, since `handle_call` blocks until a reply, we cannot receive `handle_info` messages within the same call. The proper pattern is:

1. Send the command via `:gen_udp.send/4`
2. Set a ref-based timer for timeout
3. Return `{:noreply, new_state}` from `handle_call`
4. Receive the response in `handle_info/2`
5. Reply to the caller using `GenServer.reply(from, response)`

Or use a simpler synchronous pattern:

1. Switch to passive mode temporarily
2. Send command
3. Call `:gen_udp.recv/3` with a timeout
4. Switch back to active mode
5. Return the result

For the Tello use case, the **simpler synchronous pattern** is recommended because:

- We only talk to one drone per socket
- Commands are sequential (one at a time)
- We don't need to process unsolicited messages (Tello only responds to commands)
- The code is easier to understand and test

## Implementation Pattern

```elixir
defmodule Drone.Adapters.Tello.Connection do
  @default_drone_ip {192, 168, 10, 1}
  @default_drone_port 8889
  @default_local_port 8889
  @default_timeout 10_000

  def send_command(socket, command, opts \\ []) do
    ip = Keyword.get(opts, :drone_ip, @default_drone_ip)
    port = Keyword.get(opts, :drone_port, @default_drone_port)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    # Send the command
    :ok = :gen_udp.send(socket, ip, port, command)

    # Switch to passive mode to receive response
    :inet.setopts(socket, active: false)

    # Receive response synchronously
    result =
      case :gen_udp.recv(socket, 0, timeout) do
        {:ok, {_ip, _port, response}} ->
          parse_response(response)
        {:error, :timeout} ->
          {:error, :timeout}
      end

    # Switch back to active mode
    :inet.setopts(socket, active: :once)

    result
  end
end
```

## Testing with Fake UDP Server

For testing without a real drone, we need a fake UDP server:

```elixir
defmodule Drone.Test.FakeTelloServer do
  use GenServer

  def start_link(opts \\ []) do
    port = Keyword.get(opts, :port, 9000)
    GenServer.start_link(__MODULE__, port, name: __MODULE__)
  end

  def init(port) do
    {:ok, socket} = :gen_udp.open(port, [:inet, {:active, true}])
    {:ok, %{socket: socket, state: :idle}}
  end

  def handle_info({:udp, _socket, ip, port, "command"}, state) do
    :gen_udp.send(state.socket, ip, port, "ok")
    {:noreply, %{state | state: :sdk_mode}}
  end

  def handle_info({:udp, _socket, ip, port, "takeoff"}, %{state: :sdk_mode} = state) do
    :gen_udp.send(state.socket, ip, port, "ok")
    {:noreply, %{state | state: :flying}}
  end

  # ... more handlers
end
```

Key testing considerations:

- Use ephemeral ports (not 8889) to avoid conflicts
- The fake server must respond on the same socket the client sends to
- The fake server can simulate delays, errors, and timeouts
- Tests should verify both happy path and error scenarios

## UDP Packet Size

- Maximum UDP packet size is 65507 bytes for IPv4
- Tello commands are very small (< 50 bytes)
- No need for packet fragmentation handling
- Responses are also small (`ok`, `error`, or short numeric strings)

## Error Handling

### Socket Errors

- `{:error, :eaddrinuse}` -- Port already in use
- `{:error, :eacces}` -- Permission denied (ports < 1024 require root)
- `{:error, :enetunreach}` -- Network unreachable

### Communication Errors

- `:timeout` -- No response within the timeout period
- `{:error, :closed}` -- Socket was closed
- Malformed response -- Unexpected response format

### BEAM-Specific Considerations

- If the owning process dies, the socket is automatically closed
- UDP sockets do not have a "connected" state -- `:gen_udp.send` always succeeds (packet is just sent)
- The BEAM handles socket port management (port driver)
- No connection state to manage, but must handle the drone's logical state machine

## Concurrency Model

```
Drone.Supervisor
  |
  +-- Drone.Vehicle (:tello_1)
  |     +-- owns :gen_udp socket
  |     +-- sequential command processing
  |     +-- state: %{socket, drone_ip, drone_port, position, ...}
  |
  +-- Drone.Vehicle (:tello_2)
        +-- owns :gen_udp socket
        +-- ...
```

- Each `Drone.Vehicle` GenServer owns exactly one UDP socket
- Commands are processed sequentially per drone (Tello's protocol requires this)
- Multiple drones can operate concurrently (one process per drone)
- The Supervisor ensures crashed drones are restarted

## Binary vs Text Protocol

The Tello text protocol uses plain ASCII strings. This means:

- No binary parsing needed
- Commands are constructed by string concatenation
- Responses are simple pattern matches
- The main complexity is in timing and state management, not encoding

Contrast with MAVLink (v0.4.0), which uses a binary packet format requiring careful encoding/decoding.

## Summary

| Aspect                   | Approach                                       |
|--------------------------|-------------------------------------------------|
| Socket mode              | `{:active, :once}` with sync recv for commands |
| Command pattern          | Synchronous send-then-receive                   |
| One socket per drone     | Yes, owned by the Vehicle GenServer            |
| Fake server for testing  | Yes, using :gen_udp in test processes           |
| Error model              | Explicit `{:ok, _}` / `{:error, _}` tuples     |
| Concurrency              | One GenServer per drone, sequential commands    |