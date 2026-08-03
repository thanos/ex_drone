defmodule Drone.Adapters.Crazyflie.SessionTransportMockTest do
  use ExUnit.Case, async: false

  import Mox

  alias Drone.Adapters.Crazyflie.CRTP
  alias Drone.Adapters.Crazyflie.Platform
  alias Drone.Adapters.Crazyflie.Session
  alias Drone.Adapters.Crazyflie.Transport.Mock

  setup :verify_on_exit!

  test "connect handshake and logging succeed on mock transport" do
    assert {:ok, session} = Session.connect(Mock, uri: "mock://ready")
    assert session.protocol_version == 8
    assert [_, _] = session.log_layout

    assert {:ok, _ack, session} = Session.poll(session)
    assert :ok = Session.close(session)
  end

  test "connect rejects unsupported protocol and closes transport" do
    expect(Drone.CrazyflieTransportMock, :open, fn _ -> {:ok, :transport} end)

    expect(Drone.CrazyflieTransportMock, :send, 2, fn :transport, packet ->
      payload =
        if packet == Platform.get_protocol_version() do
          <<0, 99>>
        else
          <<>>
        end

      {:ok, %{acked: true, retries: 0, payload: payload}, :transport}
    end)

    expect(Drone.CrazyflieTransportMock, :close, fn :transport -> :ok end)

    assert {:error, {:unsupported_protocol, 99}} =
             Session.connect(Drone.CrazyflieTransportMock, [])
  end

  test "connect propagates open errors" do
    expect(Drone.CrazyflieTransportMock, :open, fn _ -> {:error, :boom} end)
    assert {:error, :boom} = Session.connect(Drone.CrazyflieTransportMock, [])
  end

  test "send_packet propagates transport errors" do
    assert {:ok, session} = Session.connect(Mock, uri: "mock://ready")
    ts = Mock.force_unplug(session.transport_state)
    session = %{session | transport_state: ts}

    assert {:error, :link_lost, _} = Session.send_packet(session, CRTP.null_packet())
  end
end
