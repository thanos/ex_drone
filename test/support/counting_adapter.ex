defmodule Drone.Adapters.CountingAdapter do
  @moduledoc false
  # Test-support adapter that counts disconnect/1 invocations via an Agent
  # passed in through connect options. Used to verify cleanup runs exactly once.

  @behaviour Drone.Adapter

  @impl Drone.Adapter
  def connect(opts) do
    counter = Keyword.fetch!(opts, :counter)
    {:ok, %{counter: counter}}
  end

  @impl Drone.Adapter
  def command(state, _cmd), do: {:ok, :ok, state}

  @impl Drone.Adapter
  def telemetry(state), do: {:ok, %{}, state}

  @impl Drone.Adapter
  def disconnect(%{counter: counter}) do
    Agent.update(counter, &(&1 + 1))
    :ok
  end
end
