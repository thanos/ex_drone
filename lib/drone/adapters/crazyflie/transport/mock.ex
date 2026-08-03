defmodule Drone.Adapters.Crazyflie.Transport.Mock do
  @moduledoc """
  In-process Crazyflie transport for CI and dry development.

  Profiles (via `mock://PROFILE` or `:mock_profile`):

  * `:default` / `:ready` — healthy estimator, full battery
  * `:estimator_not_ready` — rejects takeoff readiness
  * `:low_battery` — reports low battery percent
  * `:unplug` — next send fails with `:link_lost`

  Simulates link probe, protocol version, logging TOC/control/data,
  supervisor, and high-level commander replies so `Session.connect/2`
  and adapter commands work without hardware.
  """

  @behaviour Drone.Adapters.Crazyflie.Transport

  alias Drone.Adapters.Crazyflie.CRTP
  alias Drone.Adapters.Crazyflie.CRTP.Ports
  alias Drone.Adapters.Crazyflie.LinkURI
  alias Drone.Adapters.Crazyflie.Logging

  @linkctrl Ports.port(:linkctrl)
  @platform Ports.port(:platform)
  @logging Ports.port(:logging)
  @supervisor Ports.port(:supervisor)
  @setpoint_hl Ports.port(:setpoint_hl)

  @toc [
    %{id: 0, type: 1, group: "pm", name: "batteryLevel"},
    %{id: 1, type: 1, group: "sys", name: "canfly"}
  ]

  @typedoc """
  In-memory mock radio / Crazyflie state.
  """
  @type t :: %__MODULE__{
          profile: atom() | nil,
          protocol_version: integer(),
          battery_percent: integer(),
          estimator_ready: boolean(),
          armed: boolean(),
          flying: boolean(),
          x: float(),
          y: float(),
          z: float(),
          yaw: float(),
          unplugged: boolean(),
          sent: [CRTP.packet()],
          log_layout: [Logging.layout_entry()] | nil,
          log_block_id: byte() | nil,
          logging_started: boolean()
        }

  defstruct [
    :profile,
    protocol_version: 8,
    battery_percent: 95,
    estimator_ready: true,
    armed: false,
    flying: false,
    x: 0.0,
    y: 0.0,
    z: 0.0,
    yaw: 0.0,
    unplugged: false,
    sent: [],
    log_layout: nil,
    log_block_id: nil,
    logging_started: false
  ]

  @doc """
  Opens a mock transport with a profile from opts or URI.
  """
  @impl true
  def open(opts) do
    profile = resolve_profile(opts)

    state =
      %__MODULE__{profile: profile}
      |> apply_profile(profile)

    {:ok, state}
  end

  @doc """
  Handles CRTP packets and returns synthetic ACKs.
  """
  @impl true
  def send(%__MODULE__{unplugged: true} = state, _packet) do
    {:error, :link_lost, state}
  end

  def send(%__MODULE__{} = state, packet) do
    state = %{state | sent: Enum.take([packet | state.sent], 32)}

    if CRTP.null?(packet) do
      handle_null(state)
    else
      dispatch_port(state, packet.port, packet.channel, packet.payload)
    end
  end

  defp dispatch_port(state, @linkctrl, 1, _payload) do
    {:ok, %{acked: true, retries: 0, payload: "Bitcraze Crazyflie"}, state}
  end

  defp dispatch_port(state, @platform, 1, _payload) do
    {:ok, %{acked: true, retries: 0, payload: <<0, state.protocol_version>>}, state}
  end

  defp dispatch_port(state, @logging, 0, payload), do: handle_toc(state, payload)
  defp dispatch_port(state, @logging, 1, payload), do: handle_log_control(state, payload)
  defp dispatch_port(state, @supervisor, _channel, payload), do: handle_supervisor(state, payload)
  defp dispatch_port(state, @setpoint_hl, _channel, payload), do: handle_commander(state, payload)
  defp dispatch_port(state, _port, _channel, _payload), do: {:ok, ack(), state}

  @doc """
  Closes the mock transport (no resources to release).
  """
  @impl true
  def close(%__MODULE__{}), do: :ok

  @doc """
  Returns simulated battery / estimator / flight flags for the adapter.
  """
  @impl true
  def telemetry(%__MODULE__{} = state) do
    {:ok,
     %{
       battery: state.battery_percent,
       estimator_ready: state.estimator_ready,
       flying: state.flying,
       armed: state.armed,
       firmware: "mock",
       serial_number: "mock-cf",
       link_quality: if(state.unplugged, do: 0, else: 100)
     }, state}
  end

  @doc false
  def configure_logging(%__MODULE__{} = state, layout, block_id)
      when is_list(layout) and is_integer(block_id) do
    %{state | log_layout: layout, log_block_id: block_id, logging_started: true}
  end

  @doc false
  def ingest_ack_payload(%__MODULE__{} = state, _payload), do: state

  @doc false
  def force_unplug(%__MODULE__{} = state), do: %{state | unplugged: true}

  defp resolve_profile(opts) do
    cond do
      opts[:mock_profile] ->
        opts[:mock_profile]

      is_binary(opts[:uri]) ->
        case LinkURI.parse(opts[:uri]) do
          {:ok, %{mock_profile: profile}} -> profile
          _ -> :default
        end

      true ->
        :default
    end
  end

  defp apply_profile(state, :estimator_not_ready), do: %{state | estimator_ready: false}
  defp apply_profile(state, :low_battery), do: %{state | battery_percent: 10}
  defp apply_profile(state, :unplug), do: %{state | unplugged: true}
  defp apply_profile(state, _), do: %{state | estimator_ready: true, battery_percent: 95}

  defp handle_null(%__MODULE__{logging_started: true} = state) do
    canfly = if state.estimator_ready, do: 1, else: 0
    block_id = state.log_block_id || 0
    log_payload = <<block_id, 0, 0, 0, state.battery_percent, canfly>>

    {:ok, encoded} =
      CRTP.encode(%{
        port: Ports.port(:logging),
        channel: Logging.data_channel(),
        payload: log_payload
      })

    {:ok, %{acked: true, retries: 0, payload: encoded}, state}
  end

  defp handle_null(state), do: {:ok, ack(), state}

  defp handle_toc(state, <<0x03>>) do
    count = length(@toc)
    reply = <<0x03, count::little-16, 0xAABBCCDD::little-32, 16, 128>>
    {:ok, %{acked: true, retries: 0, payload: reply}, state}
  end

  defp handle_toc(state, <<0x02, id::little-16>>) do
    case Enum.find(@toc, &(&1.id == id)) do
      nil ->
        {:ok, %{acked: true, retries: 0, payload: <<0x02>>}, state}

      item ->
        reply =
          <<0x02, item.id::little-16, item.type, item.group::binary, 0, item.name::binary, 0>>

        {:ok, %{acked: true, retries: 0, payload: reply}, state}
    end
  end

  defp handle_toc(state, _), do: {:ok, ack(), state}

  defp handle_log_control(state, <<0x05>>) do
    {:ok, %{acked: true, retries: 0, payload: <<0x05, 0, 0>>}, %{state | logging_started: false}}
  end

  defp handle_log_control(state, <<0x06, block_id, _ops::binary>>) do
    {:ok, %{acked: true, retries: 0, payload: <<0x06, block_id, 0>>},
     %{state | log_block_id: block_id}}
  end

  defp handle_log_control(state, <<0x08, block_id, _period::little-16>>) do
    {:ok, %{acked: true, retries: 0, payload: <<0x08, block_id, 0>>},
     %{state | log_block_id: block_id, logging_started: true}}
  end

  defp handle_log_control(state, _), do: {:ok, ack(), state}

  defp handle_supervisor(state, <<0>>), do: {:ok, ack(), %{state | armed: true}}
  defp handle_supervisor(state, <<1>>), do: {:ok, ack(), %{state | armed: false, flying: false}}

  defp handle_supervisor(state, <<2>>),
    do: {:ok, ack(), %{state | armed: false, flying: false, z: 0.0}}

  defp handle_supervisor(state, _), do: {:ok, ack(), state}

  defp handle_commander(state, <<7, _group, height::little-float-32, _rest::binary>>) do
    if state.estimator_ready do
      {:ok, ack(), %{state | flying: true, armed: true, z: height}}
    else
      {:error, :estimator_not_ready, state}
    end
  end

  defp handle_commander(state, <<8, _group, height::little-float-32, _rest::binary>>) do
    {:ok, ack(), %{state | flying: false, z: height, armed: false}}
  end

  defp handle_commander(state, <<3, _group>>) do
    {:ok, ack(), %{state | flying: false, armed: false}}
  end

  defp handle_commander(
         state,
         <<12, _g, relative, _linear, x::little-float-32, y::little-float-32, z::little-float-32,
           yaw::little-float-32, _dur::little-float-32>>
       ) do
    {nx, ny, nz, nyaw} =
      if relative == 1 do
        {state.x + x, state.y + y, state.z + z, state.yaw + yaw}
      else
        {x, y, z, yaw}
      end

    {:ok, ack(), %{state | x: nx, y: ny, z: nz, yaw: nyaw}}
  end

  defp handle_commander(state, _), do: {:ok, ack(), state}

  defp ack, do: %{acked: true, retries: 0, payload: <<>>}
end
