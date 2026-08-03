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
    refute uri.safelink
  end

  test "parses radio defaults and datarates" do
    assert {:ok, uri} = LinkURI.parse("radio://1/10/1M")
    assert uri.radio_index == 1
    assert uri.channel == 10
    assert uri.datarate == :rate_1m
    assert byte_size(uri.address) == 5

    assert {:ok, %{datarate: :rate_250k}} = LinkURI.parse("radio://0/5/250K")
    assert {:ok, %{datarate: :rate_2m}} = LinkURI.parse("radio://0/5")
  end

  test "parses mock URI profiles and query options" do
    assert {:ok, uri} = LinkURI.parse("mock://estimator_not_ready?timeout=250")
    assert uri.scheme == :mock
    assert uri.mock_profile == :estimator_not_ready
    assert uri.timeout_ms == 250

    assert {:ok, %{mock_profile: :default, safelink: false}} = LinkURI.parse("mock://")
    assert {:ok, %{safelink: false}} = LinkURI.parse("radio://0/80/2M")
    assert {:ok, uri} = LinkURI.parse("radio://0/80/2M?safelink=1&foo=bar")
    assert uri.safelink == true
    refute Map.has_key?(uri, :ignored)
  end

  test "rejects bad schemes, channels, and malformed inputs" do
    assert {:error, :unsupported_scheme} = LinkURI.parse("ble://0")
    assert {:error, :invalid_channel} = LinkURI.parse("radio://0/999/2M")
    assert {:error, :invalid_uri} = LinkURI.parse(nil)
    assert {:error, :invalid_radio_index} = LinkURI.parse("radio://x/80/2M")
    assert {:error, :missing_radio_index} = LinkURI.parse("radio://")
    assert {:error, :missing_channel} = LinkURI.parse("radio://0")
    assert {:error, :invalid_datarate} = LinkURI.parse("radio://0/80/5M")
    assert {:error, :invalid_address_length} = LinkURI.parse("radio://0/80/2M/E7E7")
    assert {:error, :invalid_address} = LinkURI.parse("radio://0/80/2M/E7E7E7E7E")
    assert {:error, :invalid_safelink} = LinkURI.parse("radio://0/80/2M?safelink=maybe")
    assert {:error, :invalid_timeout} = LinkURI.parse("mock://ready?timeout=nope")
    assert {:error, :unknown_mock_profile} = LinkURI.parse("mock://totally_new_profile")
  end
end
