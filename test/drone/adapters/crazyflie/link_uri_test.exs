defmodule Drone.Adapters.Crazyflie.LinkURITest do
  use ExUnit.Case, async: true

  alias Drone.Adapters.Crazyflie.LinkURI

  test "parses radio URI with address" do
    assert {:ok, uri} = LinkURI.parse("radio://0/80/2M/E7E7E7E7E7")
    assert uri.scheme == :radio
    assert uri.radio_index == 0
    assert uri.channel == 80
    assert uri.datarate == :rate_2m
    assert uri.address == <<0xE7, 0xE7, 0xE7, 0xE7, 0xE7>>
    assert uri.safelink
  end

  test "parses mock URI profiles and query options" do
    assert {:ok, uri} = LinkURI.parse("mock://estimator_not_ready?timeout=250")
    assert uri.scheme == :mock
    assert uri.mock_profile == :estimator_not_ready
    assert uri.timeout_ms == 250
  end

  test "rejects bad schemes and channels" do
    assert {:error, :unsupported_scheme} = LinkURI.parse("ble://0")
    assert {:error, :invalid_channel} = LinkURI.parse("radio://0/999/2M")
  end
end
