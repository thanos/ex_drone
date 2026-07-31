defmodule Drone.Formation do
  @moduledoc """
  Pure geometric formation planners for swarm coordination.

  Formations compute target slots in a shared world frame and return
  per-drone `Drone.Mission` scripts that fly each member to its slot.
  They do **not** run control loops, velocity sync, or flocking behaviours
  (Separate / Align / Cohere live). Plan-time **Separate** is enforced via
  `min_separation_cm`.

  ## Supported formations

    * `:front` — side-by-side, perpendicular to heading (sweeps / advance)
    * `:column` — nose-to-tail along heading (narrow corridors)
    * `:vee` — V opening opposite travel (geometry only; no aero model)
    * `:diamond` — four-sided closed layout (requires 4 drones)
    * `:echelon` — diagonal stepped rank (`side: :left | :right`)
    * `:circle` — evenly spaced on a ring (`radius_cm`)
    * `:shoulder_pair` — alias for `:front` with two members
    * `:grid` — optional classroom row/column lattice (`columns`)

  ## Reference frame

  Default origin is the **centroid** of current positions, or a configured
  `{:xy, x, y}`. Optional `:leader` uses that member's pose **at plan time
  only** — not a live runtime dependency. Yaw `0` means +Y
  (same convention as the shared geometry helpers).

  ## Movement strategy

  For each drone: rotate to face the target bearing → move forward
  (split into ≤500 cm segments) → restore original yaw when needed.
  Horizontal moves shorter than 20 cm are skipped (SDK minimum).

  ## Example

      {:ok, missions} =
        Drone.Formation.plan(:front, %{
          drones: [:a, :b],
          positions: %{
            a: %{x: 0, y: 0, z: 30, yaw: 0},
            b: %{x: 0, y: 0, z: 30, yaw: 0}
          },
          heading_deg: 0,
          spacing_cm: 100,
          min_separation_cm: 80,
          origin: {:xy, 0, 0}
        })

      Drone.Mission.run(missions.a, :a)
  """

  alias Drone.Mission

  @typedoc """
  Built-in formation identifier.

  | Value | Min drones | Layout |
  |-------|------------|--------|
  | `:front` | 2 | Side-by-side ⊥ heading |
  | `:column` | 2 | Along heading |
  | `:vee` | 3 | V behind tip |
  | `:diamond` | 4 | N/E/S/W of origin |
  | `:echelon` | 2 | Diagonal stepped rank |
  | `:circle` | 3 | Ring around origin |
  | `:shoulder_pair` | 2 | Alias of `:front` |
  | `:grid` | 2 | Row/column lattice |

  ## Examples

      :front
      :vee
      :echelon
  """
  @type formation ::
          :front
          | :column
          | :vee
          | :diamond
          | :echelon
          | :circle
          | :shoulder_pair
          | :grid

  @typedoc """
  World-frame pose for one drone used as planning input.

  ## Fields

  | Field | Type | Required | Meaning |
  |-------|------|----------|---------|
  | `:x` | `number()` | yes | East/west cm in shared world frame |
  | `:y` | `number()` | yes | North/south cm (yaw 0 faces +Y) |
  | `:z` | `number()` | no | Altitude cm (unused by horizontal planners) |
  | `:yaw` | `number()` | no | Heading degrees 0..359 (default `0`) |

  ## Example

      %{x: -50, y: 0, z: 30, yaw: 90}
  """
  @type position :: %{
          required(:x) => number(),
          required(:y) => number(),
          optional(:z) => number(),
          optional(:yaw) => number()
        }

  @typedoc """
  Options for `plan/2`.

  ## Fields

  | Key | Type | Default | Meaning |
  |-----|------|---------|---------|
  | `:drones` | `[atom()]` | required | Ordered member names |
  | `:positions` | `%{atom() => position()}` | required | Current poses |
  | `:heading_deg` | `integer()` | `0` | Direction of motion |
  | `:spacing_cm` | `pos_integer()` | `100` | Neighbor spacing |
  | `:min_separation_cm` | `pos_integer()` | `80` | Reject closer planned slots |
  | `:origin` | `:centroid \\| {:xy, number(), number()}` | `:centroid` | Formation origin |
  | `:leader` | `atom()` | none | Plan-time origin = that member's pose |
  | `:side` | `:left \\| :right` | `:right` | Echelon side |
  | `:radius_cm` | `pos_integer()` | `spacing_cm` | Circle radius |
  | `:columns` | `pos_integer()` | `ceil(sqrt(n))` | Grid column count |

  ## Example

      %{
        drones: [:a, :b, :c],
        positions: %{
          a: %{x: 0, y: 0, yaw: 0},
          b: %{x: 0, y: 0, yaw: 0},
          c: %{x: 0, y: 0, yaw: 0}
        },
        heading_deg: 0,
        spacing_cm: 100,
        min_separation_cm: 80,
        origin: :centroid,
        side: :left,
        radius_cm: 150,
        columns: 2
      }
  """
  @type plan_opts :: %{
          optional(:drones) => [atom()],
          optional(:positions) => %{optional(atom()) => position()},
          optional(:heading_deg) => integer(),
          optional(:spacing_cm) => pos_integer(),
          optional(:min_separation_cm) => pos_integer(),
          optional(:origin) => :centroid | {:xy, number(), number()},
          optional(:leader) => atom(),
          optional(:side) => :left | :right,
          optional(:radius_cm) => pos_integer(),
          optional(:columns) => pos_integer()
        }

  @typedoc """
  Error atoms returned by `plan/2`.

  * `:separation_violation` — two planned slots closer than `min_separation_cm`
  * `:unsupported_formation` — unknown formation atom
  * `:too_few_drones` — membership below the formation minimum
  * `:too_many_drones` — membership above a formation maximum (e.g. `:diamond`)
  * `:duplicate_drones` — repeated names in `:drones`
  * `:invalid_option` — bad spacing, columns, side, heading, etc.
  * `:leader_unavailable` — `:leader` missing from `:positions`
  * `:missing_positions` — a member lacks `:x`/`:y`
  * `:unassigned_slot` — planner/assembly mismatch (should not occur)

  ## Example

      :separation_violation
  """
  @type plan_error ::
          :separation_violation
          | :unsupported_formation
          | :too_few_drones
          | :too_many_drones
          | :duplicate_drones
          | :invalid_option
          | :leader_unavailable
          | :missing_positions
          | :unassigned_slot

  @min_move_cm 20
  @max_move_cm 500

  @min_drones %{
    front: 2,
    column: 2,
    vee: 3,
    diamond: 4,
    echelon: 2,
    circle: 3,
    shoulder_pair: 2,
    grid: 2
  }

  @max_drones %{
    diamond: 4,
    shoulder_pair: 2
  }

  @doc """
  Plans missions that move each drone into the given formation.

  Pure function: no processes, no I/O. Returns missions; callers execute them
  (e.g. via `Drone.Swarm.run/2` or `Drone.Mission.run/2`).

  Positions accept numeric `:x`/`:y`/`:yaw`; values are rounded to integers
  before path generation. Moves shorter than 20 cm are skipped (SDK minimum);
  longer legs are split into segments of at most 500 cm with any remainder
  redistributed so the planned slot is reached exactly.

  ## Parameters

    * `formation` (`t:formation/0`) — which layout to compute
    * `opts` (`t:plan_opts/0` or `keyword()`) — drones, positions, spacing, etc.

  ## Returns

    * `{:ok, %{atom() => Drone.Mission.t()}}` — one mission per drone
    * `{:error, plan_error()}` — validation / geometry failure

  ## Examples

      {:ok, missions} =
        Drone.Formation.plan(:front,
          drones: [:left, :right],
          positions: %{
            left: %{x: 0, y: 0, yaw: 0},
            right: %{x: 0, y: 0, yaw: 0}
          },
          spacing_cm: 100,
          origin: {:xy, 0, 0}
        )

      {:error, :separation_violation} =
        Drone.Formation.plan(:front, %{
          drones: [:a, :b],
          positions: %{a: %{x: 0, y: 0}, b: %{x: 0, y: 0}},
          spacing_cm: 40,
          min_separation_cm: 80,
          origin: {:xy, 0, 0}
        })
  """
  @spec plan(formation(), plan_opts() | keyword()) ::
          {:ok, %{atom() => Mission.t()}} | {:error, plan_error()}
  def plan(formation, opts) when is_list(opts), do: plan(formation, Map.new(opts))

  def plan(:shoulder_pair, opts) when is_map(opts) do
    with {:ok, drones} <- fetch_drones(opts),
         :ok <- check_drone_count(:shoulder_pair, drones) do
      plan(:front, opts)
    end
  end

  def plan(formation, opts) when is_map(opts) do
    with {:ok, drones} <- fetch_drones(opts),
         :ok <- check_duplicates(drones),
         :ok <- check_drone_count(formation, drones),
         {:ok, opts} <- validate_opts(formation, opts),
         {:ok, positions} <- fetch_positions(drones, opts),
         {:ok, origin} <- resolve_origin(drones, positions, opts),
         heading = Map.fetch!(opts, :heading_deg),
         spacing = Map.fetch!(opts, :spacing_cm),
         min_sep = Map.fetch!(opts, :min_separation_cm),
         {:ok, slots} <- compute_slots(formation, drones, origin, heading, spacing, opts),
         :ok <- check_separation(slots, min_sep) do
      build_missions(drones, positions, slots)
    end
  end

  def plan(_formation, _opts), do: {:error, :unsupported_formation}

  defp fetch_drones(%{drones: drones}) when is_list(drones) and drones != [], do: {:ok, drones}
  defp fetch_drones(_), do: {:error, :too_few_drones}

  defp check_duplicates(drones) do
    if length(Enum.uniq(drones)) == length(drones) do
      :ok
    else
      {:error, :duplicate_drones}
    end
  end

  defp check_drone_count(formation, drones) do
    n = length(drones)

    case Map.fetch(@min_drones, formation) do
      {:ok, min} ->
        max = Map.get(@max_drones, formation)

        cond do
          n < min -> {:error, :too_few_drones}
          max != nil and n > max -> {:error, :too_many_drones}
          true -> :ok
        end

      :error ->
        :ok
    end
  end

  defp validate_opts(formation, opts) do
    heading = Map.get(opts, :heading_deg, 0)
    spacing = Map.get(opts, :spacing_cm, 100)
    min_sep = Map.get(opts, :min_separation_cm, 80)
    side = Map.get(opts, :side, :right)
    radius = Map.get(opts, :radius_cm, spacing)
    columns = Map.get(opts, :columns, :auto)

    with :ok <- require_integer(heading),
         :ok <- require_positive_integer(spacing),
         :ok <- require_positive_integer(min_sep),
         :ok <- validate_side(formation, side),
         :ok <- validate_radius(formation, radius),
         :ok <- validate_columns(formation, columns) do
      {:ok,
       opts
       |> Map.put(:heading_deg, heading)
       |> Map.put(:spacing_cm, spacing)
       |> Map.put(:min_separation_cm, min_sep)
       |> Map.put(:side, side)
       |> Map.put(:radius_cm, radius)
       |> Map.put(:columns, columns)}
    end
  end

  defp require_integer(n) when is_integer(n), do: :ok
  defp require_integer(_), do: {:error, :invalid_option}

  defp require_positive_integer(n) when is_integer(n) and n > 0, do: :ok
  defp require_positive_integer(_), do: {:error, :invalid_option}

  defp validate_side(:echelon, side) when side in [:left, :right], do: :ok
  defp validate_side(:echelon, _), do: {:error, :invalid_option}
  defp validate_side(_, _), do: :ok

  defp validate_radius(:circle, radius), do: require_positive_integer(radius)
  defp validate_radius(_, _), do: :ok

  defp validate_columns(:grid, :auto), do: :ok
  defp validate_columns(:grid, columns), do: require_positive_integer(columns)
  defp validate_columns(_, _), do: :ok

  defp fetch_positions(drones, opts) do
    positions = Map.get(opts, :positions, %{})

    if Enum.all?(drones, fn name -> match?(%{x: _, y: _}, Map.get(positions, name)) end) do
      normalized =
        Map.new(drones, fn name ->
          pos = Map.fetch!(positions, name)

          {name,
           %{
             x: round_number(Map.fetch!(pos, :x)),
             y: round_number(Map.fetch!(pos, :y)),
             z: round_number(Map.get(pos, :z, 0)),
             yaw: rem(round_number(Map.get(pos, :yaw, 0)) + 360, 360)
           }}
        end)

      {:ok, normalized}
    else
      {:error, :missing_positions}
    end
  end

  defp round_number(n) when is_integer(n), do: n
  defp round_number(n) when is_float(n), do: round(n)

  defp resolve_origin(_drones, positions, %{leader: leader}) do
    case Map.get(positions, leader) do
      %{x: x, y: y} -> {:ok, {x * 1.0, y * 1.0}}
      _ -> {:error, :leader_unavailable}
    end
  end

  defp resolve_origin(_drones, _positions, %{origin: {:xy, x, y}}), do: {:ok, {x * 1.0, y * 1.0}}

  defp resolve_origin(drones, positions, _opts) do
    {sx, sy} =
      Enum.reduce(drones, {0.0, 0.0}, fn name, {ax, ay} ->
        %{x: x, y: y} = Map.fetch!(positions, name)
        {ax + x, ay + y}
      end)

    n = length(drones)
    {:ok, {sx / n, sy / n}}
  end

  defp build_missions(drones, positions, slots) do
    Enum.reduce_while(drones, {:ok, %{}}, fn name, {:ok, acc} ->
      case Map.fetch(slots, name) do
        {:ok, {tx, ty}} ->
          pos = Map.fetch!(positions, name)
          {:cont, {:ok, Map.put(acc, name, path_mission(pos, tx, ty))}}

        :error ->
          {:halt, {:error, :unassigned_slot}}
      end
    end)
  end

  defp compute_slots(:front, drones, origin, heading, spacing, _opts) do
    {:ok, line_slots(drones, origin, heading, spacing, :perpendicular)}
  end

  defp compute_slots(:column, drones, origin, heading, spacing, _opts) do
    {:ok, line_slots(drones, origin, heading, spacing, :along)}
  end

  defp compute_slots(:echelon, drones, origin, heading, spacing, opts) do
    sign = if Map.fetch!(opts, :side) == :left, do: -1, else: 1
    {fx, fy} = unit(heading)
    {rx, ry} = perpendicular(heading)
    n = length(drones)

    slots =
      drones
      |> Enum.with_index()
      |> Map.new(fn {name, i} ->
        offset = i - (n - 1) / 2
        x = elem(origin, 0) + offset * spacing * fx + sign * offset * spacing * rx
        y = elem(origin, 1) + offset * spacing * fy + sign * offset * spacing * ry
        {name, {trunc(x), trunc(y)}}
      end)

    {:ok, slots}
  end

  defp compute_slots(:vee, drones, origin, heading, spacing, _opts) do
    {fx, fy} = unit(heading)
    {rx, ry} = perpendicular(heading)
    [leader | wings] = drones
    {ox, oy} = origin

    tip = {trunc(ox), trunc(oy)}

    wing_slots =
      wings
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {name, i} ->
        side = if rem(i, 2) == 1, do: -1, else: 1
        rank = div(i + 1, 2)
        x = ox - rank * spacing * fx + side * rank * spacing * rx
        y = oy - rank * spacing * fy + side * rank * spacing * ry
        [{name, {trunc(x), trunc(y)}}]
      end)

    {:ok, Map.new([{leader, tip} | wing_slots])}
  end

  defp compute_slots(:diamond, [a, b, c, d], origin, heading, spacing, _opts) do
    {fx, fy} = unit(heading)
    {rx, ry} = perpendicular(heading)
    {ox, oy} = origin

    slots = %{
      a => {trunc(ox + spacing * fx), trunc(oy + spacing * fy)},
      b => {trunc(ox + spacing * rx), trunc(oy + spacing * ry)},
      c => {trunc(ox - spacing * fx), trunc(oy - spacing * fy)},
      d => {trunc(ox - spacing * rx), trunc(oy - spacing * ry)}
    }

    {:ok, slots}
  end

  defp compute_slots(:circle, drones, origin, heading, spacing, opts) do
    n = length(drones)
    radius = Map.get(opts, :radius_cm, spacing)
    {ox, oy} = origin
    base = heading * :math.pi() / 180

    slots =
      drones
      |> Enum.with_index()
      |> Map.new(fn {name, i} ->
        angle = base + 2 * :math.pi() * i / n
        x = ox + radius * :math.sin(angle)
        y = oy + radius * :math.cos(angle)
        {name, {trunc(x), trunc(y)}}
      end)

    {:ok, slots}
  end

  defp compute_slots(:grid, drones, origin, heading, spacing, opts) do
    n = length(drones)

    cols =
      case Map.get(opts, :columns, :auto) do
        :auto -> max(1, ceil(:math.sqrt(n)))
        c -> c
      end

    {fx, fy} = unit(heading)
    {rx, ry} = perpendicular(heading)
    {ox, oy} = origin
    rows = ceil(n / cols)

    slots =
      drones
      |> Enum.with_index()
      |> Map.new(fn {name, i} ->
        col = rem(i, cols)
        row = div(i, cols)
        cx = col - (cols - 1) / 2
        cy = row - (rows - 1) / 2
        x = ox + cy * spacing * fx + cx * spacing * rx
        y = oy + cy * spacing * fy + cx * spacing * ry
        {name, {trunc(x), trunc(y)}}
      end)

    {:ok, slots}
  end

  defp compute_slots(_formation, _drones, _origin, _heading, _spacing, _opts) do
    {:error, :unsupported_formation}
  end

  defp line_slots(drones, {ox, oy}, heading, spacing, axis) do
    n = length(drones)

    {ux, uy} =
      case axis do
        :along -> unit(heading)
        :perpendicular -> perpendicular(heading)
      end

    drones
    |> Enum.with_index()
    |> Map.new(fn {name, i} ->
      offset = i - (n - 1) / 2
      x = ox + offset * spacing * ux
      y = oy + offset * spacing * uy
      {name, {trunc(x), trunc(y)}}
    end)
  end

  defp check_separation(slots, min_sep) do
    points = Map.values(slots)

    too_close? =
      points
      |> Enum.with_index()
      |> Enum.any?(fn {{x1, y1}, i} ->
        points
        |> Enum.drop(i + 1)
        |> Enum.any?(fn {x2, y2} ->
          horizontal_distance(x1, y1, x2, y2) < min_sep
        end)
      end)

    if too_close?, do: {:error, :separation_violation}, else: :ok
  end

  defp path_mission(pos, tx, ty) do
    x = Map.fetch!(pos, :x)
    y = Map.fetch!(pos, :y)
    yaw = Map.get(pos, :yaw, 0)

    dx = tx - x
    dy = ty - y
    distance = trunc(:math.sqrt(dx * dx + dy * dy))

    mission = Mission.new()

    if distance < @min_move_cm do
      mission
    else
      bearing = bearing_deg(dx, dy)

      mission
      |> maybe_rotate(yaw, bearing)
      |> append_forward_segments(distance)
      |> maybe_rotate(bearing, yaw)
    end
  end

  defp maybe_rotate(mission, from_yaw, to_yaw) do
    delta = rem(to_yaw - from_yaw + 360, 360)

    cond do
      delta == 0 ->
        mission

      delta <= 180 ->
        Mission.rotate(mission, :cw, delta)

      true ->
        Mission.rotate(mission, :ccw, 360 - delta)
    end
  end

  defp append_forward_segments(mission, distance) when distance <= @max_move_cm do
    Mission.move(mission, :forward, distance)
  end

  defp append_forward_segments(mission, distance) do
    # Keep every segment >= @min_move_cm so the target is reached exactly.
    remainder = distance - @max_move_cm

    {first, rest} =
      if remainder < @min_move_cm do
        {@max_move_cm - (@min_move_cm - remainder), @min_move_cm}
      else
        {@max_move_cm, remainder}
      end

    mission
    |> Mission.move(:forward, first)
    |> append_forward_segments(rest)
  end

  defp bearing_deg(dx, dy) do
    rad = :math.atan2(dx, dy)
    deg = rad * 180 / :math.pi()
    rem(trunc(Float.round(deg)) + 360, 360)
  end

  defp horizontal_distance(x1, y1, x2, y2) do
    dx = x2 - x1
    dy = y2 - y1
    :math.sqrt(dx * dx + dy * dy)
  end

  defp unit(heading_deg) do
    r = heading_deg * :math.pi() / 180
    {:math.sin(r), :math.cos(r)}
  end

  defp perpendicular(heading_deg) do
    r = heading_deg * :math.pi() / 180
    {:math.cos(r), -:math.sin(r)}
  end
end
