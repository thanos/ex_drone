defmodule Drone.Adapters.FailingTelemAdapter do
  @moduledoc false
  @behaviour Drone.Adapter

  alias Drone.Adapter.Capabilities

  @impl true
  def connect(opts) do
    mode = Keyword.get(opts, :fail, :telemetry_error)
    {:ok, %{fail: mode, mode: :idle, flying: false, battery: 100, x: 0, y: 0, z: 0, yaw: 0}}
  end

  @impl true
  def capabilities(_), do: Capabilities.tello_like()

  @impl true
  def command(state, %Drone.Command{type: :sdk_mode}), do: {:ok, :ok, %{state | mode: :sdk_mode}}

  def command(state, %Drone.Command{type: :takeoff}),
    do: {:ok, :ok, %{state | flying: true, mode: :flying, z: 30}}

  def command(state, %Drone.Command{type: :land}),
    do: {:ok, :ok, %{state | flying: false, mode: :sdk_mode, z: 0}}

  def command(state, %Drone.Command{type: :emergency}),
    do: {:ok, :ok, %{state | flying: false, mode: :emergency}}

  def command(state, _), do: {:ok, :ok, state}

  @impl true
  def telemetry(%{fail: :telemetry_error} = state) do
    if state.mode == :idle do
      {:ok,
       %{
         x: 0,
         y: 0,
         z: 0,
         yaw: 0,
         battery: 100,
         flying: false,
         mode: :idle
       }, state}
    else
      {:error, :link_lost, state}
    end
  end

  def telemetry(%{fail: :no_pose} = state) do
    {:ok, %{battery: 100, flying: state.flying, mode: state.mode}, state}
  end

  @impl true
  def disconnect(_), do: :ok
end
