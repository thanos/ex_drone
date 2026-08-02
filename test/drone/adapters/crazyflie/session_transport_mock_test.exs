defmodule Drone.Adapters.Crazyflie.SessionTransportMockTest do
  use ExUnit.Case, async: false

  import Mox

  alias Drone.Adapters.Crazyflie.CRTP
  alias Drone.Adapters.Crazyflie.Platform
  alias Drone.Adapters.Crazyflie.Session

  setup :verify_on_exit!

  test "connect handshake succeeds through transport mock" do
    expect(Drone.CrazyflieTransportMock, :open, fn _opts -> {:ok, :transport} end)

    expect(Drone.CrazyflieTransportMock, :send, 2, fn :transport, packet ->
      payload =
        if packet.port == Platform.get_protocol_version().port and
             packet.channel == Platform.get_protocol_version().channel do
          <<0, 8>>
        else
          "Bitcraze Crazyflie"
        end

      {:ok, %{acked: true, retries: 0, payload: payload}, :transport}
    end)

    assert {:ok, session} = Session.connect(Drone.CrazyflieTransportMock, [])
    assert session.protocol_version == 8

    expect(Drone.CrazyflieTransportMock, :send, fn :transport, packet ->
      assert CRTP.null?(packet)
      {:ok, %{acked: true, retries: 0, payload: <<>>}, :transport}
    end)

    assert {:ok, _ack, session} = Session.poll(session)

    expect(Drone.CrazyflieTransportMock, :close, fn :transport -> :ok end)
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
    expect(Drone.CrazyflieTransportMock, :open, fn _ -> {:ok, :transport} end)

    expect(Drone.CrazyflieTransportMock, :send, 2, fn :transport, _packet ->
      {:ok, %{acked: true, retries: 0, payload: <<0, 8>>}, :transport}
    end)

    {:ok, session} = Session.connect(Drone.CrazyflieTransportMock, [])

    expect(Drone.CrazyflieTransportMock, :send, fn :transport, _ ->
      {:error, :link_lost, :transport}
    end)

    assert {:error, :link_lost, _} = Session.send_packet(session, CRTP.null_packet())
  end
end
