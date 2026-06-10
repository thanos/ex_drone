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
end
