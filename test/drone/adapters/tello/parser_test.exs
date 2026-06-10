defmodule Drone.Adapters.Tello.ParserTest do
  use ExUnit.Case, async: true

  alias Drone.Adapters.Tello.Parser

  describe "parse/1" do
    test "parses ok response" do
      assert {:ok, :ok} = Parser.parse("ok")
    end

    test "parses ok response with trailing whitespace" do
      assert {:ok, :ok} = Parser.parse("ok\r\n")
    end

    test "parses error response" do
      assert {:error, :command_error} = Parser.parse("error")
    end

    test "parses numeric response" do
      assert {:ok, 75} = Parser.parse("75")
    end

    test "parses string response" do
      assert {:ok, "192.168.10.1"} = Parser.parse("192.168.10.1")
    end

    test "parses nil as timeout" do
      assert {:error, :timeout} = Parser.parse(nil)
    end

    test "parses :timeout as timeout" do
      assert {:error, :timeout} = Parser.parse(:timeout)
    end
  end
end
