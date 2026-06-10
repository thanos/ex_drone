defmodule Drone.Adapter do
  @moduledoc """
  Behaviour definition for drone adapters.

  Every drone adapter must implement this behaviour. The adapter is responsible
  for all communication with the physical (or simulated) drone. The `Drone.Vehicle`
  GenServer calls adapter callbacks, passing in opaque adapter state.

  ## Implementing an Adapter

      defmodule Drone.Adapters.MyDrone do
        @behaviour Drone.Adapter

        @impl Drone.Adapter
        def connect(opts) do
          {:ok, %{ip: Keyword.fetch!(opts, :ip), port: Keyword.get(opts, :port, 8889)}}
        end

        @impl Drone.Adapter
        def command(state, %Drone.Command{type: :takeoff}) do
          {:ok, :ok, state}
        end

        @impl Drone.Adapter
        def telemetry(state) do
          {:ok, %{x: 0, y: 0, z: 30}, state}
        end

        @impl Drone.Adapter
        def disconnect(_state) do
          :ok
        end
      end

  See `docs/adapter_authoring.md` for a complete guide.
  """

  @type state :: term()

  @callback connect(opts :: keyword()) ::
              {:ok, state()}
              | {:error, term()}

  @callback command(state :: state(), command :: Drone.Command.t()) ::
              {:ok, reply :: term(), new_state :: state()}
              | {:error, reason :: term(), new_state :: state()}

  @callback telemetry(state :: state()) ::
              {:ok, map(), state()}
              | {:error, term(), state()}

  @callback disconnect(state :: state()) :: :ok

  @optional_callbacks [disconnect: 1]

  @doc """
  Returns the adapter module for a given adapter identifier.

  Accepts an atom (`:sim`, `:tello`) or a module directly.
  """
  @spec resolve(atom() | module()) :: {:ok, module()} | {:error, :unknown_adapter}
  def resolve(:sim), do: {:ok, Drone.Adapters.Sim}
  def resolve(:tello), do: {:ok, Drone.Adapters.Tello}
  def resolve(module) when is_atom(module), do: {:ok, module}
  def resolve(_), do: {:error, :unknown_adapter}
end
