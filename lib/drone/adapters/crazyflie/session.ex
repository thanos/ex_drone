defmodule Drone.Adapters.Crazyflie.Session do
  @moduledoc """
  CRTP session helpers over a transport.

  Owns connection handshake (link probe + protocol version check) and
  convenience send wrappers used by the Crazyflie adapter.

  ## Lifecycle

      {:ok, mod} = Drone.Adapters.Crazyflie.Transport.resolve(uri: "mock://ready")
      {:ok, session} = Drone.Adapters.Crazyflie.Session.connect(mod, uri: "mock://ready")
      {:ok, _ack, session} = Drone.Adapters.Crazyflie.Session.poll(session)
      :ok = Drone.Adapters.Crazyflie.Session.close(session)

  Handshake failures close the transport and return `{:error, reason}`
  (for example `{:unsupported_protocol, version}` or `:link_lost`).
  """

  alias Drone.Adapters.Crazyflie.CRTP
  alias Drone.Adapters.Crazyflie.Platform

  @typedoc """
  Open CRTP session bound to a transport module and its opaque state.

  | Field | Type | Meaning |
  | --- | --- | --- |
  | `:transport_module` | `module()` | Module implementing `Drone.Adapters.Crazyflie.Transport` |
  | `:transport_state` | `term()` | Opaque state returned by `open` / `send` |
  | `:protocol_version` | `non_neg_integer()` \\| `nil` | Negotiated CRTP protocol version after handshake |

  ## Example

      %{
        transport_module: Drone.Adapters.Crazyflie.Transport.Mock,
        transport_state: %Drone.Adapters.Crazyflie.Transport.Mock{profile: :ready},
        protocol_version: 8
      }
  """
  @type t :: %{
          transport_module: module(),
          transport_state: term(),
          protocol_version: non_neg_integer() | nil
        }

  @doc """
  Opens a transport and verifies protocol compatibility.

  Sequence:

  1. `transport_module.open(opts)`
  2. Send `Platform.link_probe/0`
  3. Send `Platform.get_protocol_version/0` and parse the reply
  4. `Platform.check_compatibility/1`

  On any handshake error the transport is closed.

  ## Parameters

    * `transport_module` (`module()`) — for example
      `Drone.Adapters.Crazyflie.Transport.Mock`
    * `opts` (`keyword()`) — forwarded to `open/1` (`:uri`, `:usb_backend`, …)

  ## Returns

    * `{:ok, t()}` — session with `:protocol_version` set
    * `{:error, term()}` — open or handshake failure

  ## Examples

      {:ok, session} =
        Drone.Adapters.Crazyflie.Session.connect(
          Drone.Adapters.Crazyflie.Transport.Mock,
          uri: "mock://ready"
        )

      is_integer(session.protocol_version)
  """
  @spec connect(module(), keyword()) :: {:ok, t()} | {:error, term()}
  def connect(transport_module, opts) do
    case transport_module.open(opts) do
      {:ok, transport_state} ->
        session = %{
          transport_module: transport_module,
          transport_state: transport_state,
          protocol_version: nil
        }

        handshake(session)

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Sends a CRTP packet through the session transport.

  ## Parameters

    * `session` (`t:t/0`) — open session
    * `packet` (`Drone.Adapters.Crazyflie.CRTP.packet()`) — packet to send

  ## Returns

    * `{:ok, ack_map, t()}` — ACK map has `:acked`, `:retries`, `:payload`;
      session carries updated `:transport_state`
    * `{:error, term(), t()}` — send failed; session may still update

  ## Examples

      packet = Drone.Adapters.Crazyflie.CRTP.null_packet()
      {:ok, %{acked: true}, session} =
        Drone.Adapters.Crazyflie.Session.send_packet(session, packet)
  """
  @spec send_packet(t(), CRTP.packet()) ::
          {:ok, map(), t()} | {:error, term(), t()}
  def send_packet(%{transport_module: mod, transport_state: ts} = session, packet) do
    case mod.send(ts, packet) do
      {:ok, ack, new_ts} ->
        {:ok, ack, %{session | transport_state: new_ts}}

      {:error, reason, new_ts} ->
        {:error, reason, %{session | transport_state: new_ts}}
    end
  end

  @doc """
  Polls the link with a null packet (port 15 / channel 3).

  Useful to drain downlink or keep the radio link warm when idle.

  ## Parameters

    * `session` (`t:t/0`) — open session

  ## Returns

  Same as `send_packet/2`.

  ## Examples

      {:ok, _ack, session} = Drone.Adapters.Crazyflie.Session.poll(session)
  """
  @spec poll(t()) :: {:ok, map(), t()} | {:error, term(), t()}
  def poll(session), do: send_packet(session, CRTP.null_packet())

  @doc """
  Closes the underlying transport.

  ## Parameters

    * `session` (`t:t/0`) — session to tear down

  ## Returns

  Always `:ok`.

  ## Examples

      :ok = Drone.Adapters.Crazyflie.Session.close(session)
  """
  @spec close(t()) :: :ok
  def close(%{transport_module: mod, transport_state: ts}) do
    mod.close(ts)
    :ok
  end

  defp handshake(session) do
    with {:ok, _ack, session} <- send_packet(session, Platform.link_probe()),
         {:ok, ack, session} <- send_packet(session, Platform.get_protocol_version()),
         {:ok, version} <- Platform.parse_protocol_version(ack.payload),
         :ok <- Platform.check_compatibility(version) do
      {:ok, %{session | protocol_version: version}}
    else
      {:error, reason, session} ->
        close(session)
        {:error, reason}

      {:error, reason} ->
        close(session)
        {:error, reason}
    end
  end
end
