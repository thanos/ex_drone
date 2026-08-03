defmodule Drone.Adapters.Tello do
  @moduledoc """
  Tello drone adapter for ex_drone.

  This adapter communicates with DJI Tello and Tello EDU drones over
  Wi-Fi UDP using the official Tello SDK protocol.

  ## Default Configuration

    - Drone IP: `192.168.10.1`
    - Drone port: `8889`
    - Local port: `8889`
    - Command timeout: `10_000` ms

  ## Usage

      {:ok, drone} = Drone.connect(:tello, name: :tello_1)
      Drone.connect_sdk(drone)
      Drone.takeoff(drone)
      Drone.move(drone, :forward, 50)
      Drone.land(drone)
      Drone.disconnect(drone)

  ## Custom Configuration

      {:ok, drone} = Drone.connect(:tello,
        name: :tello_1,
        drone_ip: {192, 168, 10, 1},
        drone_port: 8889,
        local_port: 9030,
        timeout: 15_000
      )

  **Safety warning**: The Tello is a real physical drone. Always test in
  the simulator first. Use prop guards. Do not fly near faces. Have an
  emergency stop ready.
  """

  @behaviour Drone.Adapter

  alias Drone.{
    Adapter.Capabilities,
    Adapters.Tello.Connection,
    Adapters.Tello.Encoder,
    Adapters.Tello.Parser,
    Command,
    Geometry
  }

  defstruct [
    :socket,
    :drone_ip,
    :drone_port,
    :timeout,
    mode: :idle,
    flying: false,
    x: 0,
    y: 0,
    z: 0,
    yaw: 0
  ]

  @typedoc """
  Tello adapter state held by `Drone.Vehicle`.

  | Field | Type | Meaning |
  | --- | --- | --- |
  | `:socket` | `port()` \\| `nil` | UDP socket used for SDK commands |
  | `:drone_ip` | `:inet.ip_address()` | Drone address (default `{192, 168, 10, 1}`) |
  | `:drone_port` | `non_neg_integer()` | Drone command port (default `8889`) |
  | `:timeout` | `non_neg_integer()` | Command reply timeout in ms |
  | `:mode` | `:idle` \\| `:sdk_mode` \\| `:flying` \\| `:emergency` | Flight mode |
  | `:flying` | `boolean()` | Whether airborne |
  | `:x`, `:y`, `:z` | `integer()` | Dead-reckoned position in centimeters |
  | `:yaw` | `integer()` | Heading in degrees |

  ## Example

      %Drone.Adapters.Tello{
        drone_ip: {192, 168, 10, 1},
        drone_port: 8889,
        timeout: 10_000,
        mode: :flying,
        flying: true,
        z: 50
      }
  """
  @type t :: %__MODULE__{
          socket: port() | nil,
          drone_ip: :inet.ip_address(),
          drone_port: non_neg_integer(),
          timeout: non_neg_integer(),
          mode: :idle | :sdk_mode | :flying | :emergency,
          flying: boolean(),
          x: integer(),
          y: integer(),
          z: integer(),
          yaw: integer()
        }

  @doc """
  Opens a UDP socket and returns initial Tello adapter state.

  ## Parameters

    * `opts` (`keyword()`) — common keys:
      * `:drone_ip` (`:inet.ip_address()`) — default `{192, 168, 10, 1}`
      * `:drone_port` (`non_neg_integer()`) — default `8889`
      * `:local_port` (`non_neg_integer()`) — local bind port
      * `:timeout` (`non_neg_integer()`) — reply timeout ms

  ## Returns

    * `{:ok, t()}` — connected (socket open; SDK mode not yet entered)
    * `{:error, term()}` — socket open failure

  ## Examples

      {:ok, state} =
        Drone.Adapters.Tello.connect(
          drone_ip: {192, 168, 10, 1},
          local_port: 9030
        )
  """
  @impl Drone.Adapter
  def connect(opts) do
    ip = Keyword.get(opts, :drone_ip, Connection.default_drone_ip())
    port = Keyword.get(opts, :drone_port, Connection.default_drone_port())
    local_port = Keyword.get(opts, :local_port, Connection.default_local_port())
    timeout = Keyword.get(opts, :timeout, Connection.default_timeout())

    case Connection.open(local_port: local_port) do
      {:ok, socket} ->
        state = %__MODULE__{
          socket: socket,
          drone_ip: ip,
          drone_port: port,
          timeout: timeout
        }

        {:ok, state}

      {:error, reason} ->
        {:error, {:connection_error, reason}}
    end
  end

  @doc """
  Sends an encoded SDK command over UDP and updates dead-reckoned state.

  ## Parameters

    * `state` (`t:t/0`) — open adapter state
    * `cmd` (`Drone.Command.t()`) — command to encode and send

  ## Returns

    * `{:ok, reply, t()}` — parsed reply (`:ok` or query value)
    * `{:error, reason, t()}` — UDP or parse failure

  ## Examples

      {:ok, :ok, state} =
        Drone.Adapters.Tello.command(state, Drone.Command.sdk_mode())
  """
  @impl Drone.Adapter
  def command(
        %__MODULE__{socket: socket, drone_ip: ip, drone_port: port, timeout: timeout} = state,
        %Command{} = cmd
      ) do
    encoded = Encoder.encode(cmd)
    conn_opts = [drone_ip: ip, drone_port: port, timeout: timeout]

    case Connection.send_command(socket, encoded, conn_opts) do
      {:ok, response} ->
        case Parser.parse(response) do
          {:ok, :ok} ->
            new_state = update_state(state, cmd)
            {:ok, :ok, new_state}

          {:ok, value} ->
            new_state = update_state(state, cmd)
            {:ok, value, new_state}

          {:error, reason} ->
            {:error, reason, state}
        end

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  @doc """
  Returns a telemetry snapshot from dead-reckoned adapter fields.

  ## Parameters

    * `state` (`t:t/0`)

  ## Returns

  `{:ok, map(), t()}` with `:x`, `:y`, `:z`, `:yaw`, `:flying`, `:mode`.
  """
  @impl Drone.Adapter
  def telemetry(%__MODULE__{} = state) do
    {:ok,
     %{
       x: state.x,
       y: state.y,
       z: state.z,
       yaw: state.yaw,
       flying: state.flying,
       mode: state.mode
     }, state}
  end

  @doc """
  Closes the UDP socket.

  ## Parameters

    * `state` (`t:t/0`)

  ## Returns

  Always `:ok`.
  """
  @impl Drone.Adapter
  def disconnect(%__MODULE__{socket: socket} = _state) do
    if socket, do: Connection.close(socket)
    :ok
  end

  @doc """
  Returns Tello-like capability metadata.

  ## Parameters

    * `state` (`t:t/0`) — unused beyond dispatch

  ## Returns

  `Drone.Adapter.Capabilities.tello_like/0`.
  """
  @impl Drone.Adapter
  def capabilities(%__MODULE__{}), do: Capabilities.tello_like()

  defp update_state(%__MODULE__{} = state, %Command{type: :sdk_mode}) do
    %{state | mode: :sdk_mode}
  end

  defp update_state(%__MODULE__{} = state, %Command{type: :takeoff}) do
    %{state | z: 30, flying: true, mode: :flying}
  end

  defp update_state(%__MODULE__{} = state, %Command{type: :land}) do
    %{state | z: 0, flying: false, mode: :sdk_mode}
  end

  defp update_state(%__MODULE__{} = state, %Command{type: :emergency}) do
    %{state | mode: :emergency, flying: false}
  end

  defp update_state(%__MODULE__{} = state, %Command{type: :move, args: args}) do
    direction = Keyword.fetch!(args, :direction)
    distance = Keyword.fetch!(args, :distance)
    {dx, dy, dz} = Geometry.move_delta(direction, distance, state.yaw)

    %{state | x: state.x + dx, y: state.y + dy, z: max(0, state.z + dz)}
  end

  defp update_state(%__MODULE__{} = state, %Command{type: :rotate, args: args}) do
    direction = Keyword.fetch!(args, :direction)
    degrees = Keyword.fetch!(args, :degrees)
    %{state | yaw: Geometry.rotate_yaw(direction, state.yaw, degrees)}
  end

  defp update_state(%__MODULE__{} = state, %Command{type: :flip, args: args}) do
    direction = Keyword.fetch!(args, :direction)
    {dx, dy} = Geometry.flip_delta(direction)
    %{state | x: state.x + dx, y: state.y + dy}
  end

  defp update_state(%__MODULE__{} = state, %Command{type: :speed, args: _args}) do
    state
  end

  defp update_state(%__MODULE__{} = state, %Command{type: :stop}) do
    state
  end

  defp update_state(%__MODULE__{} = state, %Command{type: :hover}) do
    state
  end

  defp update_state(%__MODULE__{} = state, %Command{type: :query, args: args}) do
    query_type = Keyword.fetch!(args, :type)

    case query_type do
      :height -> %{state | z: nil}
      _ -> state
    end
  end
end
