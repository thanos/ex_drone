defmodule Drone.Adapters.Crazyflie.Session do
  @moduledoc """
  CRTP session helpers over a transport.

  Owns connection handshake (link probe + protocol version), optional CRTP
  logging subscription for battery / estimator readiness, and convenience
  send wrappers used by the Crazyflie adapter.

  ## Lifecycle

      {:ok, mod} = Drone.Adapters.Crazyflie.Transport.resolve(uri: "mock://ready")
      {:ok, session} = Drone.Adapters.Crazyflie.Session.connect(mod, uri: "mock://ready")
      {:ok, _ack, session} =
        Drone.Adapters.Crazyflie.Session.send_packet(
          session,
          Drone.Adapters.Crazyflie.CRTP.null_packet()
        )
      :ok = Drone.Adapters.Crazyflie.Session.close(session)

  Handshake failures close the transport and return `{:error, reason}`
  (for example `{:unsupported_protocol, version}` or `:link_lost`).

  Logging setup failures close the transport with
  `{:error, {:logging_setup_failed, reason}}`.

  `poll/1` is a thin null-packet helper kept for tests; production code should
  use `send_packet/2` with an explicit CRTP packet.
  """

  alias Drone.Adapters.Crazyflie.CRTP
  alias Drone.Adapters.Crazyflie.CRTP.Ports
  alias Drone.Adapters.Crazyflie.Logging
  alias Drone.Adapters.Crazyflie.Platform

  @typedoc """
  Open CRTP session bound to a transport module and its opaque state.

  | Field | Type | Meaning |
  | --- | --- | --- |
  | `:transport_module` | `module()` | Module implementing `Drone.Adapters.Crazyflie.Transport` |
  | `:transport_state` | `term()` | Opaque state returned by `open` / `send` |
  | `:protocol_version` | `non_neg_integer()` \\| `nil` | Negotiated CRTP protocol version after handshake |
  | `:log_layout` | `[map()]` \\| `nil` | Active logging decode layout when subscribed |

  ## Example

      %{
        transport_module: Drone.Adapters.Crazyflie.Transport.Mock,
        transport_state: %Drone.Adapters.Crazyflie.Transport.Mock{profile: :ready},
        protocol_version: 8,
        log_layout: nil
      }
  """
  @type t :: %{
          transport_module: module(),
          transport_state: term(),
          protocol_version: non_neg_integer() | nil,
          log_layout: [Logging.layout_entry()] | nil
        }

  @doc """
  Opens a transport, verifies protocol compatibility, and subscribes to logging.

  Sequence:

  1. `transport_module.open(opts)` (SafeLink enable happens here when requested)
  2. Send `Platform.link_probe/0`
  3. Send `Platform.get_protocol_version/0` and parse the reply
  4. `Platform.check_compatibility/1`
  5. Reset logging, download TOC, create/start a battery + canfly block
  """
  @spec connect(module(), keyword()) :: {:ok, t()} | {:error, term()}
  def connect(transport_module, opts) do
    case transport_module.open(opts) do
      {:ok, transport_state} ->
        session = %{
          transport_module: transport_module,
          transport_state: transport_state,
          protocol_version: nil,
          log_layout: nil
        }

        case handshake(session) do
          {:ok, session} -> setup_logging(session)
          {:error, _} = err -> err
        end

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Sends a CRTP packet through the session transport.
  """
  @spec send_packet(t(), CRTP.packet()) ::
          {:ok, map(), t()} | {:error, term(), t()}
  def send_packet(%{transport_module: mod, transport_state: ts} = session, packet) do
    case mod.send(ts, packet) do
      {:ok, ack, new_ts} ->
        session = %{session | transport_state: new_ts}
        session = maybe_ingest(session, ack.payload)
        {:ok, ack, session}

      {:error, reason, new_ts} ->
        {:error, reason, %{session | transport_state: new_ts}}
    end
  end

  @doc false
  @spec poll(t()) :: {:ok, map(), t()} | {:error, term(), t()}
  def poll(session), do: send_packet(session, CRTP.null_packet())

  @doc """
  Closes the underlying transport.
  """
  @spec close(t()) :: :ok
  def close(%{transport_module: mod, transport_state: ts}) do
    mod.close(ts)
    :ok
  end

  defp handshake(session) do
    with {:ok, _ack, session} <- send_packet(session, Platform.link_probe()),
         {:ok, ack, session} <- send_packet(session, Platform.get_protocol_version()),
         {:ok, version} <-
           Platform.parse_protocol_version(response_payload(ack, Ports.port(:platform))),
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

  defp setup_logging(session) do
    block_id = Logging.default_block_id()
    period = Logging.default_period_ms()
    log_port = Ports.port(:logging)

    with {:ok, _ack, session} <- send_packet(session, Logging.reset()),
         {:ok, ack, session} <- send_packet(session, Logging.get_toc_info()),
         {:ok, info} <- Logging.parse_toc_info(response_payload(ack, log_port)),
         {:ok, items, session} <- download_toc(session, info.count),
         {:ok, layout} <- Logging.resolve_layout(items),
         {:ok, ack, session} <-
           send_packet(session, Logging.create_block_v2(block_id, Logging.layout_ops(layout))),
         {:ok, create} <- Logging.parse_control_result(response_payload(ack, log_port)),
         true <- Logging.control_ok?(create),
         {:ok, ack, session} <-
           send_packet(session, Logging.start_block_v2(block_id, period)),
         {:ok, start} <- Logging.parse_control_result(response_payload(ack, log_port)),
         true <- Logging.control_ok?(start) do
      session =
        session
        |> Map.put(:log_layout, layout)
        |> configure_transport_logging(layout, block_id)
        |> warm_log_cache()

      {:ok, session}
    else
      false ->
        fail_logging(session, :log_control_rejected)

      {:error, reason, session} ->
        fail_logging(session, reason)

      {:error, reason} ->
        fail_logging(session, reason)
    end
  end

  defp download_toc(session, count) when is_integer(count) and count >= 0 do
    log_port = Ports.port(:logging)

    Enum.reduce_while(0..(count - 1)//1, {:ok, [], session}, fn id, {:ok, acc, session} ->
      fetch_toc_item(session, id, log_port, acc)
    end)
    |> case do
      {:ok, items, session} -> {:ok, Enum.reverse(items), session}
      other -> other
    end
  end

  defp fetch_toc_item(session, id, log_port, acc) do
    with {:ok, ack, session} <- send_packet(session, Logging.get_toc_item(id)),
         {:ok, item} <- Logging.parse_toc_item(response_payload(ack, log_port)) do
      {:cont, {:ok, [item | acc], session}}
    else
      {:error, reason, session} -> {:halt, {:error, reason, session}}
      {:error, reason} -> {:halt, {:error, reason, session}}
    end
  end

  defp configure_transport_logging(
         %{transport_module: mod, transport_state: ts} = session,
         layout,
         block_id
       ) do
    _ = Code.ensure_loaded(mod)

    if function_exported?(mod, :configure_logging, 3) do
      %{session | transport_state: mod.configure_logging(ts, layout, block_id)}
    else
      session
    end
  end

  defp warm_log_cache(session) do
    Enum.reduce(1..5, session, fn _, session ->
      case poll(session) do
        {:ok, _ack, session} -> session
        {:error, _, session} -> session
      end
    end)
  end

  defp maybe_ingest(%{transport_module: mod, transport_state: ts} = session, payload) do
    _ = Code.ensure_loaded(mod)

    if function_exported?(mod, :ingest_ack_payload, 2) do
      %{session | transport_state: mod.ingest_ack_payload(ts, payload)}
    else
      session
    end
  end

  # Unwrap CRTP-framed ACK payloads from real radios. Mock transports often
  # return bare command payloads; only strip a header when the decoded port
  # matches the expected subsystem.
  defp response_payload(%{payload: payload}, expected_port) when is_binary(payload) do
    case CRTP.decode(payload) do
      {:ok, %{port: ^expected_port, payload: inner}} -> inner
      _ -> payload
    end
  end

  defp fail_logging(session, reason) do
    close(session)
    {:error, {:logging_setup_failed, reason}}
  end
end
