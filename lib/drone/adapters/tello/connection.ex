defmodule Drone.Adapters.Tello.Connection do
  @moduledoc """
  UDP connection handler for the Tello drone.

  Manages a `:gen_udp` socket for sending commands and receiving
  responses from a Tello drone over Wi-Fi.
  """

  @default_drone_ip {192, 168, 10, 1}
  @default_drone_port 8889
  @default_local_port 8889
  @default_timeout 10_000

  def default_drone_ip, do: @default_drone_ip
  def default_drone_port, do: @default_drone_port
  def default_local_port, do: @default_local_port
  def default_timeout, do: @default_timeout

  @spec open(keyword()) :: {:ok, port()} | {:error, term()}
  def open(opts \\ []) do
    local_port = Keyword.get(opts, :local_port, @default_local_port)
    :gen_udp.open(local_port, [:inet, {:active, false}])
  end

  @spec close(port()) :: :ok
  def close(socket) do
    :gen_udp.close(socket)
  end

  @spec send_command(port(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def send_command(socket, command, opts \\ []) do
    ip = Keyword.get(opts, :drone_ip, @default_drone_ip)
    port = Keyword.get(opts, :drone_port, @default_drone_port)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    case :gen_udp.send(socket, ip, port, command) do
      :ok ->
        receive_response(socket, timeout)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec receive_response(port(), non_neg_integer()) :: {:ok, binary()} | {:error, term()}
  def receive_response(socket, timeout) do
    case :gen_udp.recv(socket, 0, timeout) do
      {:ok, {_ip, _port, data}} when is_binary(data) ->
        {:ok, data}

      {:ok, {_ip, _port, data}} when is_list(data) ->
        {:ok, :erlang.list_to_binary(data)}

      {:error, :timeout} ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
