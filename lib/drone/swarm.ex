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
        Drone.Swarm.start(
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
        Drone.Swarm.start([
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

  `emergency/1` fans out from the caller process using a membership table, so
  it is not blocked by an in-flight `run/2` or other coordinated call.

  ## See also

  * `Drone.Formation` — formation planners
  * `docs/swarm.md` — user guide
  * `docs/design/v0_2_0_deferred.md` — deferred flocking / closed-loop work
  """

  use GenServer

  alias Drone.{Formation, Mission, Telemetry}

  @members_table Drone.Swarm.Members
  @default_spacing_cm 100
  @default_min_separation_cm 80
  @default_timeout 60_000

  @typedoc """
  Handle used to address a running swarm.

  * `atom()` — registered name passed as `:name` to `start/1`
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
  Options accepted by `start/1` after normalization.

  ## Fields / keys

  | Key | Type | Default | Meaning |
  |-----|------|---------|---------|
  | `:name` | `atom()` | none | Register swarm in `Drone.Swarm.Registry` |
  | `:members` | `[{atom(), keyword()}]` | required | Ordered member list |
  | `:spacing_cm` | `pos_integer()` | `100` | Neighbor spacing for formations |
  | `:min_separation_cm` | `pos_integer()` | `80` | Plan-time Separate check |
  | `:heading_deg` | `integer()` | `0` | Formation travel heading (yaw 0 = +Y) |
  | `:timeout` | `timeout()` | `60_000` | Default `GenServer.call` timeout for ops |

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
  @type start_opts :: [
          {:name, atom()}
          | {:members, [{atom(), keyword()}]}
          | {:spacing_cm, pos_integer()}
          | {:min_separation_cm, pos_integer()}
          | {:heading_deg, integer()}
          | {:timeout, timeout()}
        ]

  @doc false
  @spec members_table() :: atom()
  def members_table, do: @members_table

  @doc """
  Returns the child specification used by `Drone.Swarm.Supervisor`.

  ## Parameters

    * `opts` (`t:start_opts/0`) — swarm start options

  ## Returns

  A supervisor child spec map with `:temporary` restart and a shutdown
  allowance for member disconnects.

  ## Example

      Drone.Swarm.child_spec(name: :demo, members: [{:a, adapter: :sim}, {:b, adapter: :sim}])
  """
  @spec child_spec(start_opts()) :: Supervisor.child_spec()
  def child_spec(opts) do
    opts = normalize_opts(opts)

    %{
      id: __MODULE__,
      start: {__MODULE__, :start_genserver, [opts]},
      restart: :temporary,
      type: :worker,
      shutdown: 10_000
    }
  end

  @doc """
  Starts a supervised swarm and connects all members.

  Accepts either:

  1. A keyword list with `:members` and optional swarm options
  2. A bare member list `[{name, opts}, ...]` or `[name, ...]` (defaults to `:sim`)

  Members are started via `Drone.connect/2` under `Drone.Supervisor`.
  The swarm process itself is started under `Drone.Swarm.Supervisor`.

  Like `Drone.connect/2`, this returns a swarm **handle** (`:name` or `pid`)
  and does not link the caller. Use `child_spec/1` under your own supervisor
  when you need OTP linking/restart semantics.

  ## Parameters

    * `arg` (`t:start_opts/0 | [{atom(), keyword()}] | [atom()]`) — start options or member list

  ## Returns

    * `{:ok, swarm()}` — swarm name when `:name` was given, otherwise the pid
    * `{:error, :name_already_taken}` — swarm name already registered
    * `{:error, term()}` — member connect failure or supervisor error

  ## Examples

      {:ok, :advisors} =
        Drone.Swarm.start(
          name: :advisors,
          members: [
            {:good, adapter: :sim, initial_x: 0},
            {:bad, adapter: :sim, initial_x: 0, safety: [max_altitude_cm: 50]}
          ]
        )

      {:ok, pid} =
        Drone.Swarm.start([
          {:left, adapter: :sim, initial_x: -50},
          {:right, adapter: :sim, initial_x: 50}
        ])
  """
  @spec start(start_opts() | [{atom(), keyword()}] | [atom()]) ::
          {:ok, swarm()} | {:error, term()}
  def start(arg) do
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

    * `{:ok, [atom()]}` — membership order, e.g. `{:ok, [:good, :bad]}`
    * `{:error, :not_found}` — unknown swarm

  ## Example

      {:ok, [:good, :bad]} = Drone.Swarm.members(:advisors)
  """
  @spec members(swarm()) :: {:ok, [atom()]} | {:error, :not_found}
  def members(swarm), do: call(swarm, :members)

  @doc """
  Sends SDK-mode activation to every member (fail-fast).

  ## Parameters

    * `swarm` (`t:swarm/0`) — swarm name or pid
    * `opts` (`keyword()`) — `:timeout` overrides the swarm default

  ## Returns

    * `{:ok, results()}` — all members entered SDK mode
    * `{:error, :partial, results()}` — stopped after first failure
    * `{:error, :not_found}`

  ## Example

      {:ok, %{good: :ok, bad: :ok}} = Drone.Swarm.connect_sdk(:advisors)
  """
  @spec connect_sdk(swarm(), keyword()) ::
          {:ok, results()} | {:error, :partial, results()} | {:error, :not_found}
  def connect_sdk(swarm, opts \\ []), do: call(swarm, {:fan_out, :connect_sdk}, opts)

  @doc """
  Coordinated takeoff for every member (fail-fast).

  Members must already be in SDK mode (`connect_sdk/1`).

  ## Parameters

    * `swarm` (`t:swarm/0`) — swarm name or pid
    * `opts` (`keyword()`) — `:timeout` overrides the swarm default

  ## Returns

    * `{:ok, results()}`
    * `{:error, :partial, results()}`
    * `{:error, :not_found}`

  ## Example

      {:ok, _} = Drone.Swarm.takeoff(:advisors)
  """
  @spec takeoff(swarm(), keyword()) ::
          {:ok, results()} | {:error, :partial, results()} | {:error, :not_found}
  def takeoff(swarm, opts \\ []), do: call(swarm, {:fan_out, :takeoff}, opts)

  @doc """
  Coordinated land for every member (fail-fast).

  ## Parameters

    * `swarm` (`t:swarm/0`) — swarm name or pid
    * `opts` (`keyword()`) — `:timeout` overrides the swarm default

  ## Returns

    * `{:ok, results()}`
    * `{:error, :partial, results()}`
    * `{:error, :not_found}`

  ## Example

      {:ok, _} = Drone.Swarm.land(:advisors)
  """
  @spec land(swarm(), keyword()) ::
          {:ok, results()} | {:error, :partial, results()} | {:error, :not_found}
  def land(swarm, opts \\ []), do: call(swarm, {:fan_out, :land}, opts)

  @doc """
  Emergency-stops every member (best-effort; does not fail-fast).

  Fans out **from the caller process** using the swarm membership table, so
  this is not queued behind an in-flight `run/2`, `takeoff/1`, or other
  coordinator call. Continues through all members even if one fails. Bypasses
  normal safety on each vehicle.

  ## Parameters

    * `swarm` (`t:swarm/0`) — swarm name or pid

  ## Returns

    * `{:ok, results()}` — always returns the full per-member map when the
      swarm exists
    * `{:error, :not_found}`

  ## Example

      {:ok, %{good: :ok, bad: :ok}} = Drone.Swarm.emergency(:advisors)
  """
  @spec emergency(swarm()) :: {:ok, results()} | {:error, :not_found}
  def emergency(swarm) do
    case lookup_members(swarm) do
      {:ok, name, drones} ->
        Telemetry.emit_swarm_emergency(name, drones)

        results =
          Map.new(drones, fn member ->
            {member, normalize_result(Drone.emergency(member))}
          end)

        {:ok, results}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Returns a map of telemetry snapshots for every member.

  ## Parameters

    * `swarm` (`t:swarm/0`) — swarm name or pid
    * `opts` (`keyword()`) — `:timeout` overrides the swarm default

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
  @spec telemetry(swarm(), keyword()) ::
          {:ok, %{atom() => map()}} | {:error, term()}
  def telemetry(swarm, opts \\ []), do: call(swarm, :telemetry, opts)

  @doc """
  Runs a formation, a per-drone mission map, or a custom function.

  When `target` is a formation atom, `opts` may include formation planner
  options (`:heading_deg`, `:spacing_cm`, `:min_separation_cm`, `:leader`,
  `:origin`, `:side`, `:radius_cm`, `:columns`) which override swarm defaults.
  Use `:timeout` to override the call timeout.

  ## Parameters

    * `swarm` (`t:swarm/0`) — swarm name or pid
    * `target` — one of:
      * `Drone.Formation.formation()` — e.g. `:front`, `:vee`, `:circle`
      * `%{atom() => Drone.Mission.t()}` — per-member missions (membership order;
        unknown keys are rejected before any flight)
      * `(map() -> term())` — function receiving `%{name => name}` member map;
        must return `:ok`, `{:ok, term()}`, or `{:error, term()}`
    * `opts` (`keyword()`) — formation and/or `:timeout` options

  ## Returns

    * `{:ok, results()}` — all members succeeded (or custom function returned ok)
    * `{:error, :partial, results()}` — fail-fast stop during mission execution
    * `{:error, reason}` — plan-time error such as `:separation_violation`,
      `:too_few_drones`, `:unsupported_formation`, `:unsupported_run_target`,
      `{:unknown_members, [atom()]}`, `{:invalid_run_result, term()}`
    * `{:error, :not_found}` — unknown swarm

  ## Examples

      {:ok, _} = Drone.Swarm.run(swarm, :front)
      {:ok, _} = Drone.Swarm.run(swarm, :echelon, side: :left, heading_deg: 90)

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
          Formation.formation() | %{atom() => Mission.t()} | (map() -> term()),
          keyword()
        ) ::
          {:ok, results()}
          | {:error, term()}
          | {:error, :partial, results()}
  def run(swarm, target, opts \\ []) do
    {timeout_opts, formation_opts} = Keyword.split(opts, [:timeout])
    call(swarm, {:run, target, formation_opts}, timeout_opts)
  end

  @doc """
  Stops the swarm process.

  By default disconnects all member vehicles. Pass `disconnect: false` to
  leave vehicles running after the coordinator exits.

  ## Parameters

    * `swarm` (`t:swarm/0`) — swarm name or pid
    * `opts` (`keyword()`) — options:
      * `:disconnect` (`boolean()`, default `true`) — disconnect members
      * `:timeout` (`timeout()`) — call timeout

  ## Returns

    * `:ok`
    * `{:error, :not_found}`

  ## Examples

      :ok = Drone.Swarm.stop(:advisors)
      :ok = Drone.Swarm.stop(swarm, disconnect: false)
  """
  @spec stop(swarm(), keyword()) :: :ok | {:error, term()}
  def stop(swarm, opts \\ []) do
    call(swarm, {:stop, opts}, opts)
  end

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)

    members = Keyword.fetch!(opts, :members)
    name = Keyword.get(opts, :name)

    case connect_members(members) do
      {:ok, drones} ->
        member_pids = link_members(drones)

        state = %{
          name: name,
          drones: drones,
          member_pids: member_pids,
          spacing_cm: Keyword.get(opts, :spacing_cm, @default_spacing_cm),
          min_separation_cm: Keyword.get(opts, :min_separation_cm, @default_min_separation_cm),
          heading_deg: Keyword.get(opts, :heading_deg, 0),
          timeout: Keyword.get(opts, :timeout, @default_timeout),
          disconnect_on_stop: true
        }

        :ets.insert(@members_table, {self(), {name, drones, state.timeout}})
        Telemetry.emit_swarm_start(name, drones)
        {:ok, state}

      {:error, reason, connected} ->
        Enum.each(connected, &safe_disconnect/1)
        {:stop, reason}
    end
  end

  @impl GenServer
  def terminate(reason, %{name: name, drones: drones} = state) do
    Telemetry.emit_swarm_stop(name, drones, reason)

    if Map.get(state, :disconnect_on_stop, true) do
      Enum.each(drones, &safe_disconnect/1)
    else
      Enum.each(Map.keys(Map.get(state, :member_pids, %{})), &Process.unlink/1)
    end

    :ets.delete(@members_table, self())
    :ok
  end

  @impl GenServer
  def handle_call(:members, _from, state) do
    {:reply, {:ok, state.drones}, state}
  end

  def handle_call({:fan_out, op}, _from, state) do
    reply_with_telemetry(state, op, fn ->
      fan_out_fail_fast(state.drones, &apply_member_op(op, &1))
    end)
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

  def handle_call({:run, target, formation_opts}, _from, state) do
    reply_with_telemetry(state, :run, fn ->
      do_run(target, state, formation_opts)
    end)
  end

  def handle_call({:stop, opts}, _from, state) do
    disconnect? = Keyword.get(opts, :disconnect, true)
    {:stop, :normal, :ok, %{state | disconnect_on_stop: disconnect?}}
  end

  @impl GenServer
  def handle_info({:EXIT, pid, _reason}, state) do
    case Map.pop(state.member_pids, pid) do
      {nil, _} ->
        {:noreply, state}

      {name, member_pids} ->
        drones = List.delete(state.drones, name)
        :ets.insert(@members_table, {self(), {state.name, drones, state.timeout}})
        {:noreply, %{state | drones: drones, member_pids: member_pids}}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp do_run(%Mission{}, _state, _opts), do: {:error, :unsupported_run_target}

  defp do_run(fun, state, _opts) when is_function(fun, 1) do
    members = Map.new(state.drones, &{&1, &1})

    case fun.(members) do
      :ok -> {:ok, Map.new(state.drones, &{&1, :ok})}
      {:ok, _} = ok -> ok
      {:error, _} = err -> err
      {:error, :safety, reason} -> {:error, {:safety, reason}}
      other -> {:error, {:invalid_run_result, other}}
    end
  end

  defp do_run(missions, state, _opts) when is_map(missions) do
    unknown = Map.keys(missions) -- state.drones

    cond do
      unknown != [] ->
        {:error, {:unknown_members, unknown}}

      not Enum.all?(missions, fn {_k, v} -> match?(%Mission{}, v) end) ->
        {:error, :unsupported_run_target}

      true ->
        ordered = Enum.filter(state.drones, &Map.has_key?(missions, &1))

        fan_out_fail_fast(ordered, fn name ->
          run_mission(Map.fetch!(missions, name), name)
        end)
    end
  end

  defp do_run(formation, state, opts) when is_atom(formation) do
    plan_opts =
      %{
        drones: state.drones,
        heading_deg: Keyword.get(opts, :heading_deg, state.heading_deg),
        spacing_cm: Keyword.get(opts, :spacing_cm, state.spacing_cm),
        min_separation_cm: Keyword.get(opts, :min_separation_cm, state.min_separation_cm)
      }
      |> maybe_put(opts, :leader)
      |> maybe_put(opts, :origin)
      |> maybe_put(opts, :side)
      |> maybe_put(opts, :radius_cm)
      |> maybe_put(opts, :columns)

    with {:ok, positions} <- member_positions(state.drones),
         {:ok, missions} <- Formation.plan(formation, Map.put(plan_opts, :positions, positions)) do
      do_run(missions, state, [])
    end
  end

  defp do_run(_other, _state, _opts), do: {:error, :unsupported_run_target}

  defp maybe_put(map, opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> Map.put(map, key, value)
      :error -> map
    end
  end

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

        {:ok, _tel} ->
          {:halt, {:error, {name, :position_unavailable}}}

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

  defp reply_with_telemetry(state, op, fun) do
    start = System.monotonic_time()
    Telemetry.emit_swarm_command_start(state.name, state.drones, op)
    result = fun.()
    duration = System.monotonic_time() - start

    case result do
      {:ok, _} = ok ->
        Telemetry.emit_swarm_command_stop(state.name, state.drones, op, duration)
        {:reply, ok, state}

      {:error, :partial, _} = err ->
        Telemetry.emit_swarm_command_error(state.name, state.drones, op, :partial, duration)
        {:reply, err, state}

      {:error, reason} = err ->
        Telemetry.emit_swarm_command_error(state.name, state.drones, op, reason, duration)
        {:reply, err, state}
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

  defp link_members(drones) do
    Enum.reduce(drones, %{}, fn name, acc ->
      case Drone.Vehicle.whereis(name) do
        pid when is_pid(pid) ->
          Process.link(pid)
          Map.put(acc, pid, name)

        nil ->
          acc
      end
    end)
  end

  defp safe_disconnect(drone) do
    Drone.disconnect(drone)
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp lookup_members(pid) when is_pid(pid) do
    case :ets.lookup(@members_table, pid) do
      [{^pid, {name, drones, _timeout}}] -> {:ok, name, drones}
      [] -> {:error, :not_found}
    end
  end

  defp lookup_members(name) when is_atom(name) do
    case whereis(name) do
      nil -> {:error, :not_found}
      pid -> lookup_members(pid)
    end
  end

  defp call(swarm, message, opts \\ []) do
    case resolve(swarm) do
      nil ->
        {:error, :not_found}

      pid ->
        timeout = Keyword.get_lazy(opts, :timeout, fn -> stored_timeout(pid) end)
        GenServer.call(pid, message, timeout)
    end
  end

  defp stored_timeout(pid) do
    case :ets.lookup(@members_table, pid) do
      [{^pid, {_name, _drones, timeout}}] -> timeout
      [] -> @default_timeout
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
      |> Keyword.put_new(:heading_deg, 0)
      |> Keyword.put_new(:timeout, @default_timeout)
      |> normalize_member_entries()
    else
      [
        members: normalize_member_list(members),
        spacing_cm: @default_spacing_cm,
        min_separation_cm: @default_min_separation_cm,
        heading_deg: 0,
        timeout: @default_timeout
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
