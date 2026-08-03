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
    assert state.uri.safelink == false
    assert :ok = Crazyradio.close(state)
  end

  test "opens from pre-parsed link_uri and supports 250K/1M rates" do
    {:ok, uri} = LinkURI.parse("radio://0/40/250K")
    uri = %{uri | datarate: :rate_1m}

    assert {:ok, state} =
             Crazyradio.open(link_uri: uri, usb_backend: Drone.CrazyflieUSBMock)

    assert state.uri.safelink == false
    assert :ok = Crazyradio.close(state)
  end

  test "send writes raw CRTP and parses ACK payload" do
    {:ok, state} =
      Crazyradio.open(uri: "radio://0/80/2M", usb_backend: Drone.CrazyflieUSBMock)

    packet = Platform.get_protocol_version()
    {:ok, raw} = CRTP.encode(packet)

    expect(Drone.CrazyflieUSBMock, :bulk_write, fn :usb_handle, 0x01, framed, _timeout ->
      assert framed == raw
      :ok
    end)

    expect(Drone.CrazyflieUSBMock, :bulk_read, fn :usb_handle, 0x81, 64, _timeout ->
      {:ok, ack(<<0, 8>>, retries: 2)}
    end)

    assert {:ok, %{acked: true, retries: 2, payload: <<0, 8>>}, _new_state} =
             Crazyradio.send(state, packet)
  end

  test "enables SafeLink and stamps CRTP headers" do
    expect(Drone.CrazyflieUSBMock, :bulk_write, fn :usb_handle, 0x01, <<0xFF, 0x05, 0x01>>, _ ->
      :ok
    end)

    expect(Drone.CrazyflieUSBMock, :bulk_read, fn :usb_handle, 0x81, 64, _ ->
      {:ok, ack(<<0xFF, 0x05, 0x01>>)}
    end)

    assert {:ok, state} =
             Crazyradio.open(
               uri: "radio://0/80/2M?safelink=1",
               usb_backend: Drone.CrazyflieUSBMock
             )

    assert state.safelink_enabled
    assert state.safelink_up == 0
    assert state.safelink_down == 0

    packet = CRTP.null_packet()
    {:ok, raw} = CRTP.encode(packet)

    expect(Drone.CrazyflieUSBMock, :bulk_write, fn :usb_handle, 0x01, framed, _ ->
      refute framed == raw
      assert byte_size(framed) == byte_size(raw)
      :ok
    end)

    expect(Drone.CrazyflieUSBMock, :bulk_read, fn :usb_handle, 0x81, 64, _ ->
      {:ok, ack(<<>>)}
    end)

    assert {:ok, _, state} = Crazyradio.send(state, packet)
    assert state.safelink_up == 1
  end

  test "safelink enable failure closes USB" do
    expect(Drone.CrazyflieUSBMock, :bulk_write, 10, fn :usb_handle,
                                                       0x01,
                                                       <<0xFF, 0x05, 0x01>>,
                                                       _ ->
      :ok
    end)

    expect(Drone.CrazyflieUSBMock, :bulk_read, 10, fn :usb_handle, 0x81, 64, _ ->
      {:ok, ack(<<0xFF, 0x05, 0x00>>)}
    end)

    expect(Drone.CrazyflieUSBMock, :close, fn :usb_handle -> :ok end)

    assert {:error, :safelink_enable_failed} =
             Crazyradio.open(
               uri: "radio://0/80/2M?safelink=1",
               usb_backend: Drone.CrazyflieUSBMock
             )
  end

  test "telemetry stays unknown until logging cache is filled" do
    {:ok, state} =
      Crazyradio.open(uri: "radio://0/80/2M", usb_backend: Drone.CrazyflieUSBMock)

    assert {:ok, telem, ^state} = Crazyradio.telemetry(state)
    assert telem.battery == nil
    assert telem.estimator_ready == nil
  end

  test "ingest_ack_payload updates battery and estimator from log data" do
    alias Drone.Adapters.Crazyflie.Logging

    {:ok, state} =
      Crazyradio.open(uri: "radio://0/80/2M", usb_backend: Drone.CrazyflieUSBMock)

    layout = [
      %{key: :battery, type: 1, id: 0, source: :battery_level},
      %{key: :estimator_ready, type: 1, id: 1, source: :canfly}
    ]

    state = Crazyradio.configure_logging(state, layout, 0)

    {:ok, frame} =
      CRTP.encode(%{port: 5, channel: Logging.data_channel(), payload: <<0, 0, 0, 0, 77, 1>>})

    state = Crazyradio.ingest_ack_payload(state, frame)

    assert {:ok, telem, _} = Crazyradio.telemetry(state)
    assert telem.battery == 77
    assert telem.estimator_ready == true
  end

  test "does not advance SafeLink counters on :no_ack" do
    expect(Drone.CrazyflieUSBMock, :bulk_write, fn :usb_handle, 0x01, <<0xFF, 0x05, 0x01>>, _ ->
      :ok
    end)

    expect(Drone.CrazyflieUSBMock, :bulk_read, fn :usb_handle, 0x81, 64, _ ->
      {:ok, ack(<<0xFF, 0x05, 0x01>>)}
    end)

    assert {:ok, state} =
             Crazyradio.open(
               uri: "radio://0/80/2M?safelink=1",
               usb_backend: Drone.CrazyflieUSBMock
             )

    expect(Drone.CrazyflieUSBMock, :bulk_write, fn _, _, _, _ -> :ok end)

    expect(Drone.CrazyflieUSBMock, :bulk_read, fn _, _, _, _ -> {:ok, ack(<<>>, acked: false)} end)

    assert {:error, :no_ack, state} = Crazyradio.send(state, CRTP.null_packet())
    assert state.safelink_up == 0
    assert state.safelink_down == 0
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

  test "control_write failure during configure closes the USB handle" do
    expect(Drone.CrazyflieUSBMock, :control_write, fn _dev, _r, _v, _i, _d, _t ->
      {:error, :usb_stall}
    end)

    expect(Drone.CrazyflieUSBMock, :close, fn :usb_handle -> :ok end)

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
