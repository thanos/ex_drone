defmodule Drone.Adapters.CrazyflieTest do
  use ExUnit.Case, async: false

  alias Drone.Adapters.Crazyflie
  alias Drone.Command

  setup do
    {:ok, _} = Application.ensure_all_started(:ex_drone)
    :ok
  end

  test "connect identity battery disconnect via mock transport" do
    assert {:ok, state} = Crazyflie.connect(uri: "mock://ready", positioning: :flow)
    assert state.protocol_version == 8
    assert Crazyflie.capabilities(state).sdk_mode == :optional

    assert {:ok, battery, state} = Crazyflie.command(state, Command.query(:battery))
    assert battery == 95

    assert :ok = Crazyflie.disconnect(state)
  end

  test "flight loop on mock transport" do
    {:ok, state} = Crazyflie.connect(uri: "mock://ready")
    assert {:ok, :ok, state} = Crazyflie.command(state, Command.sdk_mode())
    assert {:ok, :ok, state} = Crazyflie.command(state, Command.takeoff())
    assert state.flying
    assert {:ok, :ok, state} = Crazyflie.command(state, Command.move(:forward, 50))
    assert {:ok, :ok, state} = Crazyflie.command(state, Command.rotate(:cw, 90))
    assert {:ok, :ok, state} = Crazyflie.command(state, Command.land())
    refute state.flying
    assert :ok = Crazyflie.disconnect(state)
  end

  test "rejects takeoff when estimator is not ready" do
    {:ok, state} = Crazyflie.connect(uri: "mock://estimator_not_ready")
    assert {:ok, :ok, state} = Crazyflie.command(state, Command.sdk_mode())
    assert {:error, :estimator_not_ready, _} = Crazyflie.command(state, Command.takeoff())
  end

  test "rejects takeoff on low battery" do
    {:ok, state} = Crazyflie.connect(uri: "mock://low_battery")
    assert {:ok, :ok, state} = Crazyflie.command(state, Command.sdk_mode())
    assert {:error, :low_battery, _} = Crazyflie.command(state, Command.takeoff())
  end

  test "flip is unsupported" do
    {:ok, state} = Crazyflie.connect(uri: "mock://ready")
    assert {:error, :unsupported_command, _} = Crazyflie.command(state, Command.flip(:forward))
  end

  test "public Drone API definition-of-done path" do
    assert {:ok, drone} =
             Drone.connect(:crazyflie,
               name: :cf_dod,
               uri: "mock://ready",
               positioning: :flow
             )

    assert :ok = Drone.connect_sdk(drone)
    assert {:ok, battery} = Drone.query(drone, :battery)
    assert is_integer(battery)
    assert :ok = Drone.takeoff(drone)
    assert :ok = Drone.move(drone, :forward, 50)
    assert :ok = Drone.rotate(drone, :cw, 90)
    assert :ok = Drone.land(drone)
    assert :ok = Drone.disconnect(drone)
  end

  test "radio URI without USB backend fails clearly" do
    assert {:error, :usb_backend_unavailable} =
             Crazyflie.connect(uri: "radio://0/80/2M/E7E7E7E7E7")
  end

  test "mission rejects unsupported flip before flying" do
    assert {:ok, drone} =
             Drone.connect(:crazyflie, name: :cf_mission, uri: "mock://ready")

    mission =
      Drone.Mission.new()
      |> Drone.Mission.sdk_mode()
      |> Drone.Mission.takeoff()
      |> Drone.Mission.flip(:forward)
      |> Drone.Mission.land()

    assert {:error, %Command{type: :flip}, {:unsupported_command, :flip}} =
             Drone.Mission.run(mission, drone)

    assert :ok = Drone.disconnect(drone)
  end
end
