defmodule Drone.Adapters.Crazyflie.LinkURICoverageTest do
  use ExUnit.Case, async: true

  alias Drone.Adapters.Crazyflie.LinkURI

  test "parses radio defaults and datarates" do
    assert {:ok, uri} = LinkURI.parse("radio://1/10/1M")
    assert uri.radio_index == 1
    assert uri.channel == 10
    assert uri.datarate == :rate_1m
    assert byte_size(uri.address) == 5

    assert {:ok, %{datarate: :rate_250k}} = LinkURI.parse("radio://0/5/250K")
    assert {:ok, %{datarate: :rate_2m}} = LinkURI.parse("radio://0/5")
  end

  test "parses mock empty path and safelink query" do
    assert {:ok, %{mock_profile: :default}} = LinkURI.parse("mock://")
    assert {:ok, %{safelink: false}} = LinkURI.parse("radio://0/80/2M?safelink=0")
    assert {:ok, %{safelink: true}} = LinkURI.parse("radio://0/80/2M?safelink=1&foo=bar")
  end

  test "rejects invalid inputs" do
    assert {:error, :invalid_uri} = LinkURI.parse(nil)
    assert {:error, :invalid_radio_index} = LinkURI.parse("radio://x/80/2M")
    assert {:error, :missing_radio_index} = LinkURI.parse("radio://")
    assert {:error, :missing_channel} = LinkURI.parse("radio://0")
    assert {:error, :invalid_datarate} = LinkURI.parse("radio://0/80/5M")
    assert {:error, :invalid_address_length} = LinkURI.parse("radio://0/80/2M/E7E7")
    assert {:error, :invalid_address} = LinkURI.parse("radio://0/80/2M/E7E7E7E7E")
    assert {:error, :invalid_safelink} = LinkURI.parse("radio://0/80/2M?safelink=maybe")
    assert {:error, :invalid_timeout} = LinkURI.parse("mock://ready?timeout=nope")
  end
end
