defmodule Drone.Adapter.AcceptanceTest do
  use ExUnit.Case, async: false

  @moduledoc false

  alias Drone.Adapter.Capabilities

  # Shared contract checks for adapters that support the common command set.

  setup do
    {:ok, _} = Application.ensure_all_started(:ex_drone)
    :ok
  end

  for {adapter, opts} <- [
        {:sim, []},
        {:crazyflie, [uri: "mock://ready", positioning: :flow]}
      ] do
    @adapter adapter
    @opts opts

    test "#{adapter} satisfies connect/sdk/query/disconnect contract" do
      name = :"acceptance_#{@adapter}_#{System.unique_integer([:positive])}"

      assert {:ok, drone} = Drone.connect(@adapter, Keyword.merge([name: name], @opts))
      caps = Drone.capabilities(drone)
      assert is_map(caps)
      assert Map.has_key?(caps, :sdk_mode)
      assert is_list(caps.commands)
      assert :takeoff in caps.commands
      assert :land in caps.commands
      assert :ok = Drone.connect_sdk(drone)
      assert {:ok, battery} = Drone.query(drone, :battery)
      assert is_integer(battery)
      assert :ok = Drone.disconnect(drone)
    end

    test "#{adapter} flies a short takeoff/move/land mission" do
      name = :"acceptance_flight_#{@adapter}_#{System.unique_integer([:positive])}"

      assert {:ok, drone} = Drone.connect(@adapter, Keyword.merge([name: name], @opts))
      assert :ok = Drone.connect_sdk(drone)
      assert :ok = Drone.takeoff(drone)
      assert :ok = Drone.move(drone, :forward, 20)
      assert :ok = Drone.rotate(drone, :cw, 45)
      assert {:ok, telem} = Drone.telemetry(drone)
      assert is_map(telem)
      assert :ok = Drone.land(drone)
      assert :ok = Drone.disconnect(drone)
    end

    test "#{adapter} advertised commands match adapter acceptance" do
      name = :"acceptance_caps_#{@adapter}_#{System.unique_integer([:positive])}"

      assert {:ok, drone} = Drone.connect(@adapter, Keyword.merge([name: name], @opts))
      caps = Drone.capabilities(drone)

      for command <- caps.commands do
        assert Capabilities.supports_command?(caps, command)
      end

      for query <- Map.get(caps, :queries, []) do
        assert Capabilities.supports_query?(caps, query)
      end

      assert :ok = Drone.disconnect(drone)
    end
  end
end
