defmodule Drone.Adapters.Crazyflie.ExtraCoverageTest do
  use ExUnit.Case, async: false

  alias Drone.Adapter.Capabilities
  alias Drone.Adapters.Crazyflie
  alias Drone.Adapters.Crazyflie.CRTP
  alias Drone.Adapters.Crazyflie.CRTP.Ports
  alias Drone.Adapters.Crazyflie.Platform
  alias Drone.Adapters.Crazyflie.Transport
  alias Drone.Adapters.Crazyflie.Transport.Mock
  alias Drone.Command

  test "ports.all/0 lists known subsystems" do
    assert Ports.port(:supervisor) == 9
    assert map_size(Ports.all()) >= 8
  end

  test "platform rejects unknown version payloads" do
    assert {:error, :invalid_version_response} = Platform.parse_protocol_version(<<1, 2, 3>>)
    assert {:error, {:unsupported_protocol, :unknown}} = Platform.check_compatibility(:nope)
    assert Platform.min_supported() <= Platform.max_supported()
  end

  test "CRTP invalid encode and oversized decode path" do
    assert {:error, :invalid_packet} = CRTP.encode(%{port: 1})
    huge = :binary.copy(<<1>>, 40)
    assert {:error, :invalid_packet} = CRTP.decode(<<0x8C, huge::binary>>)
  end

  test "transport resolve prefers explicit module and radio/mock URIs" do
    assert {:ok, Mock} = Transport.resolve([])
    assert {:ok, Mock} = Transport.resolve(uri: "mock://ready")

    assert {:ok, Drone.Adapters.Crazyflie.Transport.Crazyradio} =
             Transport.resolve(uri: "radio://0/80/2M")

    assert {:ok, Drone.CrazyflieTransportMock} =
             Transport.resolve(transport: Drone.CrazyflieTransportMock)
  end

  test "mock transport force_unplug and absolute go_to" do
    {:ok, state} = Mock.open(mock_profile: :default)
    state = Mock.force_unplug(state)
    assert {:error, :link_lost, _} = Mock.send(state, CRTP.null_packet())

    {:ok, state} = Mock.open([])

    packet = %{
      port: 8,
      channel: 0,
      payload:
        <<12, 0, 0, 0, 1.0::little-float-32, 2.0::little-float-32, 3.0::little-float-32,
          0.0::little-float-32, 1.0::little-float-32>>
    }

    assert {:ok, _, %{x: 1.0, y: 2.0, z: 3.0}} = Mock.send(state, packet)
  end

  test "adapter covers remaining commands and queries" do
    {:ok, state} = Crazyflie.connect(uri: "mock://ready")
    assert {:ok, :ok, state} = Crazyflie.command(state, Command.sdk_mode())
    assert {:ok, :ok, state} = Crazyflie.command(state, Command.takeoff())
    assert {:ok, :ok, state} = Crazyflie.command(state, Command.move(:back, 20))
    assert {:ok, :ok, state} = Crazyflie.command(state, Command.move(:left, 20))
    assert {:ok, :ok, state} = Crazyflie.command(state, Command.move(:right, 20))
    assert {:ok, :ok, state} = Crazyflie.command(state, Command.move(:up, 20))
    assert {:ok, :ok, state} = Crazyflie.command(state, Command.move(:down, 20))
    assert {:ok, :ok, state} = Crazyflie.command(state, Command.rotate(:ccw, 45))
    assert {:ok, :ok, state} = Crazyflie.command(state, Command.stop())
    assert {:ok, :ok, state} = Crazyflie.command(state, Command.hover(seconds: 1))
    assert {:ok, :ok, state} = Crazyflie.command(state, Command.speed(40))
    assert {:ok, 40, state} = Crazyflie.command(state, Command.query(:speed))
    assert {:ok, _, state} = Crazyflie.command(state, Command.query(:height))
    assert {:ok, _, state} = Crazyflie.command(state, Command.query(:sdk_version))
    assert {:ok, "mock-cf", state} = Crazyflie.command(state, Command.query(:serial_number))

    assert {:error, {:unsupported_query, :wifi}, state} =
             Crazyflie.command(state, Command.query(:wifi))

    assert {:ok, :ok, state} = Crazyflie.command(state, Command.emergency())
    assert state.mode == :emergency
    assert :ok = Crazyflie.disconnect(state)
  end

  test "emergency surfaces link loss from unplugged mock" do
    {:ok, state} = Crazyflie.connect(uri: "mock://ready")
    ts = Mock.force_unplug(state.session.transport_state)
    state = put_in(state.session.transport_state, ts)
    assert {:error, :link_lost, state} = Crazyflie.command(state, Command.emergency())
    assert state.mode == :emergency
    assert state.last_error == :link_lost
  end

  test "land and move errors when transport unplugged mid-flight" do
    {:ok, state} = Crazyflie.connect(uri: "mock://ready")
    assert {:ok, :ok, state} = Crazyflie.command(state, Command.sdk_mode())
    assert {:ok, :ok, state} = Crazyflie.command(state, Command.takeoff())
    ts = Mock.force_unplug(state.session.transport_state)
    state = put_in(state.session.transport_state, ts)
    assert {:error, :link_lost, _} = Crazyflie.command(state, Command.move(:forward, 20))
  end

  test "readiness rejects nil telemetry_at" do
    {:ok, state} = Crazyflie.connect(uri: "mock://ready")
    state = %{state | telemetry_at: nil, estimator_ready: true, battery: 100}
    assert {:error, :stale_telemetry, _} = Crazyflie.command(state, Command.takeoff())
  end

  test "mock transport opens from unparseable uri defaults profile" do
    {:ok, state} = Mock.open(uri: "not-a-uri")
    assert state.profile == :default
  end

  test "mock transport unknown supervisor/commander payloads" do
    {:ok, state} = Mock.open([])
    assert {:ok, _, _} = Mock.send(state, %{port: 9, channel: 0, payload: <<9>>})
    assert {:ok, _, _} = Mock.send(state, %{port: 8, channel: 0, payload: <<99>>})
    assert {:ok, _, _} = Mock.send(state, %{port: 2, channel: 0, payload: <<>>})
  end

  test "capabilities helpers" do
    caps = Capabilities.crazyflie(positioning: :lighthouse)
    assert caps.positioning == :lighthouse
    assert Capabilities.supports_command?(caps, :takeoff)
    refute Capabilities.supports_command?(caps, :flip)
    assert Capabilities.supports_query?(%{}, :battery)
  end
end
