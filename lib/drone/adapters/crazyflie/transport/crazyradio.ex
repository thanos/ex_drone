defmodule Drone.Adapters.Crazyflie.Transport.Crazyradio do
  @moduledoc """
  Crazyradio PA / Crazyradio 2.0 transport.

  Implements documented USB vendor setup and bulk EP1 send/ACK receive.
  Requires a `usb_backend` module implementing `Drone.Adapters.Crazyflie.USB`.

  Without a backend the default `USB.Unavailable` module returns
  `{:error, :usb_backend_unavailable}`.

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

  alias Drone.Adapters.Crazyflie.CRTP
  alias Drone.Adapters.Crazyflie.LinkURI
  alias Drone.Adapters.Crazyflie.USB.Unavailable

  @vid 0x1915
  @pid 0x7777

  @set_radio_channel 0x01
  @set_radio_address 0x02
  @set_data_rate 0x03
  @set_radio_power 0x04
  @set_radio_arc 0x06

  @typedoc """
  Open Crazyradio transport state.

  | Field | Type | Meaning |
  | --- | --- | --- |
  | `:usb` | `Drone.Adapters.Crazyflie.USB.device()` | Opaque USB handle |
  | `:backend` | `module()` | Module implementing `Drone.Adapters.Crazyflie.USB` |
  | `:uri` | `Drone.Adapters.Crazyflie.LinkURI.t()` | Parsed radio URI |
  | `:safelink_up` | `0 \\| 1` | Alternating SafeLink uplink counter |
  | `:safelink_down` | `0 \\| 1` | Reserved downlink counter field |

  ## Example

      %Drone.Adapters.Crazyflie.Transport.Crazyradio{
        usb: device_handle,
        backend: MyApp.CrazyradioUSB,
        uri: %{scheme: :radio, channel: 80, datarate: :rate_2m, safelink: true},
        safelink_up: 0,
        safelink_down: 0
      }
  """
  @type t :: %__MODULE__{
          usb: term(),
          backend: module(),
          uri: LinkURI.t(),
          safelink_up: 0 | 1,
          safelink_down: 0 | 1
        }

  defstruct [:usb, :backend, :uri, :safelink_up, :safelink_down]

  @doc """
  Opens a Crazyradio USB device and configures channel / address / rate.

  ## Parameters

    * `opts` (`keyword()`) — required / common keys:
      * `:uri` (`String.t()`) or `:link_uri` (`LinkURI.t()`) — radio link
      * `:usb_backend` (`module()`) — USB behaviour (default `USB.Unavailable`)

  ## Returns

    * `{:ok, t()}` — configured transport
    * `{:error, term()}` — `:missing_uri`, `:crazyradio_not_found`,
      `:crazyradio_index_out_of_range`, `:usb_backend_unavailable`, …

  ## Examples

      {:error, :usb_backend_unavailable} =
        Drone.Adapters.Crazyflie.Transport.Crazyradio.open(uri: "radio://0/80/2M")
  """
  @impl true
  def open(opts) do
    backend = Keyword.get(opts, :usb_backend, Unavailable)

    with {:ok, uri} <- parse_uri(opts),
         {:ok, devices} <- backend.discover(vid: @vid, pid: @pid),
         {:ok, info} <- pick_device(devices, uri.radio_index),
         {:ok, usb} <- backend.open(info, opts),
         :ok <- configure(backend, usb, uri) do
      {:ok,
       %__MODULE__{
         usb: usb,
         backend: backend,
         uri: uri,
         safelink_up: 0,
         safelink_down: 0
       }}
    end
  end

  @doc """
  Encodes a CRTP packet, optionally prefixes SafeLink, and exchanges an ACK.

  ## Parameters

    * `state` (`t:t/0`) — open radio transport
    * `packet` (`CRTP.packet()`) — packet to send

  ## Returns

    * `{:ok, %{acked: true, retries: integer(), payload: binary()}, t()}`
    * `{:error, reason, t()}` — `:no_ack`, `:invalid_ack`, USB errors, …

  ## Examples

      {:ok, %{acked: true}, state} =
        Drone.Adapters.Crazyflie.Transport.Crazyradio.send(state, packet)
  """
  @impl true
  def send(%__MODULE__{} = state, packet) do
    with {:ok, raw} <- CRTP.encode(packet),
         framed <- maybe_safelink(state, raw),
         :ok <- state.backend.bulk_write(state.usb, 0x01, framed, state.uri.timeout_ms),
         {:ok, ack_bin} <- state.backend.bulk_read(state.usb, 0x81, 64, state.uri.timeout_ms) do
      parse_ack(state, ack_bin)
    else
      {:error, reason} -> {:error, reason, state}
      {:error, _reason, _} = err -> err
    end
  end

  @doc """
  Closes the USB device via the configured backend.

  ## Parameters

    * `state` (`t:t/0`) — open radio transport

  ## Returns

  Always `:ok`.

  ## Examples

      :ok = Drone.Adapters.Crazyflie.Transport.Crazyradio.close(state)
  """
  @impl true
  def close(%__MODULE__{backend: backend, usb: usb}) do
    backend.close(usb)
    :ok
  end

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

  # SafeLink prepends a 1-byte counter header when enabled (documented radio link).
  defp maybe_safelink(%{uri: %{safelink: true}, safelink_up: up}, raw) do
    <<Bitwise.band(up, 0x01), raw::binary>>
  end

  defp maybe_safelink(_state, raw), do: raw

  defp parse_ack(state, <<status, payload::binary>>) do
    acked = Bitwise.band(status, 0x01) == 1
    retries = Bitwise.bsr(status, 4)

    new_state =
      if state.uri.safelink do
        %{state | safelink_up: Bitwise.band(state.safelink_up + 1, 0x01)}
      else
        state
      end

    if acked do
      {:ok, %{acked: true, retries: retries, payload: payload}, new_state}
    else
      {:error, :no_ack, new_state}
    end
  end

  defp parse_ack(state, _), do: {:error, :invalid_ack, state}
end
