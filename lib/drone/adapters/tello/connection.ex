defmodule Drone.Adapters.Tello.Connection do
  @moduledoc """
  UDP connection helper for the Tello drone.

  Manages a `:gen_udp` socket for sending SDK command strings and receiving
  ASCII responses over Wi-Fi. Defaults match the official Tello SDK network:

  | Constant | Default |
  | --- | --- |
  | Drone IP | `{192, 168, 10, 1}` |
  | Drone port | `8889` |
  | Local bind port | `8889` |
  | Reply timeout | `10_000` ms |

  ## Examples

      {:ok, socket} = Drone.Adapters.Tello.Connection.open(local_port: 9030)

      {:ok, "ok"} =
        Drone.Adapters.Tello.Connection.send_command(socket, "command",
          drone_ip: {192, 168, 10, 1},
          timeout: 5_000
        )

      :ok = Drone.Adapters.Tello.Connection.close(socket)
  """

  @default_drone_ip {192, 168, 10, 1}
  @default_drone_port 8889
  @default_local_port 8889
  @default_timeout 10_000

  @doc """
  Default Tello station IP address.

  ## Returns

  `:inet.ip_address()` — `{192, 168, 10, 1}`.

  ## Examples

      {192, 168, 10, 1} = Drone.Adapters.Tello.Connection.default_drone_ip()
  """
  @spec default_drone_ip() :: :inet.ip_address()
  def default_drone_ip, do: @default_drone_ip

  @doc """
  Default Tello command UDP port.

  ## Returns

  `8889`.

  ## Examples

      8889 = Drone.Adapters.Tello.Connection.default_drone_port()
  """
  @spec default_drone_port() :: pos_integer()
  def default_drone_port, do: @default_drone_port

  @doc """
  Default local UDP bind port.

  ## Returns

  `8889`.

  ## Examples

      8889 = Drone.Adapters.Tello.Connection.default_local_port()
  """
  @spec default_local_port() :: pos_integer()
  def default_local_port, do: @default_local_port

  @doc """
  Default command reply timeout in milliseconds.

  ## Returns

  `10_000`.

  ## Examples

      10_000 = Drone.Adapters.Tello.Connection.default_timeout()
  """
  @spec default_timeout() :: pos_integer()
  def default_timeout, do: @default_timeout

  @doc """
  Opens a passive UDP socket bound to the local port.

  ## Parameters

    * `opts` (`keyword()`) — optional:
      * `:local_port` (`non_neg_integer()`) — bind port (default `8889`)

  ## Returns

    * `{:ok, port()}` — open `:gen_udp` socket (`active: false`)
    * `{:error, term()}` — bind failure (for example `:eaddrinuse`)

  ## Examples

      {:ok, socket} = Drone.Adapters.Tello.Connection.open(local_port: 0)
      :ok = Drone.Adapters.Tello.Connection.close(socket)
  """
  @spec open(keyword()) :: {:ok, port()} | {:error, term()}
  def open(opts \\ []) do
    local_port = Keyword.get(opts, :local_port, @default_local_port)
    :gen_udp.open(local_port, [:inet, {:active, false}])
  end

  @doc """
  Closes a UDP socket opened with `open/1`.

  ## Parameters

    * `socket` (`port()`) — socket from `open/1`

  ## Returns

  Always `:ok`.

  ## Examples

      :ok = Drone.Adapters.Tello.Connection.close(socket)
  """
  @spec close(port()) :: :ok
  def close(socket) do
    :gen_udp.close(socket)
  end

  @doc """
  Sends a command string and waits for one UDP reply.

  ## Parameters

    * `socket` (`port()`) — open UDP socket
    * `command` (`String.t()`) — ASCII SDK command (from
      `Drone.Adapters.Tello.Encoder.encode/1`)
    * `opts` (`keyword()`) — optional:
      * `:drone_ip` (`:inet.ip_address()`) — default `{192, 168, 10, 1}`
      * `:drone_port` (`non_neg_integer()`) — default `8889`
      * `:timeout` (`non_neg_integer()`) — recv timeout ms (default `10_000`)

  ## Returns

    * `{:ok, binary()}` — raw reply payload (not yet parsed)
    * `{:error, :timeout}` — no datagram within the timeout
    * `{:error, term()}` — send or socket failure

  ## Examples

      {:ok, reply} =
        Drone.Adapters.Tello.Connection.send_command(socket, "battery?",
          timeout: 3_000
        )

      {:ok, percent} = Drone.Adapters.Tello.Parser.parse(reply)
  """
  @spec send_command(port(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def send_command(socket, command, opts \\ []) do
    ip = Keyword.get(opts, :drone_ip, @default_drone_ip)
    port = Keyword.get(opts, :drone_port, @default_drone_port)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    case :gen_udp.send(socket, ip, port, command) do
      :ok ->
        receive_response(socket, timeout)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Receives one UDP datagram from the Tello (or times out).

  Charlist payloads from older OTP paths are converted to binaries.

  ## Parameters

    * `socket` (`port()`) — open UDP socket in passive mode
    * `timeout` (`non_neg_integer()`) — milliseconds to wait

  ## Returns

    * `{:ok, binary()}` — reply bytes
    * `{:error, :timeout}` — no packet received
    * `{:error, term()}` — other `:gen_udp.recv/3` errors

  ## Examples

      {:ok, data} = Drone.Adapters.Tello.Connection.receive_response(socket, 5_000)
      {:error, :timeout} =
        Drone.Adapters.Tello.Connection.receive_response(socket, 1)
  """
  @spec receive_response(port(), non_neg_integer()) :: {:ok, binary()} | {:error, term()}
  def receive_response(socket, timeout) do
    case :gen_udp.recv(socket, 0, timeout) do
      {:ok, {_ip, _port, data}} when is_binary(data) ->
        {:ok, data}

      {:ok, {_ip, _port, data}} when is_list(data) ->
        {:ok, :erlang.list_to_binary(data)}

      {:error, :timeout} ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
