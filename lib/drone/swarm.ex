defmodule Drone.Swarm do
  @moduledoc """
  Coordinator for a named set of drones.

  A swarm owns **membership** and **group operations**. Each member remains a
  normal `Drone.Vehicle` under `Drone.Supervisor`. Per-drone `Drone.Safety`
  still gates every command; the swarm adds plan-time formation separation
  and fail-fast fan-out for coordinated commands.

  Formations are one-shot geometric planners (`Drone.Formation`), not
  continuous flocking controllers.

  ## Quick start

      {:ok, swarm} =
        Drone.Swarm.start_link(
          name: :advisors,
          members: [
            {:good, adapter: :sim, initial_x: 0, initial_y: 0},
            {:bad, adapter: :sim, initial_x: 0, initial_y: 0}
          ],
          spacing_cm: 100,
          min_separation_cm: 80
        )

      {:ok, _} = Drone.Swarm.connect_sdk(swarm)
      {:ok, _} = Drone.Swarm.takeoff(swarm)
      {:ok, _} = Drone.Swarm.run(swarm, :front)
      {:ok, _} = Drone.Swarm.land(swarm)
      :ok = Drone.Swarm.stop(swarm)

  Member-list sugar (anonymous swarm, returns a pid):

      {:ok, swarm} =
        Drone.Swarm.start_link([
          {:left, adapter: :sim, initial_x: -50},
          {:right, adapter: :sim, initial_x: 50}
        ])

  ## Result shapes

  Coordinated ops return a map of per-member outcomes:

      {:ok, %{good: :ok, bad: :ok}}
      {:error, :partial, %{good: :ok, bad: {:error, {:safety, :max_altitude}}}}

  Default policy is **fail-fast**: stop issuing further member commands after
  the first error. Already-completed members are not undone; call `land/1` or
  `emergency/1` explicitly.

  ## See also

  * `Drone.Formation` — formation planners
  * `docs/swarm.md` — user guide
  * `docs/design/v0_2_0_deferred.md` — deferred flocking / closed-loop work
  """

  use GenServer

  alias Drone.{Formation, Mission, Telemetry}

  @typedoc """
  Handle used to address a running swarm.

  * `atom()` — registered name passed as `:name` to `start_link/1`
    (looked up via `Drone.Swarm.Registry`), e.g. `:advisors`
  * `pid()` — process id of an anonymous swarm

  ## Examples

      :advisors
      #PID<0.123.0>
  """
  @type swarm :: atom() | pid()

  @typedoc """
  Outcome for a single swarm member after a coordinated operation.

  * `:ok` — command succeeded with no payload
  * `{:ok, term()}` — succeeded with a value (e.g. mission reply list)
  * `{:error, term()}` — failed; reason may be `{:safety, atom()}`,
    `:simulated_failure`, `:not_connected`, etc.

  ## Examples

      :ok
      {:ok, [:ok, :ok]}
      {:error, {:safety, :max_altitude}}
      {:error, :simulated_failure}
  """
  @type member_result :: :ok | {:ok, term()} | {:error, term()}

  @typedoc """
  Map of member name → per-member result for a coordinated operation.

  Keys are the drone names from membership (atoms such as `:good`, `:left`).

  ## Example

      %{good: :ok, bad: {:error, {:safety, :max_altitude}}}
  """
  @type results :: %{optional(atom()) => member_result()}

  @typedoc """
  Options accepted by `start_link/1` after normalization.

  ## Fields / keys

  | Key | Type | Default | Meaning |
  |-----|------|---------|---------|
  | `:name` | `atom()` | none | Register swarm in `Drone.Swarm.Registry` |
  | `:members` | `[{atom(), keyword()}]` | required | Ordered member list |
  | `:spacing_cm` | `pos_integer()` | `100` | Neighbor spacing for formations |
  | `:min_separation_cm` | `pos_integer()` | `80` | Plan-time Separate check |
  | `:heading_deg` | `integer()` | `0` | Formation travel heading (yaw 0 = +Y) |
  | `:policy` | `:fail_fast` | `:fail_fast` | Fan-out policy (only fail-fast shipped) |

  Each member keyword list is passed to `Drone.connect/2` (plus `:name`).
  Common member opts: `:adapter` (`:sim` \| `:tello` \| module),
  `:initial_x`, `:initial_y`, `:initial_z`, `:initial_yaw`, `:safety`,
  simulator failure injection opts.

  ## Example

      [
        name: :patrol,
        members: [
          {:alpha, adapter: :sim, initial_x: -50, safety: [indoor: true]},
          {:bravo, adapter: :sim, initial_x: 50}
        ],
        spacing_cm: 120,
        min_separation_cm: 100,
        heading_deg: 0
      ]
  """
  @type start_opts :: keyword()

  @default_spacing_cm 100
  @default_min_separation_cm 80

  @doc """
  Returns the child specification used by `Drone.Swarm.Supervisor`.

  ## Parameters

    * `opts` (`keyword()`) — swarm start options (see `t:start_opts/0`)

  ## Returns

  A supervisor child spec map with `:temporary` restart.

  ## Example

      Drone.Swarm.child_spec(name: :demo, members: [{:a, adapter: :sim}, {:b, adapter: :sim}])
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    opts = normalize_opts(opts)
    id = Keyword.get(opts, :name) || {:swarm, System.unique_integer([:positive])}

    %{
      id: id,
      start: {__MODULE__, :start_genserver, [opts]},
      restart: :temporary,
      type: :worker
    }
  end

  @doc """
  Starts a supervised swarm and connects all members.

  Accepts either:

  1. A keyword list with `:members` and optional swarm options
  2. A bare member list `[{name, opts}, ...]` (prompt-style sugar)

  Members are started via `Drone.connect/2` under `Drone.Supervisor`.
  The swarm process itself is started under `Drone.Swarm.Supervisor`.

  ## Parameters

    * `arg` (`keyword() | [{atom(), keyword()}]`) — start options or member list

  ## Returns

    * `{:ok, swarm()}` — swarm name when `:name` was given, otherwise the pid
    * `{:error, :name_already_taken}` — swarm name already registered
    * `{:error, term()}` — member connect failure or supervisor error

  ## Examples

      {:ok, :advisors} =
        Drone.Swarm.start_link(
          name: :advisors,
          members: [
            {:good, adapter: :sim, initial_x: 0},
            {:bad, adapter: :sim, initial_x: 0, safety: [max_altitude_cm: 50]}
          ]
        )

      {:ok, pid} =
        Drone.Swarm.start_link([
          {:left, adapter: :sim, initial_x: -50},
          {:right, adapter: :sim, initial_x: 50}
        ])
  """
  @spec start_link(keyword() | [{atom(), keyword()}]) ::
          {:ok, swarm()} | {:error, term()}
  def start_link(arg) do
    opts = normalize_opts(arg)

    case Drone.Swarm.Supervisor.start_swarm(opts) do
      {:ok, pid} ->
        {:ok, Keyword.get(opts, :name, pid)}

      {:error, {:already_started, _pid}} ->
        {:error, :name_already_taken}

      {:error, _} = err ->
        err
    end
  end

  @doc false
  @spec start_genserver(keyword()) :: GenServer.on_start()
  def start_genserver(opts) do
    GenServer.start_link(__MODULE__, opts, name_opts(opts))
  end

  @doc """
  Looks up a named swarm process.

  ## Parameters

    * `name` (`atom()`) — registry key, e.g. `:advisors`

  ## Returns

    * `pid()` when registered
    * `nil` when not found

  ## Example

      pid = Drone.Swarm.whereis(:advisors)
  """
  @spec whereis(atom()) :: pid() | nil
  def whereis(name) when is_atom(name) do
    case Registry.lookup(Drone.Swarm.Registry, name) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Returns the ordered list of member drone names.

  ## Parameters

    * `swarm` (`t:swarm/0`) — swarm name or pid

  ## Returns

  A list of atoms in membership order, e.g. `[:good, :bad]`.

  ## Example

      [:good, :bad] = Drone.Swarm.members(:advisors)
  """
  @spec members(swarm()) :: [atom()] | {:error, :not_found}
  def members(swarm), do: call(swarm, :members)

  @doc """
  Sends SDK-mode activation to every member (fail-fast).

  ## Parameters

    * `swarm` (`t:swarm/0`) — swarm name or pid

  ## Returns

    * `{:ok, results()}` — all members entered SDK mode
    * `{:error, :partial, results()}` — stopped after first failure

  ## Example

      {:ok, %{good: :ok, bad: :ok}} = Drone.Swarm.connect_sdk(:advisors)
  """
  @spec connect_sdk(swarm()) ::
          {:ok, results()} | {:error, :partial, results()} | {:error, :not_found}
  def connect_sdk(swarm), do: call(swarm, {:fan_out, :connect_sdk})

  @doc """
  Coordinated takeoff for every member (fail-fast).

  Members must already be in SDK mode (`connect_sdk/1`).

  ## Parameters

    * `swarm` (`t:swarm/0`) — swarm name or pid

  ## Returns

    * `{:ok, results()}`
    * `{:error, :partial, results()}`

  ## Example

      {:ok, _} = Drone.Swarm.takeoff(:advisors)
  """
  @spec takeoff(swarm()) ::
          {:ok, results()} | {:error, :partial, results()} | {:error, :not_found}
  def takeoff(swarm), do: call(swarm, {:fan_out, :takeoff})

  @doc """
  Coordinated land for every member (fail-fast).

  ## Parameters

    * `swarm` (`t:swarm/0`) — swarm name or pid

  ## Returns

    * `{:ok, results()}`
    * `{:error, :partial, results()}`

  ## Example

      {:ok, _} = Drone.Swarm.land(:advisors)
  """
  @spec land(swarm()) ::
          {:ok, results()} | {:error, :partial, results()} | {:error, :not_found}
  def land(swarm), do: call(swarm, {:fan_out, :land})

  @doc """
  Emergency-stops every member (best-effort; does not fail-fast).

  Continues through all members even if one fails. Bypasses normal safety
  on each vehicle.

  ## Parameters

    * `swarm` (`t:swarm/0`) — swarm name or pid

  ## Returns

    * `{:ok, results()}` — always returns the full per-member map when the
      swarm exists

  ## Example

      {:ok, %{good: :ok, bad: :ok}} = Drone.Swarm.emergency(:advisors)
  """
  @spec emergency(swarm()) :: {:ok, results()} | {:error, :not_found}
  def emergency(swarm), do: call(swarm, :emergency)

  @doc """
  Returns a map of telemetry snapshots for every member.

  ## Parameters

    * `swarm` (`t:swarm/0`) — swarm name or pid

  ## Returns

    * `{:ok, %{atom() => map()}}` — keys are member names; values include
      at least `:x`, `:y`, `:z`, `:yaw`, `:battery`, `:flying`, `:mode`
    * `{:error, {member :: atom(), reason :: term()}}` — first telemetry failure
    * `{:error, :not_found}` — unknown swarm

  ## Example

      {:ok, tel} = Drone.Swarm.telemetry(:advisors)
      tel.good.flying
      #=> true
  """
  @spec telemetry(swarm()) ::
          {:ok, %{atom() => map()}} | {:error, term()}
  def telemetry(swarm), do: call(swarm, :telemetry)

  @doc """
  Runs a formation, a per-drone mission map, or a custom function.

  ## Parameters

    * `swarm` (`t:swarm/0`) — swarm name or pid
    * `target` — one of:
      * `Drone.Formation.formation()` — e.g. `:front`, `:vee`, `:circle`
      * `%{atom() => Drone.Mission.t()}` — per-member missions (fail-fast order
        follows membership, then any extra keys)
      * `(map() -> term())` — function receiving `%{name => name}` member map;
        return `:ok`, `{:ok, term()}`, or `{:error, term()}`

  ## Returns

    * `{:ok, results()}` — all members succeeded (or custom function returned ok)
    * `{:error, :partial, results()}` — fail-fast stop during mission execution
    * `{:error, reason}` — plan-time error such as `:separation_violation`,
      `:too_few_drones`, `:unsupported_formation`, `:unsupported_run_target`
    * `{:error, :not_found}` — unknown swarm

  ## Examples

      {:ok, _} = Drone.Swarm.run(swarm, :front)

      good = Drone.Mission.new() |> Drone.Mission.move(:forward, 40)
      bad = Drone.Mission.new() |> Drone.Mission.move(:up, 200)
      {:error, :partial, results} = Drone.Swarm.run(swarm, %{good: good, bad: bad})

      {:ok, _} =
        Drone.Swarm.run(swarm, fn members ->
          Enum.each(members, fn {_k, name} -> Drone.hover(name, seconds: 1) end)
          :ok
        end)
  """
  @spec run(
          swarm(),
          Formation.formation() | %{atom() => Mission.t()} | (map() -> term())
        ) ::
          {:ok, results()}
          | {:error, term()}
          | {:error, :partial, results()}
  def run(swarm, target), do: call(swarm, {:run, target})

  @doc """
  Stops the swarm process.

  By default disconnects all member vehicles. Pass `disconnect: false` to
  leave vehicles running after the coordinator exits.

  ## Parameters

    * `swarm` (`t:swarm/0`) — swarm name or pid
    * `opts` (`keyword()`) — options:
      * `:disconnect` (`boolean()`, default `true`) — disconnect members

  ## Returns

    * `:ok`
    * `{:error, :not_found}`

  ## Examples

      :ok = Drone.Swarm.stop(:advisors)
      :ok = Drone.Swarm.stop(swarm, disconnect: false)
  """
  @spec stop(swarm(), keyword()) :: :ok | {:error, term()}
  def stop(swarm, opts \\ []) do
    call(swarm, {:stop, opts})
  end

  @impl GenServer
  def init(opts) do
    members = Keyword.fetch!(opts, :members)
    name = Keyword.get(opts, :name)

    case connect_members(members) do
      {:ok, drones} ->
        state = %{
          name: name,
          members: members,
          drones: drones,
          spacing_cm: Keyword.get(opts, :spacing_cm, @default_spacing_cm),
          min_separation_cm: Keyword.get(opts, :min_separation_cm, @default_min_separation_cm),
          heading_deg: Keyword.get(opts, :heading_deg, 0),
          policy: Keyword.get(opts, :policy, :fail_fast)
        }

        Telemetry.emit_swarm_start(name, drones)
        {:ok, state}

      {:error, reason, connected} ->
        Enum.each(connected, &Drone.disconnect/1)
        {:stop, reason}
    end
  end

  @impl GenServer
  def terminate(_reason, %{name: name, drones: drones} = state) do
    Telemetry.emit_swarm_stop(name, drones)

    if Map.get(state, :disconnect_on_stop, true) do
      Enum.each(drones, fn drone ->
        try do
          Drone.disconnect(drone)
        rescue
          _ -> :ok
        catch
          :exit, _ -> :ok
        end
      end)
    end

    :ok
  end

  @impl GenServer
  def handle_call(:members, _from, state) do
    {:reply, state.drones, state}
  end

  def handle_call({:fan_out, op}, _from, state) do
    start = System.monotonic_time()
    Telemetry.emit_swarm_command_start(state.name, state.drones, op)

    result = fan_out_fail_fast(state.drones, &apply_member_op(op, &1))
    duration = System.monotonic_time() - start

    case result do
      {:ok, _} = ok ->
        Telemetry.emit_swarm_command_stop(state.name, state.drones, op, duration)
        {:reply, ok, state}

      {:error, :partial, _} = err ->
        Telemetry.emit_swarm_command_error(state.name, state.drones, op, :partial, duration)
        {:reply, err, state}
    end
  end

  def handle_call(:emergency, _from, state) do
    Telemetry.emit_swarm_emergency(state.name, state.drones)

    results =
      Map.new(state.drones, fn name ->
        {name, normalize_result(Drone.emergency(name))}
      end)

    {:reply, {:ok, results}, state}
  end

  def handle_call(:telemetry, _from, state) do
    results =
      Enum.reduce_while(state.drones, %{}, fn name, acc ->
        case Drone.telemetry(name) do
          {:ok, data} -> {:cont, Map.put(acc, name, data)}
          {:error, reason} -> {:halt, {:error, {name, reason}}}
        end
      end)

    case results do
      {:error, _} = err -> {:reply, err, state}
      map -> {:reply, {:ok, map}, state}
    end
  end

  def handle_call({:run, target}, _from, state) do
    start = System.monotonic_time()
    Telemetry.emit_swarm_command_start(state.name, state.drones, :run)

    result = do_run(target, state)
    duration = System.monotonic_time() - start

    case result do
      {:ok, _} = ok ->
        Telemetry.emit_swarm_command_stop(state.name, state.drones, :run, duration)
        {:reply, ok, state}

      {:error, :partial, _} = err ->
        Telemetry.emit_swarm_command_error(state.name, state.drones, :run, :partial, duration)
        {:reply, err, state}

      {:error, reason} = err ->
        Telemetry.emit_swarm_command_error(state.name, state.drones, :run, reason, duration)
        {:reply, err, state}
    end
  end

  def handle_call({:stop, opts}, _from, state) do
    disconnect? = Keyword.get(opts, :disconnect, true)
    new_state = Map.put(state, :disconnect_on_stop, disconnect?)

    if disconnect? do
      Enum.each(state.drones, fn drone ->
        _ = Drone.disconnect(drone)
      end)
    end

    {:stop, :normal, :ok, %{new_state | disconnect_on_stop: false}}
  end

  defp do_run(fun, state) when is_function(fun, 1) do
    members = Map.new(state.drones, &{&1, &1})

    case fun.(members) do
      :ok -> {:ok, Map.new(state.drones, &{&1, :ok})}
      {:ok, _} = ok -> ok
      {:error, _} = err -> err
      other -> {:ok, %{result: other}}
    end
  end

  defp do_run(missions, state) when is_map(missions) do
    ordered =
      Enum.filter(state.drones, &Map.has_key?(missions, &1)) ++
        Enum.reject(Map.keys(missions), &(&1 in state.drones))

    fan_out_fail_fast(ordered, fn name ->
      case Map.fetch(missions, name) do
        {:ok, %Mission{} = mission} -> run_mission(mission, name)
        :error -> {:error, :missing_mission}
      end
    end)
  end

  defp do_run(formation, state) when is_atom(formation) do
    with {:ok, positions} <- member_positions(state.drones),
         {:ok, missions} <-
           Formation.plan(formation, %{
             drones: state.drones,
             positions: positions,
             heading_deg: state.heading_deg,
             spacing_cm: state.spacing_cm,
             min_separation_cm: state.min_separation_cm
           }) do
      do_run(missions, state)
    end
  end

  defp do_run(_other, _state), do: {:error, :unsupported_run_target}

  defp member_positions(drones) do
    Enum.reduce_while(drones, %{}, fn name, acc ->
      case Drone.telemetry(name) do
        {:ok, %{x: x, y: y} = tel} ->
          {:cont,
           Map.put(acc, name, %{
             x: x,
             y: y,
             z: Map.get(tel, :z, 0),
             yaw: Map.get(tel, :yaw, 0)
           })}

        {:error, reason} ->
          {:halt, {:error, {name, reason}}}
      end
    end)
    |> case do
      {:error, _} = err -> err
      map -> {:ok, map}
    end
  end

  defp run_mission(%Mission{} = mission, name) do
    case Mission.run(mission, name) do
      {:ok, results} -> {:ok, results}
      {:error, _cmd, reason} -> {:error, reason}
    end
  end

  defp apply_member_op(:connect_sdk, name), do: normalize_result(Drone.connect_sdk(name))
  defp apply_member_op(:takeoff, name), do: normalize_result(Drone.takeoff(name))
  defp apply_member_op(:land, name), do: normalize_result(Drone.land(name))

  defp normalize_result(:ok), do: :ok
  defp normalize_result({:ok, _value}), do: :ok
  defp normalize_result({:error, :safety, reason}), do: {:error, {:safety, reason}}
  defp normalize_result({:error, reason}), do: {:error, reason}

  defp fan_out_fail_fast(drones, fun) do
    {status, results} =
      Enum.reduce_while(drones, {:ok, %{}}, fn name, {:ok, acc} ->
        case fun.(name) do
          :ok ->
            {:cont, {:ok, Map.put(acc, name, :ok)}}

          {:ok, value} ->
            {:cont, {:ok, Map.put(acc, name, {:ok, value})}}

          {:error, _} = err ->
            {:halt, {:error, Map.put(acc, name, err)}}
        end
      end)

    case status do
      :ok -> {:ok, results}
      :error -> {:error, :partial, results}
    end
  end

  defp connect_members(members) do
    Enum.reduce_while(members, {:ok, []}, fn {name, member_opts}, {:ok, connected} ->
      adapter = Keyword.get(member_opts, :adapter, :sim)
      connect_opts = member_opts |> Keyword.put(:name, name) |> Keyword.delete(:adapter)

      case Drone.connect(adapter, connect_opts) do
        {:ok, ^name} ->
          {:cont, {:ok, [name | connected]}}

        {:error, reason} ->
          {:halt, {:error, {name, reason}, Enum.reverse(connected)}}
      end
    end)
    |> case do
      {:ok, drones} -> {:ok, Enum.reverse(drones)}
      {:error, reason, connected} -> {:error, reason, connected}
    end
  end

  defp call(swarm, message) do
    case resolve(swarm) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, message, 60_000)
    end
  end

  defp resolve(pid) when is_pid(pid), do: pid
  defp resolve(name) when is_atom(name), do: whereis(name)

  defp name_opts(opts) do
    case Keyword.get(opts, :name) do
      nil -> []
      name -> [name: via_tuple(name)]
    end
  end

  defp via_tuple(name) do
    {:via, Registry, {Drone.Swarm.Registry, name}}
  end

  defp normalize_opts(members) when is_list(members) do
    if keyword_members?(members) do
      members
      |> Keyword.put_new(:spacing_cm, @default_spacing_cm)
      |> Keyword.put_new(:min_separation_cm, @default_min_separation_cm)
      |> normalize_member_entries()
    else
      [
        members: normalize_member_list(members),
        spacing_cm: @default_spacing_cm,
        min_separation_cm: @default_min_separation_cm
      ]
    end
  end

  defp keyword_members?(list) do
    Keyword.keyword?(list) and Keyword.has_key?(list, :members)
  end

  defp normalize_member_entries(opts) do
    members =
      opts
      |> Keyword.fetch!(:members)
      |> normalize_member_list()

    Keyword.put(opts, :members, members)
  end

  defp normalize_member_list(members) do
    Enum.map(members, fn
      {name, opts} when is_atom(name) and is_list(opts) -> {name, opts}
      name when is_atom(name) -> {name, [adapter: :sim]}
    end)
  end
end
