defmodule Drone.Adapters.Tello.FakeServer do
  @moduledoc false

  use GenServer

  @movement_prefixes [
    "up ",
    "down ",
    "left ",
    "right ",
    "forward ",
    "back ",
    "cw ",
    "ccw ",
    "flip ",
    "speed "
  ]

  def start_link(opts \\ []) do
    port = Keyword.get(opts, :port, 19_876)
    GenServer.start_link(__MODULE__, port, name: __MODULE__)
  end

  def init(port) do
    {:ok, socket} = :gen_udp.open(port, [:inet, {:active, true}])
    {:ok, %{socket: socket, state: :idle, port: port}}
  end

  def handle_info({:udp, _socket, ip, port, "command"}, state) do
    :gen_udp.send(state.socket, ip, port, "ok")
    {:noreply, %{state | state: :sdk_mode}}
  end

  def handle_info({:udp, _socket, ip, port, "takeoff"}, %{state: :sdk_mode} = state) do
    :gen_udp.send(state.socket, ip, port, "ok")
    {:noreply, %{state | state: :flying}}
  end

  def handle_info({:udp, _socket, ip, port, "land"}, %{state: :flying} = state) do
    :gen_udp.send(state.socket, ip, port, "ok")
    {:noreply, %{state | state: :sdk_mode}}
  end

  def handle_info({:udp, _socket, ip, port, "emergency"}, state) do
    :gen_udp.send(state.socket, ip, port, "ok")
    {:noreply, %{state | state: :emergency}}
  end

  def handle_info({:udp, _socket, ip, port, "stop"}, state) do
    :gen_udp.send(state.socket, ip, port, "ok")
    {:noreply, state}
  end

  def handle_info({:udp, _socket, ip, port, "battery?"}, state) do
    :gen_udp.send(state.socket, ip, port, "85")
    {:noreply, state}
  end

  def handle_info({:udp, _socket, ip, port, "height?"}, state) do
    :gen_udp.send(state.socket, ip, port, "30")
    {:noreply, state}
  end

  def handle_info({:udp, _socket, ip, port, "speed?"}, state) do
    :gen_udp.send(state.socket, ip, port, "50")
    {:noreply, state}
  end

  def handle_info({:udp, _socket, ip, port, command}, state) do
    if has_movement_prefix?(command) do
      :gen_udp.send(state.socket, ip, port, "ok")
      {:noreply, state}
    else
      :gen_udp.send(state.socket, ip, port, "error")
      {:noreply, state}
    end
  end

  defp has_movement_prefix?(command) do
    Enum.any?(@movement_prefixes, &String.starts_with?(command, &1))
  end

  def terminate(_reason, state) do
    if state.socket, do: :gen_udp.close(state.socket)
  end
end
