defmodule Drone.Adapters.Crazyflie.USB do
  @moduledoc """
  Behaviour for Crazyradio USB backends.

  Real bulk USB I/O is optional. Without a backend, radio URIs return
  `{:error, :usb_backend_unavailable}` and CI uses the mock transport
  (`mock://…`). Pass a module implementing this behaviour as
  `usb_backend:` to `Drone.connect/2` when talking to physical Crazyradio
  hardware.

  ## Implementing a backend

      defmodule MyApp.CrazyradioUSB do
        @behaviour Drone.Adapters.Crazyflie.USB

        @impl true
        def discover(opts) do
          vid = Keyword.get(opts, :vid, 0x1915)
          pid = Keyword.get(opts, :pid, 0x7777)
          devices = LibUSB.list_devices(vid: vid, pid: pid)
          {:ok, Enum.map(devices, &%{handle_info: &1, index: &1.index})}
        end

        @impl true
        def open(%{handle_info: info}, _opts) do
          {:ok, device} = LibUSB.open(info)
          {:ok, device}
        end

        @impl true
        def control_write(device, request, value, index, data, timeout) do
          LibUSB.control_transfer(device, request, value, index, data, timeout)
        end

        @impl true
        def bulk_write(device, endpoint, data, timeout) do
          LibUSB.bulk_transfer_out(device, endpoint, data, timeout)
        end

        @impl true
        def bulk_read(device, endpoint, max_len, timeout) do
          LibUSB.bulk_transfer_in(device, endpoint, max_len, timeout)
        end

        @impl true
        def close(device) do
          LibUSB.close(device)
          :ok
        end
      end

      {:ok, drone} =
        Drone.connect(:crazyflie,
          uri: "radio://0/80/2M",
          usb_backend: MyApp.CrazyradioUSB
        )

  The default stub is `Drone.Adapters.Crazyflie.USB.Unavailable`.
  """

  @typedoc """
  Opaque USB device handle owned by the backend.

  Typically a reference, port, or struct from your USB library. The Crazyradio
  transport never inspects it except to pass it back into callbacks.

  ## Examples

      # NIF / libusb style
      #Reference<0.123.456.789>

      # Wrapper struct
      %MyApp.USB.Device{handle: pid(), endpoint_out: 0x01}
  """
  @type device :: term()

  @doc """
  Lists Crazyradio devices matching the given filters.

  Called by `Drone.Adapters.Crazyflie.Transport.Crazyradio.open/1` before
  opening a radio.

  ## Parameters

    * `opts` (`keyword()`) — discovery filters. Common keys:
      * `:vid` (`integer()`) — USB vendor id (Crazyradio PA defaults to `0x1915`)
      * `:pid` (`integer()`) — USB product id (defaults to `0x7777`)

  ## Returns

    * `{:ok, [map()]}` — zero or more device info maps. Each map must be
      acceptable to `c:open/2`. Typical keys: `:index`, `:path`, `:serial`.
    * `{:error, term()}` — discovery failed (permissions, missing driver, …)

  ## Example implementation

      @impl Drone.Adapters.Crazyflie.USB
      def discover(opts) do
        vid = Keyword.fetch!(opts, :vid)
        pid = Keyword.fetch!(opts, :pid)

        case LibUSB.find(vid, pid) do
          [] -> {:ok, []}
          devices -> {:ok, Enum.with_index(devices, fn d, i -> %{index: i, raw: d} end)}
        end
      end
  """
  @callback discover(opts :: keyword()) :: {:ok, [map()]} | {:error, term()}

  @doc """
  Opens a USB device described by `device_info`.

  ## Parameters

    * `device_info` (`map()`) — one entry from `c:discover/1`
    * `opts` (`keyword()`) — connect options forwarded from the transport
      (may include `:uri`, `:timeout`, backend-specific keys)

  ## Returns

    * `{:ok, device()}` — opaque handle for subsequent transfers
    * `{:error, term()}` — open failed

  ## Example implementation

      @impl Drone.Adapters.Crazyflie.USB
      def open(%{raw: raw}, _opts) do
        with {:ok, handle} <- LibUSB.open(raw),
             :ok <- LibUSB.claim_interface(handle, 0) do
          {:ok, handle}
        end
      end
  """
  @callback open(device_info :: map(), opts :: keyword()) :: {:ok, device()} | {:error, term()}

  @doc """
  Performs a USB control (vendor) write used to configure Crazyradio registers.

  Crazyradio setup uses vendor requests such as set channel (`0x01`),
  address (`0x02`), data rate (`0x03`), power (`0x04`), and ARC (`0x06`).

  ## Parameters

    * `device` (`t:device/0`) — open handle from `c:open/2`
    * `request` (`byte()`) — vendor request id (for example `0x01` for channel)
    * `value` (`integer()`) — `wValue` field (channel number, rate enum, …)
    * `index` (`integer()`) — `wIndex` field (usually `0`)
    * `data` (`binary()`) — optional payload (for example a 5-byte radio address)
    * `timeout` (`pos_integer()`) — timeout in milliseconds

  ## Returns

    * `:ok` — transfer completed
    * `{:error, term()}` — transfer failed or timed out

  ## Example implementation

      @impl Drone.Adapters.Crazyflie.USB
      def control_write(device, request, value, index, data, timeout) do
        LibUSB.control_transfer(
          device,
          %{request_type: :vendor_out, request: request, value: value, index: index},
          data,
          timeout
        )
      end
  """
  @callback control_write(
              device(),
              byte(),
              integer(),
              integer(),
              binary(),
              timeout :: pos_integer()
            ) ::
              :ok | {:error, term()}

  @doc """
  Writes a bulk OUT packet (typically Crazyradio endpoint `0x01`).

  ## Parameters

    * `device` (`t:device/0`) — open handle
    * `endpoint` (`integer()`) — bulk OUT endpoint address (`0x01` for Crazyradio)
    * `data` (`binary()`) — framed CRTP bytes (SafeLink may rewrite header bits)
    * `timeout` (`pos_integer()`) — timeout in milliseconds

  ## Returns

    * `:ok` — write succeeded
    * `{:error, term()}` — write failed

  ## Example implementation

      @impl Drone.Adapters.Crazyflie.USB
      def bulk_write(device, endpoint, data, timeout) do
        LibUSB.bulk_write(device, endpoint, data, timeout)
      end
  """
  @callback bulk_write(device(), endpoint :: integer(), binary(), timeout :: pos_integer()) ::
              :ok | {:error, term()}

  @doc """
  Reads a bulk IN packet (typically Crazyradio ACK endpoint `0x81`).

  ## Parameters

    * `device` (`t:device/0`) — open handle
    * `endpoint` (`integer()`) — bulk IN endpoint address (`0x81` for Crazyradio)
    * `max_len` (`pos_integer()`) — maximum bytes to read (often `64`)
    * `timeout` (`pos_integer()`) — timeout in milliseconds

  ## Returns

    * `{:ok, binary()}` — ACK status byte plus optional downlink payload
    * `{:error, term()}` — read failed or timed out

  ## Example implementation

      @impl Drone.Adapters.Crazyflie.USB
      def bulk_read(device, endpoint, max_len, timeout) do
        LibUSB.bulk_read(device, endpoint, max_len, timeout)
      end
  """
  @callback bulk_read(
              device(),
              endpoint :: integer(),
              max_len :: pos_integer(),
              timeout :: pos_integer()
            ) ::
              {:ok, binary()} | {:error, term()}

  @doc """
  Releases the USB device and any claimed interfaces.

  ## Parameters

    * `device` (`t:device/0`) — open handle from `c:open/2`

  ## Returns

    * `:ok` — released
    * `{:error, term()}` — close failed (stuck handle, driver error, …)

  ## Example implementation

      @impl Drone.Adapters.Crazyflie.USB
      def close(device) do
        with :ok <- LibUSB.release_interface(device, 0) do
          LibUSB.close(device)
        end
      end
  """
  @callback close(device()) :: :ok | {:error, term()}
end
