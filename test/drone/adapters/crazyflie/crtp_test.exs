defmodule Drone.Adapters.Crazyflie.CRTPTest do
  use ExUnit.Case, async: true

  alias Drone.Adapters.Crazyflie.Commander
  alias Drone.Adapters.Crazyflie.CRTP
  alias Drone.Adapters.Crazyflie.CRTP.Ports
  alias Drone.Adapters.Crazyflie.Platform
  alias Drone.Adapters.Crazyflie.SupervisorCmd
  alias Drone.Adapters.Crazyflie.Units

  test "header encodes port and channel with legacy link bits" do
    # port 8 channel 0 -> 0b1000_11_00 = 0x8C
    assert CRTP.header(8, 0) == 0x8C
    assert CRTP.decode_header(0x8C) == {8, 0}
  end

  test "null packet is port 15 channel 3" do
    assert CRTP.null?(CRTP.null_packet())
    assert CRTP.encode_null() == <<0xFF>>
  end

  test "rejects oversized payloads" do
    payload = :binary.copy(<<0>>, 31)
    assert {:error, :oversized_payload} = CRTP.encode(%{port: 1, channel: 0, payload: payload})
  end

  test "decode empty and invalid packets" do
    assert {:error, :empty_packet} = CRTP.decode(<<>>)
    assert {:error, :invalid_packet} = CRTP.decode(:not_binary)
  end

  test "round-trips encode/decode" do
    packet = %{port: Ports.port(:setpoint_hl), channel: 0, payload: <<7, 0, 1, 2, 3>>}
    assert {:ok, bin} = CRTP.encode(packet)
    assert {:ok, ^packet} = CRTP.decode(bin)
  end

  test "TAKEOFF_2 golden vector (little-endian floats)" do
    packet = Commander.takeoff_2(0.5, 2.0, use_current_yaw: true, yaw: 0.0)
    assert packet.port == 8

    assert <<7, 0, height::little-float-32, yaw::little-float-32, 1, duration::little-float-32>> =
             packet.payload

    assert_in_delta height, 0.5, 0.0001
    assert_in_delta yaw, 0.0, 0.0001
    assert_in_delta duration, 2.0, 0.0001
  end

  test "GO_TO_2 golden vector" do
    packet = Commander.go_to_2(0.5, 0.0, 0.0, 0.0, 1.0, relative: true, linear: false)

    assert <<12, 0, 1, 0, x::little-float-32, _y::little-float-32, _z::little-float-32,
             _yaw::little-float-32, dur::little-float-32>> = packet.payload

    assert_in_delta x, 0.5, 0.0001
    assert_in_delta dur, 1.0, 0.0001
  end

  test "STOP and supervisor packets" do
    assert Commander.stop().payload == <<3, 0>>
    assert SupervisorCmd.arm().port == 9
    assert SupervisorCmd.emergency().payload == <<2>>
  end

  test "protocol compatibility" do
    assert :ok = Platform.check_compatibility(8)
    assert {:error, {:unsupported_protocol, 99}} = Platform.check_compatibility(99)
    assert {:ok, 8} = Platform.parse_protocol_version(<<0, 8>>)
  end

  test "unit conversions" do
    assert Units.cm_to_m(50) == 0.5
    assert Units.m_to_cm(0.5) == 50
    assert_in_delta Units.deg_to_rad(180), :math.pi(), 0.0001
    assert Units.rad_to_deg(:math.pi()) == 180
  end
end
