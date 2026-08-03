defmodule Drone.Adapters.Crazyflie.Transport.Crazyradio do
  @moduledoc """
  Crazyradio PA / Crazyradio 2.0 transport.

  Implements documented USB vendor setup and bulk EP1 send/ACK receive.
  Requires a `usb_backend` module implementing `Drone.Adapters.Crazyflie.USB`.

  When the URI enables SafeLink (`?safelink=1`), open negotiates SafeLink and
  stamps alternating uplink/downlink bits on every CRTP frame.

  After `Session` subscribes to CRTP logging, `telemetry/1` reports cached
  battery percent and estimator readiness from log-data ACK payloads.

  ## Examples

      {:ok, state} =
        Drone.Adapters.Crazyflie.Transport.Crazyradio.open(
          uri: "radio://0/80/2M",
          usb_backend: MyApp.CrazyradioUSB
        )

      {:ok, ack, state} =
        Drone.Adapters.Crazyflie.Transport.Crazyradio.send(
          state,
          Drone.Adapters.Crazyflie.CRTP.null_packet()
        )

      :ok = Drone.Adapters.Crazyflie.Transport.Crazyradio.close(state)
  """

  @behaviour Drone.Adapters.Crazyflie.Transport

  # Local `send/2` is the transport callback; avoid Kernel.send/2 clash.
  import Kernel, except: [send: 2]

  alias Drone.Adapters.Crazyflie.CRTP
  alias Drone.Adapters.Crazyflie.CRTP.Ports
  alias Drone.Adapters.Crazyflie.LinkURI
  alias Drone.Adapters.Crazyflie.Logging
  alias Drone.Adapters.Crazyflie.SafeLink
  alias Drone.Adapters.Crazyflie.USB.Unavailable

  @vid 0x1915
  @pid 0x7777

  @set_radio_channel 0x01
  @set_radio_address 0x02
  @set_data_rate 0x03
  @set_radio_power 0x04
  @set_radio_arc 0x06

  @safelink_enable_attempts 10

  @typedoc """
  Open Crazyradio transport state.

  | Field | Type | Meaning |
  | --- | --- | --- |
  | `:usb` | device handle | Opaque USB handle |
  | `:backend` | `module()` | `Drone.Adapters.Crazyflie.USB` implementation |
  | `:uri` | `LinkURI.t()` | Parsed radio URI |
  | `:safelink_enabled` | `boolean()` | SafeLink negotiated successfully |
  | `:safelink_up` | `0 \\| 1` | Alternating uplink counter |
  | `:safelink_down` | `0 \\| 1` | Alternating downlink counter |
  | `:log_layout` | layout \\| `nil` | Active log-block decode layout |
  | `:log_block_id` | `byte()` \\| `nil` | Active log block id |
  | `:battery` | `0..100` \\| `nil` | Last logged battery percent |
  | `:estimator_ready` | `boolean()` \\| `nil` | Last logged `sys.canfly` |
  """
  @type t :: %__MODULE__{
          usb: term(),
          backend: module(),
          uri: LinkURI.t(),
          safelink_enabled: boolean(),
          safelink_up: 0 | 1,
          safelink_down: 0 | 1,
          log_layout: [Logging.layout_entry()] | nil,
          log_block_id: byte() | nil,
          battery: 0..100 | nil,
          estimator_ready: boolean() | nil
        }

  defstruct [
    :usb,
    :backend,
    :uri,
    safelink_enabled: false,
    safelink_up: 0,
    safelink_down: 0,
    log_layout: nil,
    log_block_id: nil,
    battery: nil,
    estimator_ready: nil
  ]

  @doc """
  Opens a Crazyradio USB device, configures RF, and optionally enables SafeLink.
  """
  @impl true
  def open(opts) do
    backend = Keyword.get(opts, :usb_backend, Unavailable)

    with {:ok, uri} <- parse_uri(opts),
         {:ok, devices} <- backend.discover(vid: @vid, pid: @pid),
         {:ok, info} <- pick_device(devices, uri.radio_index),
         {:ok, usb} <- backend.open(info, opts) do
      finish_open(backend, usb, uri)
    end
  end

  defp finish_open(backend, usb, uri) do
    case configure(backend, usb, uri) do
      :ok ->
        state = %__MODULE__{usb: usb, backend: backend, uri: uri}
        enable_or_close(state)

      {:error, _} = err ->
        _ = backend.close(usb)
        err
    end
  end

  defp enable_or_close(%__MODULE__{backend: backend, usb: usb} = state) do
    case maybe_enable_safelink(state) do
      {:ok, state} ->
        {:ok, state}

      {:error, reason} ->
        _ = backend.close(usb)
        {:error, reason}
    end
  end

  @doc """
  Encodes a CRTP packet, optionally SafeLink-stamps it, and exchanges an ACK.

  On ACK, advances SafeLink counters and ingests logging data payloads into
  the transport telemetry cache.
  """
  @impl true
  def send(%__MODULE__{} = state, packet) do
    with {:ok, raw} <- CRTP.encode(packet),
         {:ok, framed} <- maybe_stamp(state, raw),
         :ok <- state.backend.bulk_write(state.usb, 0x01, framed, state.uri.timeout_ms),
         {:ok, ack_bin} <- state.backend.bulk_read(state.usb, 0x81, 64, state.uri.timeout_ms) do
      parse_ack(state, ack_bin)
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  @doc """
  Closes the USB device via the configured backend.
  """
  @impl true
  def close(%__MODULE__{backend: backend, usb: usb}) do
    case backend.close(usb) do
      :ok -> :ok
      {:error, _} -> :ok
    end
  end

  @doc """
  Returns cached battery / estimator values from CRTP logging.

  Fields stay `nil` until `configure_logging/3` succeeds and at least one
  log-data packet has been received on an ACK.
  """
  @impl true
  def telemetry(%__MODULE__{} = state) do
    state = maybe_poll_for_log(state)

    {:ok,
     %{
       battery: state.battery,
       estimator_ready: state.estimator_ready,
       firmware: nil,
       serial_number: nil,
       link_quality: nil
     }, state}
  end

  @doc false
  @spec configure_logging(t(), [Logging.layout_entry()], byte()) :: t()
  def configure_logging(%__MODULE__{} = state, layout, block_id)
      when is_list(layout) and is_integer(block_id) do
    %{state | log_layout: layout, log_block_id: block_id}
  end

  @doc false
  @spec ingest_ack_payload(t(), binary()) :: t()
  def ingest_ack_payload(%__MODULE__{} = state, payload) when is_binary(payload) do
    case downlink_packet(payload) do
      {:ok, %{port: port, channel: channel, payload: log_payload}} ->
        if port == Ports.port(:logging) and channel == Logging.data_channel() do
          ingest_log_data(state, log_payload)
        else
          state
        end

      _ ->
        state
    end
  end

  defp maybe_enable_safelink(%__MODULE__{uri: %{safelink: true}} = state) do
    enable_safelink(state, @safelink_enable_attempts)
  end

  defp maybe_enable_safelink(state), do: {:ok, state}

  defp enable_safelink(_state, 0), do: {:error, :safelink_enable_failed}

  defp enable_safelink(%__MODULE__{} = state, attempts_left) do
    packet = SafeLink.enable_packet()

    with :ok <- state.backend.bulk_write(state.usb, 0x01, packet, state.uri.timeout_ms),
         {:ok, ack_bin} <- state.backend.bulk_read(state.usb, 0x81, 64, state.uri.timeout_ms),
         {:ok, payload} <- ack_payload(ack_bin),
         true <- SafeLink.enabled_echo?(payload) do
      {:ok, %{state | safelink_enabled: true, safelink_up: 0, safelink_down: 0}}
    else
      false -> enable_safelink(state, attempts_left - 1)
      {:error, :no_ack} -> enable_safelink(state, attempts_left - 1)
      {:error, :invalid_ack} -> enable_safelink(state, attempts_left - 1)
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_stamp(%__MODULE__{safelink_enabled: true} = state, raw) do
    SafeLink.stamp_frame(raw, state.safelink_up, state.safelink_down)
  end

  defp maybe_stamp(_state, raw), do: {:ok, raw}

  defp parse_uri(opts) do
    cond do
      is_map(opts[:link_uri]) -> {:ok, opts[:link_uri]}
      is_binary(opts[:uri]) -> LinkURI.parse(opts[:uri])
      true -> {:error, :missing_uri}
    end
  end

  defp pick_device([], _), do: {:error, :crazyradio_not_found}

  defp pick_device(devices, index) when is_integer(index) do
    case Enum.at(devices, index) do
      nil -> {:error, :crazyradio_index_out_of_range}
      info -> {:ok, info}
    end
  end

  defp configure(backend, usb, uri) do
    with :ok <-
           backend.control_write(usb, @set_radio_channel, uri.channel, 0, <<>>, uri.timeout_ms),
         :ok <- backend.control_write(usb, @set_radio_address, 0, 0, uri.address, uri.timeout_ms),
         :ok <-
           backend.control_write(
             usb,
             @set_data_rate,
             datarate_value(uri.datarate),
             0,
             <<>>,
             uri.timeout_ms
           ),
         :ok <- backend.control_write(usb, @set_radio_power, 3, 0, <<>>, uri.timeout_ms) do
      backend.control_write(usb, @set_radio_arc, 3, 0, <<>>, uri.timeout_ms)
    end
  end

  defp datarate_value(:rate_250k), do: 0
  defp datarate_value(:rate_1m), do: 1
  defp datarate_value(:rate_2m), do: 2
  defp datarate_value(_), do: 2

  defp parse_ack(state, ack_bin) do
    case ack_payload(ack_bin) do
      {:ok, payload} ->
        state =
          state
          |> maybe_advance_safelink(payload)
          |> ingest_ack_payload(payload)

        retries = ack_retries(ack_bin)
        {:ok, %{acked: true, retries: retries, payload: payload}, state}

      {:error, :no_ack} ->
        {:error, :no_ack, state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp ack_payload(<<status, payload::binary>>) do
    if band(status, 0x01) == 1 do
      {:ok, payload}
    else
      {:error, :no_ack}
    end
  end

  defp ack_payload(_), do: {:error, :invalid_ack}

  defp ack_retries(<<status, _::binary>>), do: bsr(status, 4)
  defp ack_retries(_), do: 0

  defp maybe_advance_safelink(%__MODULE__{safelink_enabled: true} = state, payload) do
    header =
      case payload do
        <<h, _::binary>> -> h
        _ -> nil
      end

    {up, down} = SafeLink.advance(state.safelink_up, state.safelink_down, header)
    %{state | safelink_up: up, safelink_down: down}
  end

  defp maybe_advance_safelink(state, _), do: state

  defp maybe_poll_for_log(%__MODULE__{log_layout: layout} = state) when is_list(layout) do
    if is_nil(state.battery) or is_nil(state.estimator_ready) do
      case send(state, CRTP.null_packet()) do
        {:ok, _ack, new_state} -> new_state
        {:error, _, new_state} -> new_state
      end
    else
      state
    end
  end

  defp maybe_poll_for_log(state), do: state

  defp ingest_log_data(%__MODULE__{log_layout: nil} = state, _), do: state

  defp ingest_log_data(%__MODULE__{log_layout: layout} = state, payload) do
    case Logging.parse_data(payload, layout) do
      {:ok, values} ->
        state
        |> put_if_key(values, :battery)
        |> put_if_key(values, :estimator_ready)

      {:error, _} ->
        state
    end
  end

  defp put_if_key(state, values, key) do
    if Map.has_key?(values, key) do
      Map.put(state, key, Map.fetch!(values, key))
    else
      state
    end
  end

  defp downlink_packet(payload) do
    case CRTP.decode(payload) do
      {:ok, packet} ->
        {:ok, packet}

      {:error, _} ->
        # Mock-style bare payloads and non-CRTP ACKs are ignored for demux.
        :error
    end
  end

  defp band(a, b), do: Bitwise.band(a, b)
  defp bsr(a, b), do: Bitwise.bsr(a, b)
end
