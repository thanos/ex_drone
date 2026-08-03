defmodule Drone.Test.MoxHelpers do
  @moduledoc false

  import Mox

  alias Drone.Adapter.Capabilities
  alias Drone.Command

  @doc "Stubs AdapterMock as a healthy connected drone for Vehicle tests."
  def stub_healthy_adapter!(opts \\ []) do
    battery = Keyword.get(opts, :battery, 100)
    mode = Keyword.get(opts, :mode, :idle)
    flying = Keyword.get(opts, :flying, false)

    state = %{
      battery: battery,
      mode: mode,
      flying: flying,
      x: 0,
      y: 0,
      z: if(flying, do: 30, else: 0),
      yaw: 0
    }

    stub(Drone.AdapterMock, :connect, fn _opts -> {:ok, state} end)
    stub(Drone.AdapterMock, :capabilities, fn _state -> Capabilities.tello_like() end)
    stub(Drone.AdapterMock, :telemetry, &telemetry_reply/1)
    stub(Drone.AdapterMock, :disconnect, fn _ -> :ok end)
    stub(Drone.AdapterMock, :command, &command_reply/2)
    :ok
  end

  @doc "Stubs CrazyflieUSBMock for a successful Crazyradio open/configure."
  def stub_crazyradio_usb!(opts \\ []) do
    devices = Keyword.get(opts, :devices, [%{index: 0, serial: "CR-TEST"}])
    device = Keyword.get(opts, :device, :usb_handle)

    stub(Drone.CrazyflieUSBMock, :discover, fn _ -> {:ok, devices} end)
    stub(Drone.CrazyflieUSBMock, :open, fn _info, _opts -> {:ok, device} end)
    stub(Drone.CrazyflieUSBMock, :control_write, fn _dev, _r, _v, _i, _d, _t -> :ok end)
    stub(Drone.CrazyflieUSBMock, :close, fn _ -> :ok end)
    :ok
  end

  @doc "ACK binary: status bit0=acked, optional CRTP payload bytes after."
  def ack(payload \\ <<>>, opts \\ []) do
    retries = Keyword.get(opts, :retries, 0)
    acked? = Keyword.get(opts, :acked, true)
    status = Bitwise.bor(if(acked?, do: 1, else: 0), Bitwise.bsl(retries, 4))
    <<status, payload::binary>>
  end

  defp telemetry_reply(s) do
    {:ok,
     %{
       x: s.x,
       y: s.y,
       z: s.z,
       yaw: s.yaw,
       battery: s.battery,
       flying: s.flying,
       mode: s.mode
     }, s}
  end

  defp command_reply(s, %Command{type: :sdk_mode}), do: {:ok, :ok, %{s | mode: :sdk_mode}}

  defp command_reply(s, %Command{type: :takeoff}),
    do: {:ok, :ok, %{s | flying: true, mode: :flying, z: 30}}

  defp command_reply(s, %Command{type: :land}),
    do: {:ok, :ok, %{s | flying: false, mode: :sdk_mode, z: 0}}

  defp command_reply(s, %Command{type: :emergency}),
    do: {:ok, :ok, %{s | flying: false, mode: :emergency}}

  defp command_reply(s, %Command{type: type})
       when type in [:move, :rotate, :stop, :hover, :speed, :flip],
       do: {:ok, :ok, s}

  defp command_reply(s, %Command{type: :query}), do: {:ok, Map.get(s, :battery, 100), s}
  defp command_reply(s, _cmd), do: {:error, :unsupported_command, s}
end
