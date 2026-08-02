defmodule Drone.Adapter.AcceptanceTest do
  use ExUnit.Case, async: false

  @moduledoc false

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
      caps = GenServer.call(Drone.Vehicle.whereis(drone), :capabilities)
      assert is_map(caps)
      assert Map.has_key?(caps, :sdk_mode)
      assert :ok = Drone.connect_sdk(drone)
      assert {:ok, _} = Drone.query(drone, :battery)
      assert :ok = Drone.disconnect(drone)
    end
  end
end
