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

  alias Drone.{Adapters.Tello.Connection, Adapters.Tello.Encoder, Adapters.Tello.Parser, Command}

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

  @impl Drone.Adapter
  def connect(opts) do
    ip = Keyword.get(opts, :drone_ip, {192, 168, 10, 1})
    port = Keyword.get(opts, :drone_port, 8889)
    local_port = Keyword.get(opts, :local_port, 8889)
    timeout = Keyword.get(opts, :timeout, 10_000)

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

  @impl Drone.Adapter
  def disconnect(%__MODULE__{socket: socket} = _state) do
    if socket, do: Connection.close(socket)
    :ok
  end

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
    {dx, dy, dz} = move_delta(direction, distance, state.yaw)

    %{state | x: state.x + dx, y: state.y + dy, z: max(0, state.z + dz)}
  end

  defp update_state(%__MODULE__{} = state, %Command{type: :rotate, args: args}) do
    direction = Keyword.fetch!(args, :direction)
    degrees = Keyword.fetch!(args, :degrees)

    new_yaw =
      case direction do
        :cw -> rem(state.yaw + degrees, 360)
        :ccw -> rem(state.yaw - degrees + 360, 360)
      end

    %{state | yaw: new_yaw}
  end

  defp update_state(%__MODULE__{} = state, %Command{type: :flip, args: args}) do
    direction = Keyword.fetch!(args, :direction)

    {dx, dy} =
      case direction do
        :left -> {-20, 0}
        :right -> {20, 0}
        :forward -> {0, 20}
        :back -> {0, -20}
      end

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

  defp update_state(%__MODULE__{} = state, _cmd), do: state

  defp move_delta(:up, distance, _yaw), do: {0, 0, distance}
  defp move_delta(:down, distance, _yaw), do: {0, 0, -distance}
  defp move_delta(:forward, distance, yaw), do: forward_delta(distance, yaw)
  defp move_delta(:back, distance, yaw), do: forward_delta(-distance, yaw)
  defp move_delta(:left, distance, yaw), do: right_delta(-distance, yaw)
  defp move_delta(:right, distance, yaw), do: right_delta(distance, yaw)

  defp forward_delta(distance, yaw) do
    radians = yaw * :math.pi() / 180
    {trunc(distance * :math.sin(radians)), trunc(distance * :math.cos(radians)), 0}
  end

  defp right_delta(distance, yaw) do
    radians = yaw * :math.pi() / 180
    {trunc(distance * :math.cos(radians)), trunc(-distance * :math.sin(radians)), 0}
  end
end
