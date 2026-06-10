defmodule Drone.Adapters.Tello.EncoderTest do
  use ExUnit.Case, async: true

  alias Drone.{Adapters.Tello.Encoder, Command}

  describe "encode/1" do
    test "encodes sdk_mode command" do
      assert Encoder.encode(Command.sdk_mode()) == "command"
    end

    test "encodes takeoff command" do
      assert Encoder.encode(Command.takeoff()) == "takeoff"
    end

    test "encodes land command" do
      assert Encoder.encode(Command.land()) == "land"
    end

    test "encodes emergency command" do
      assert Encoder.encode(Command.emergency()) == "emergency"
    end

    test "encodes stop command" do
      assert Encoder.encode(Command.stop()) == "stop"
    end

    test "encodes move commands" do
      assert Encoder.encode(Command.move(:up, 50)) == "up 50"
      assert Encoder.encode(Command.move(:down, 30)) == "down 30"
      assert Encoder.encode(Command.move(:left, 20)) == "left 20"
      assert Encoder.encode(Command.move(:right, 40)) == "right 40"
      assert Encoder.encode(Command.move(:forward, 100)) == "forward 100"
      assert Encoder.encode(Command.move(:back, 75)) == "back 75"
    end

    test "encodes rotate commands" do
      assert Encoder.encode(Command.rotate(:cw, 90)) == "cw 90"
      assert Encoder.encode(Command.rotate(:ccw, 180)) == "ccw 180"
    end

    test "encodes flip commands" do
      assert Encoder.encode(Command.flip(:left)) == "flip l"
      assert Encoder.encode(Command.flip(:right)) == "flip r"
      assert Encoder.encode(Command.flip(:forward)) == "flip f"
      assert Encoder.encode(Command.flip(:back)) == "flip b"
    end

    test "encodes speed command" do
      assert Encoder.encode(Command.speed(50)) == "speed 50"
    end

    test "encodes hover as stop" do
      assert Encoder.encode(Command.hover(5)) == "stop"
    end

    test "encodes query commands" do
      assert Encoder.encode(Command.query(:battery)) == "battery?"
      assert Encoder.encode(Command.query(:height)) == "height?"
      assert Encoder.encode(Command.query(:speed)) == "speed?"
      assert Encoder.encode(Command.query(:time)) == "time?"
      assert Encoder.encode(Command.query(:wifi)) == "wifi?"
      assert Encoder.encode(Command.query(:sdk_version)) == "sdk?"
      assert Encoder.encode(Command.query(:serial_number)) == "sn?"
    end
  end
end
