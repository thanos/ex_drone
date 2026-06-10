defmodule Drone.Adapters.TelloTest do
  use ExUnit.Case, async: false

  alias Drone.Adapters.Tello
  alias Drone.Command

  describe "connect/1" do
    test "connects with default options" do
      assert {:ok, %Tello{} = state} = Tello.connect(local_port: 0)
      assert state.mode == :idle
      assert is_port(state.socket)
      Tello.disconnect(state)
    end

    test "connects with custom options" do
      assert {:ok, %Tello{} = state} =
               Tello.connect(local_port: 0, timeout: 5000)

      assert state.timeout == 5000
      Tello.disconnect(state)
    end
  end

  describe "telemetry/1" do
    test "returns telemetry map" do
      {:ok, state} = Tello.connect(local_port: 0)
      assert {:ok, telemetry, _} = Tello.telemetry(state)
      assert Map.has_key?(telemetry, :x)
      assert Map.has_key?(telemetry, :y)
      assert Map.has_key?(telemetry, :z)
      assert Map.has_key?(telemetry, :flying)
      assert Map.has_key?(telemetry, :mode)
      Tello.disconnect(state)
    end
  end

  describe "disconnect/1" do
    test "disconnects cleanly" do
      {:ok, state} = Tello.connect(local_port: 0)
      assert :ok = Tello.disconnect(state)
    end
  end

  describe "state machine" do
    test "starts in idle mode" do
      {:ok, state} = Tello.connect(local_port: 0)
      assert state.mode == :idle
      Tello.disconnect(state)
    end

    test "commands timeout without a real drone" do
      {:ok, state} = Tello.connect(local_port: 0)

      # Without a real Tello drone on the network, commands timeout.
      # This verifies the adapter handles UDP timeouts correctly.
      result = Tello.command(state, Command.sdk_mode())

      assert match?({:error, :timeout, _}, result)

      {:ok, state} = Tello.connect(local_port: 0)
      Tello.disconnect(state)
    end
  end

  describe "encoder/decoder" do
    test "encoder encodes all commands" do
      alias Drone.Adapters.Tello.Encoder

      assert Encoder.encode(Command.sdk_mode()) == "command"
      assert Encoder.encode(Command.takeoff()) == "takeoff"
      assert Encoder.encode(Command.land()) == "land"
      assert Encoder.encode(Command.emergency()) == "emergency"
      assert Encoder.encode(Command.move(:up, 50)) == "up 50"
      assert Encoder.encode(Command.rotate(:cw, 90)) == "cw 90"
      assert Encoder.encode(Command.flip(:left)) == "flip l"
      assert Encoder.encode(Command.speed(50)) == "speed 50"
      assert Encoder.encode(Command.query(:battery)) == "battery?"
    end

    test "parser parses all responses" do
      alias Drone.Adapters.Tello.Parser

      assert Parser.parse("ok") == {:ok, :ok}
      assert Parser.parse("error") == {:error, :command_error}
      assert Parser.parse("75") == {:ok, 75}
      assert Parser.parse("192.168.10.1") == {:ok, "192.168.10.1"}
      assert Parser.parse(nil) == {:error, :timeout}
    end
  end
end
