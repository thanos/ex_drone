defmodule Drone.Adapters.Tello.ConnectionTest do
  use ExUnit.Case, async: true

  alias Drone.Adapters.Tello.Connection

  describe "open/1 and close/1" do
    test "opens and closes a UDP socket" do
      assert {:ok, socket} = Connection.open(local_port: 0)
      assert is_port(socket)
      assert :ok = Connection.close(socket)
    end

    test "fails on occupied port" do
      {:ok, socket} = Connection.open(local_port: 0)
      {:ok, port} = :inet.port(socket)

      assert {:error, _} = Connection.open(local_port: port)
      Connection.close(socket)
    end
  end

  describe "receive_response/2" do
    test "returns timeout when no response" do
      {:ok, socket} = Connection.open(local_port: 0)
      assert {:error, :timeout} = Connection.receive_response(socket, 100)
      Connection.close(socket)
    end
  end

  describe "default configuration" do
    test "default_drone_ip returns correct IP" do
      assert Connection.default_drone_ip() == {192, 168, 10, 1}
    end

    test "default_drone_port returns correct port" do
      assert Connection.default_drone_port() == 8889
    end

    test "default_local_port returns correct port" do
      assert Connection.default_local_port() == 8889
    end

    test "default_timeout returns correct timeout" do
      assert Connection.default_timeout() == 10_000
    end
  end

  describe "send_command/3" do
    test "returns error when sending to closed socket" do
      {:ok, socket} = Connection.open(local_port: 0)
      Connection.close(socket)
      # Sending to a closed socket should error
      assert {:error, _} = Connection.send_command(socket, "command")
    end
  end
end
