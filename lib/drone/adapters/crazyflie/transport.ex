defmodule Drone.Adapters.Crazyflie.Transport do
  @moduledoc """
  Behaviour for Crazyflie link transports (Crazyradio USB or mock).

  The adapter never calls USB APIs directly. Transports own exclusive
  device access and must release resources in `c:close/1`.

  Built-in implementations:

  * `Drone.Adapters.Crazyflie.Transport.Mock` — in-process, for CI (`mock://`)
  * `Drone.Adapters.Crazyflie.Transport.Crazyradio` — USB radio (`radio://`)

  ## Implementing a custom transport

      defmodule MyApp.LoopbackTransport do
        @behaviour Drone.Adapters.Crazyflie.Transport

        @impl true
        def open(_opts), do: {:ok, %{sent: []}}

        @impl true
        def send(state, packet) do
          state = %{state | sent: [packet | state.sent]}
          {:ok, %{acked: true, retries: 0, payload: <<>>}, state}
        end

        @impl true
        def close(_state), do: :ok
      end

      {:ok, drone} =
        Drone.connect(:crazyflie, transport: MyApp.LoopbackTransport)

  Prefer `resolve/1` when selecting among URI schemes unless you inject
  `:transport` explicitly.
  """

  alias Drone.Adapters.Crazyflie.CRTP
  alias Drone.Adapters.Crazyflie.LinkURI
  alias Drone.Adapters.Crazyflie.Transport.Crazyradio
  alias Drone.Adapters.Crazyflie.Transport.Mock

  @typedoc """
  Opaque transport state held by a CRTP session.

  Each transport defines its own representation (struct, map, or reference).
  Sessions pass it back into `c:send/2` and `c:close/1` without inspecting it.

  ## Examples

      %Drone.Adapters.Crazyflie.Transport.Mock{profile: :ready, battery_percent: 95}

      %Drone.Adapters.Crazyflie.Transport.Crazyradio{
        usb: device_handle,
        backend: MyApp.CrazyradioUSB,
        uri: %{scheme: :radio, channel: 80, ...}
      }
  """
  @type state :: term()

  @typedoc """
  Result of sending one CRTP packet over the link.

  On success the middle map describes the radio ACK:

  | Key | Type | Meaning |
  | --- | --- | --- |
  | `:acked` | `boolean()` | Radio reported an ACK from the Crazyflie |
  | `:retries` | `non_neg_integer()` | Retransmit count encoded in the ACK status byte |
  | `:payload` | `binary()` | Downlink bytes after the status byte (may be empty) |

  ## Examples

      {:ok, %{acked: true, retries: 0, payload: <<0, 8>>}, new_state}

      {:error, :no_ack, new_state}
      {:error, :link_lost, new_state}
      {:error, :usb_backend_unavailable, new_state}
  """
  @type send_result ::
          {:ok, %{acked: boolean(), retries: non_neg_integer(), payload: binary()}, state()}
          | {:error, term(), state()}

  @doc """
  Opens the transport and returns initial state.

  Called once from `Drone.Adapters.Crazyflie.Session.connect/2`.

  ## Parameters

    * `opts` (`keyword()`) — options from `Drone.connect/2`, commonly:
      * `:uri` (`String.t()`) — `"mock://ready"` or `"radio://0/80/2M/…"`
      * `:link_uri` (`Drone.Adapters.Crazyflie.LinkURI.t()`) — pre-parsed URI
      * `:usb_backend` (`module()`) — `Drone.Adapters.Crazyflie.USB` impl (radio)
      * `:mock_profile` (`atom()`) — mock profile override

  ## Returns

    * `{:ok, state()}` — ready to send
    * `{:error, term()}` — open/configure failed

  ## Example implementation

      @impl Drone.Adapters.Crazyflie.Transport
      def open(opts) do
        uri = Keyword.fetch!(opts, :uri)
        {:ok, %{uri: uri, buffer: []}}
      end
  """
  @callback open(opts :: keyword()) :: {:ok, state()} | {:error, term()}

  @doc """
  Sends one CRTP packet and returns the ACK summary plus updated state.

  ## Parameters

    * `state` (`t:state/0`) — current transport state
    * `packet` (`Drone.Adapters.Crazyflie.CRTP.packet()`) — port/channel/payload

  ## Returns

    * `{:ok, ack_map, new_state}` — see `t:send_result/0`
    * `{:error, reason, new_state}` — link or encode failure; state may update

  ## Example implementation

      @impl Drone.Adapters.Crazyflie.Transport
      def send(state, packet) do
        {:ok, bytes} = Drone.Adapters.Crazyflie.CRTP.encode(packet)
        :ok = Radio.write(state.device, bytes)
        {:ok, ack_bin} = Radio.read_ack(state.device)
        {:ok, %{acked: true, retries: 0, payload: ack_bin}, state}
      end
  """
  @callback send(state(), CRTP.packet()) :: send_result()

  @doc """
  Closes the transport and releases exclusive device access.

  ## Parameters

    * `state` (`t:state/0`) — final transport state

  ## Returns

  Always `:ok`.

  ## Example implementation

      @impl Drone.Adapters.Crazyflie.Transport
      def close(%{device: device}) do
        Radio.close(device)
        :ok
      end
  """
  @callback close(state()) :: :ok

  @doc """
  Optional snapshot of transport-reported vehicle telemetry.

  Used by the Crazyflie adapter instead of inspecting transport structs.
  Keys may include `:battery`, `:estimator_ready`, `:flying`, `:armed`,
  `:firmware`, `:serial_number`, and `:link_quality`. Missing keys leave
  adapter fields unchanged. Use `nil` explicitly when a value is unknown
  (for example radio transports without a logging subscription).

  ## Example implementation

      @impl Drone.Adapters.Crazyflie.Transport
      def telemetry(state) do
        {:ok,
         %{
           battery: state.battery_percent,
           estimator_ready: state.estimator_ready,
           flying: state.flying,
           armed: state.armed,
           firmware: "mock",
           serial_number: "mock-cf"
         }, state}
      end
  """
  @callback telemetry(state()) ::
              {:ok, map(), state()}
              | {:error, term(), state()}

  @optional_callbacks [telemetry: 1]

  @doc """
  Resolves a transport module from options or a parsed link URI.

  Selection order:

  1. Explicit `:transport` module atom (when set and not a boolean)
  2. `:uri` scheme — `mock://` → `Mock`, `radio://` → `Crazyradio`
  3. Default → `Mock`

  ## Parameters

    * `opts` (`keyword()`) — typically the keyword list passed to
      `Drone.connect/2` / `Session.connect/2`

  ## Returns

    * `{:ok, module()}` — transport module implementing this behaviour
    * `{:error, term()}` — URI parse failure (unsupported scheme, bad path, …)

  ## Examples

      iex> Drone.Adapters.Crazyflie.Transport.resolve(uri: "mock://ready")
      {:ok, Drone.Adapters.Crazyflie.Transport.Mock}

      iex> Drone.Adapters.Crazyflie.Transport.resolve(uri: "radio://0/80/2M")
      {:ok, Drone.Adapters.Crazyflie.Transport.Crazyradio}

      iex> Drone.Adapters.Crazyflie.Transport.resolve(transport: MyApp.LoopbackTransport)
      {:ok, MyApp.LoopbackTransport}

      iex> Drone.Adapters.Crazyflie.Transport.resolve([])
      {:ok, Drone.Adapters.Crazyflie.Transport.Mock}
  """
  @spec resolve(keyword()) :: {:ok, module()} | {:error, term()}
  def resolve(opts) when is_list(opts) do
    cond do
      is_atom(opts[:transport]) and opts[:transport] not in [nil, true, false] ->
        {:ok, opts[:transport]}

      is_binary(opts[:uri]) ->
        case LinkURI.parse(opts[:uri]) do
          {:ok, %{scheme: :mock}} -> {:ok, Mock}
          {:ok, %{scheme: :radio}} -> {:ok, Crazyradio}
          {:error, _} = err -> err
        end

      true ->
        {:ok, Mock}
    end
  end
end
