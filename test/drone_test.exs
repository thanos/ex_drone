defmodule DroneTest do
  use ExUnit.Case, async: false

  describe "connect/2" do
    test "connects to simulator" do
      name = :"drone_sim_#{System.unique_integer([:positive])}"
      assert {:ok, ^name} = Drone.connect(:sim, name: name)
    end

    test "connects with indoor safety" do
      name = :"drone_indoor_#{System.unique_integer([:positive])}"
      assert {:ok, ^name} = Drone.connect(:sim, name: name, safety: [indoor: true])
    end

    test "rejects duplicate names" do
      name = :"drone_dup_#{System.unique_integer([:positive])}"
      assert {:ok, ^name} = Drone.connect(:sim, name: name)
      assert {:error, :name_already_taken} = Drone.connect(:sim, name: name)
    end
  end

  describe "full flight flow" do
    test "complete mission with simulator" do
      name = :"full_flow_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name)
      Drone.connect_sdk(name)

      :ok = Drone.takeoff(name)
      :ok = Drone.move(name, :up, 40)
      :ok = Drone.move(name, :forward, 100)
      :ok = Drone.rotate(name, :cw, 90)
      :ok = Drone.land(name)

      {:ok, telemetry} = Drone.telemetry(name)
      assert telemetry.flying == false

      :ok = Drone.disconnect(name)
    end

    test "query operations" do
      name = :"query_test_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name)
      Drone.connect_sdk(name)

      assert {:ok, _} = Drone.query(name, :battery)
      assert {:ok, _} = Drone.query(name, :sdk_version)

      :ok = Drone.disconnect(name)
    end
  end

  describe "safety" do
    test "prevents movement when not flying" do
      name = :"safety_nofly_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name)
      Drone.connect_sdk(name)

      assert {:error, :safety, :not_flying} = Drone.move(name, :forward, 100)

      :ok = Drone.disconnect(name)
    end

    test "prevents takeoff with low battery" do
      name = :"low_bat_#{System.unique_integer([:positive])}"

      {:ok, ^name} =
        Drone.connect(:sim, name: name, battery: 5, safety: [min_battery_percent: 15])

      Drone.connect_sdk(name)

      assert {:error, :safety, :low_battery} = Drone.takeoff(name)

      :ok = Drone.disconnect(name)
    end

    test "emergency bypasses safety" do
      name = :"emerg_bypass_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name, safety: [allowlist: [:sdk_mode, :takeoff]])
      Drone.connect_sdk(name)
      :ok = Drone.takeoff(name)

      assert :ok = Drone.emergency(name)

      :ok = Drone.disconnect(name)
    end
  end

  describe "telemetry" do
    test "returns telemetry data" do
      name = :"tele_#{System.unique_integer([:positive])}"
      {:ok, ^name} = Drone.connect(:sim, name: name)
      Drone.connect_sdk(name)

      {:ok, telemetry} = Drone.telemetry(name)
      assert Map.has_key?(telemetry, :x)
      assert Map.has_key?(telemetry, :y)
      assert Map.has_key?(telemetry, :z)
      assert Map.has_key?(telemetry, :battery)
      assert Map.has_key?(telemetry, :flying)
      assert Map.has_key?(telemetry, :mode)

      :ok = Drone.disconnect(name)
    end
  end
end
