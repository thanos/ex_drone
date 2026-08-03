defmodule Drone.Adapters.Crazyflie.SafeLinkTest do
  use ExUnit.Case, async: true

  alias Drone.Adapters.Crazyflie.CRTP
  alias Drone.Adapters.Crazyflie.SafeLink

  test "enable/disable packets and echo detection" do
    assert <<0xFF, 0x05, 0x01>> = SafeLink.enable_packet()
    assert <<0xFF, 0x05, 0x00>> = SafeLink.disable_packet()
    assert SafeLink.enabled_echo?(<<0xFF, 0x05, 0x01>>)
    refute SafeLink.enabled_echo?(<<0xFF, 0x05, 0x00>>)
  end

  test "stamps header link bits without changing port/channel" do
    header = CRTP.header(8, 0)
    stamped = SafeLink.stamp_header(header, 1, 0)
    {port, channel} = CRTP.decode_header(stamped)
    assert port == 8
    assert channel == 0
    assert Bitwise.band(stamped, 0x0C) == Bitwise.bor(Bitwise.bsl(1, 3), Bitwise.bsl(0, 2))
  end

  test "stamp_frame rewrites first byte" do
    {:ok, raw} = CRTP.encode(CRTP.null_packet())
    assert {:ok, <<stamped, rest::binary>>} = SafeLink.stamp_frame(raw, 0, 1)
    assert rest == <<>>
    assert Bitwise.band(stamped, 0x03) == 3
    assert Bitwise.band(stamped, 0x0C) == Bitwise.bsl(1, 2)
  end

  test "advance flips uplink always and downlink when echoed" do
    # Downlink flips only when ACK header bit2 matches the *current* down counter.
    assert {1, 1} = SafeLink.advance(0, 0, Bitwise.bsl(0, 2))
    assert {0, 0} = SafeLink.advance(1, 1, Bitwise.bsl(1, 2))
    assert {1, 0} = SafeLink.advance(0, 0, nil)
    assert {1, 0} = SafeLink.advance(0, 0, Bitwise.bsl(1, 2))
  end
end
