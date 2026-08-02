defmodule Drone.Adapters.Tello.FakeServerTest do
  use ExUnit.Case, async: false

  alias Drone.Adapter.Capabilities
  alias Drone.Adapters.Tello
  alias Drone.Command

  setup do
    port = 20_000 + rem(System.unique_integer([:positive]), 20_000)
    start_supervised!({Drone.Adapters.Tello.FakeServer, port: port})

    {:ok, state} =
      Tello.connect(
        drone_ip: {127, 0, 0, 1},
        drone_port: port,
        local_port: 0,
        timeout: 1_000
      )

    on_exit(fn ->
      try do
        Tello.disconnect(state)
      rescue
        _ -> :ok
      catch
        :exit, _ -> :ok
      end
    end)

    {:ok, state: state, port: port}
  end

  test "full flight loop updates adapter state via FakeServer", %{state: state} do
    assert Tello.capabilities(state) == Capabilities.tello_like()

    assert {:ok, :ok, state} = Tello.command(state, Command.sdk_mode())
    assert state.mode == :sdk_mode

    assert {:ok, :ok, state} = Tello.command(state, Command.takeoff())
    assert state.flying
    assert state.mode == :flying
    assert state.z == 30

    assert {:ok, :ok, state} = Tello.command(state, Command.move(:forward, 50))
    assert state.y == 50

    assert {:ok, :ok, state} = Tello.command(state, Command.move(:right, 40))
    assert state.x == 40

    assert {:ok, :ok, state} = Tello.command(state, Command.rotate(:cw, 90))
    assert state.yaw == 90

    assert {:ok, :ok, state} = Tello.command(state, Command.flip(:forward))
    assert {:ok, :ok, state} = Tello.command(state, Command.speed(40))
    assert {:ok, :ok, state} = Tello.command(state, Command.stop())
    assert {:ok, :ok, state} = Tello.command(state, Command.hover(seconds: 1))

    assert {:ok, 85, state} = Tello.command(state, Command.query(:battery))
    assert {:ok, 50, state} = Tello.command(state, Command.query(:speed))
    assert {:ok, 30, state} = Tello.command(state, Command.query(:height))
    assert is_nil(state.z)

    assert {:ok, 12, state} = Tello.command(state, Command.query(:time))
    assert {:ok, 90, state} = Tello.command(state, Command.query(:wifi))
    assert {:ok, 20, state} = Tello.command(state, Command.query(:sdk_version))
    assert {:ok, "0TQTESTSN", state} = Tello.command(state, Command.query(:serial_number))

    assert {:ok, :ok, state} = Tello.command(state, Command.land())
    assert state.mode == :sdk_mode
    refute state.flying

    assert {:ok, :ok, state} = Tello.command(state, Command.emergency())
    assert state.mode == :emergency
  end

  test "command_error from FakeServer flows through Tello.command/2", %{state: state} do
    assert {:ok, :ok, state} = Tello.command(state, Command.sdk_mode())
    assert {:ok, :ok, state} = Tello.command(state, Command.takeoff())
    assert {:error, :command_error, _} = Tello.command(state, Command.takeoff())
  end

  test "connect failure when local port is already bound" do
    {:ok, sock} = :gen_udp.open(0, [:inet, {:active, false}])
    {:ok, port} = :inet.port(sock)

    assert {:error, {:connection_error, _}} = Tello.connect(local_port: port)
    :gen_udp.close(sock)
  end

  test "public Drone API against FakeServer uses tello adapter", %{port: port} do
    name = :"tello_fake_#{System.unique_integer([:positive])}"

    assert {:ok, ^name} =
             Drone.connect(:tello,
               name: name,
               drone_ip: {127, 0, 0, 1},
               drone_port: port,
               local_port: 0,
               timeout: 1_000
             )

    assert :ok = Drone.connect_sdk(name)
    assert :ok = Drone.takeoff(name)
    assert {:ok, 85} = Drone.query(name, :battery)
    assert {:ok, tel} = Drone.telemetry(name)
    assert tel.flying == true
    assert :ok = Drone.land(name)
    assert :ok = Drone.disconnect(name)
  end
end
