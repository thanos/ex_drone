defmodule Drone.Adapters.Crazyflie.Transport.CrazyradioTest do
  use ExUnit.Case, async: false

  import Mox
  import Drone.Test.MoxHelpers

  alias Drone.Adapters.Crazyflie.CRTP
  alias Drone.Adapters.Crazyflie.LinkURI
  alias Drone.Adapters.Crazyflie.Platform
  alias Drone.Adapters.Crazyflie.Transport.Crazyradio
  alias Drone.Adapters.Crazyflie.USB.Unavailable

  setup :verify_on_exit!

  setup do
    stub_crazyradio_usb!()
    :ok
  end

  test "opens radio URI with USB mock and configures channel/address/rate" do
    expect(Drone.CrazyflieUSBMock, :control_write, 5, fn _dev, _r, _v, _i, _d, _t -> :ok end)

    assert {:ok, state} =
             Crazyradio.open(
               uri: "radio://0/80/2M/E7E7E7E7E7",
               usb_backend: Drone.CrazyflieUSBMock
             )

    assert state.backend == Drone.CrazyflieUSBMock
    assert state.uri.channel == 80
    assert state.safelink_up == 0
    assert :ok = Crazyradio.close(state)
  end

  test "opens from pre-parsed link_uri and supports 250K/1M rates" do
    {:ok, uri} = LinkURI.parse("radio://0/40/250K?safelink=0")
    uri = %{uri | datarate: :rate_1m}

    assert {:ok, state} =
             Crazyradio.open(link_uri: uri, usb_backend: Drone.CrazyflieUSBMock)

    assert state.uri.safelink == false
    assert :ok = Crazyradio.close(state)
  end

  test "send frames SafeLink and parses ACK payload" do
    {:ok, state} =
      Crazyradio.open(uri: "radio://0/80/2M", usb_backend: Drone.CrazyflieUSBMock)

    packet = Platform.get_protocol_version()

    expect(Drone.CrazyflieUSBMock, :bulk_write, fn :usb_handle, 0x01, framed, _timeout ->
      assert <<0, _header, _payload::binary>> = framed
      :ok
    end)

    expect(Drone.CrazyflieUSBMock, :bulk_read, fn :usb_handle, 0x81, 64, _timeout ->
      {:ok, ack(<<0, 8>>, retries: 2)}
    end)

    assert {:ok, %{acked: true, retries: 2, payload: <<0, 8>>}, new_state} =
             Crazyradio.send(state, packet)

    assert new_state.safelink_up == 1
  end

  test "send without safelink does not prepend counter" do
    {:ok, uri} = LinkURI.parse("radio://0/80/2M?safelink=0")

    {:ok, state} =
      Crazyradio.open(link_uri: uri, usb_backend: Drone.CrazyflieUSBMock)

    {:ok, raw} = CRTP.encode(CRTP.null_packet())

    expect(Drone.CrazyflieUSBMock, :bulk_write, fn _, _, framed, _ ->
      assert framed == raw
      :ok
    end)

    expect(Drone.CrazyflieUSBMock, :bulk_read, fn _, _, _, _ -> {:ok, ack()} end)

    assert {:ok, %{acked: true}, _} = Crazyradio.send(state, CRTP.null_packet())
  end

  test "returns :no_ack when status bit is clear" do
    {:ok, state} =
      Crazyradio.open(uri: "radio://0/80/2M", usb_backend: Drone.CrazyflieUSBMock)

    expect(Drone.CrazyflieUSBMock, :bulk_write, fn _, _, _, _ -> :ok end)

    expect(Drone.CrazyflieUSBMock, :bulk_read, fn _, _, _, _ -> {:ok, ack(<<>>, acked: false)} end)

    assert {:error, :no_ack, _} = Crazyradio.send(state, CRTP.null_packet())
  end

  test "returns :invalid_ack for empty USB response" do
    {:ok, state} =
      Crazyradio.open(uri: "radio://0/80/2M", usb_backend: Drone.CrazyflieUSBMock)

    expect(Drone.CrazyflieUSBMock, :bulk_write, fn _, _, _, _ -> :ok end)
    expect(Drone.CrazyflieUSBMock, :bulk_read, fn _, _, _, _ -> {:ok, <<>>} end)

    assert {:error, :invalid_ack, _} = Crazyradio.send(state, CRTP.null_packet())
  end

  test "propagates bulk_write errors" do
    {:ok, state} =
      Crazyradio.open(uri: "radio://0/80/2M", usb_backend: Drone.CrazyflieUSBMock)

    expect(Drone.CrazyflieUSBMock, :bulk_write, fn _, _, _, _ -> {:error, :usb_io} end)

    assert {:error, :usb_io, _} = Crazyradio.send(state, CRTP.null_packet())
  end

  test "discover empty list is crazyradio_not_found" do
    expect(Drone.CrazyflieUSBMock, :discover, fn _ -> {:ok, []} end)

    assert {:error, :crazyradio_not_found} =
             Crazyradio.open(uri: "radio://0/80/2M", usb_backend: Drone.CrazyflieUSBMock)
  end

  test "radio index out of range" do
    expect(Drone.CrazyflieUSBMock, :discover, fn _ -> {:ok, [%{index: 0}]} end)

    assert {:error, :crazyradio_index_out_of_range} =
             Crazyradio.open(uri: "radio://3/80/2M", usb_backend: Drone.CrazyflieUSBMock)
  end

  test "missing uri errors" do
    assert {:error, :missing_uri} = Crazyradio.open(usb_backend: Drone.CrazyflieUSBMock)
  end

  test "control_write failure during configure" do
    expect(Drone.CrazyflieUSBMock, :control_write, fn _dev, _r, _v, _i, _d, _t ->
      {:error, :usb_stall}
    end)

    assert {:error, :usb_stall} =
             Crazyradio.open(uri: "radio://0/80/2M", usb_backend: Drone.CrazyflieUSBMock)
  end

  test "default backend is Unavailable" do
    assert Unavailable.discover([]) == {:error, :usb_backend_unavailable}
    assert Unavailable.open(%{}, []) == {:error, :usb_backend_unavailable}

    assert Unavailable.control_write(:d, 1, 0, 0, <<>>, 1000) ==
             {:error, :usb_backend_unavailable}

    assert Unavailable.bulk_write(:d, 1, <<>>, 1000) == {:error, :usb_backend_unavailable}
    assert Unavailable.bulk_read(:d, 1, 64, 1000) == {:error, :usb_backend_unavailable}
    assert Unavailable.close(:d) == :ok
  end
end
