defmodule Drone.FormationTest do
  use ExUnit.Case, async: true

  alias Drone.{Formation, Mission}

  defp positions(pairs) do
    Map.new(pairs, fn {name, {x, y, yaw}} ->
      {name, %{x: x, y: y, z: 30, yaw: yaw}}
    end)
  end

  defp forward_cm(mission) do
    mission
    |> Mission.commands()
    |> Enum.reduce(0, fn
      %{type: :move, args: args}, acc -> acc + Keyword.get(args, :distance, 0)
      _, acc -> acc
    end)
  end

  describe "plan/2 front" do
    test "places two drones side-by-side on heading 0" do
      drones = [:a, :b]
      pos = positions(a: {0, 0, 0}, b: {0, 0, 0})

      assert {:ok, missions} =
               Formation.plan(:front, %{
                 drones: drones,
                 positions: pos,
                 spacing_cm: 100,
                 min_separation_cm: 80,
                 origin: {:xy, 0, 0},
                 heading_deg: 0
               })

      assert Map.has_key?(missions, :a)
      assert Map.has_key?(missions, :b)
      assert Mission.length(missions.a) > 0
      assert Mission.length(missions.b) > 0
    end

    test "front slots are on X axis at heading 0; column slots on Y" do
      # Already at expected front slots → empty missions
      assert {:ok, front} =
               Formation.plan(:front, %{
                 drones: [:a, :b],
                 positions: positions(a: {-50, 0, 0}, b: {50, 0, 0}),
                 spacing_cm: 100,
                 origin: {:xy, 0, 0},
                 heading_deg: 0
               })

      assert Mission.length(front.a) == 0
      assert Mission.length(front.b) == 0

      # Front slots are wrong for column → non-empty missions
      assert {:ok, as_column} =
               Formation.plan(:column, %{
                 drones: [:a, :b],
                 positions: positions(a: {-50, 0, 0}, b: {50, 0, 0}),
                 spacing_cm: 100,
                 origin: {:xy, 0, 0},
                 heading_deg: 0
               })

      assert Mission.length(as_column.a) > 0
      assert Mission.length(as_column.b) > 0

      # Column expected slots
      assert {:ok, column} =
               Formation.plan(:column, %{
                 drones: [:a, :b],
                 positions: positions(a: {0, -50, 0}, b: {0, 50, 0}),
                 spacing_cm: 100,
                 origin: {:xy, 0, 0},
                 heading_deg: 0
               })

      assert Mission.length(column.a) == 0
      assert Mission.length(column.b) == 0
    end

    test "shoulder_pair aliases front for exactly two drones" do
      drones = [:good, :bad]
      pos = positions(good: {0, 0, 0}, bad: {0, 0, 0})

      assert {:ok, _} =
               Formation.plan(:shoulder_pair, %{
                 drones: drones,
                 positions: pos,
                 spacing_cm: 100,
                 origin: {:xy, 0, 0}
               })

      assert {:error, :too_many_drones} =
               Formation.plan(:shoulder_pair, %{
                 drones: [:a, :b, :c],
                 positions: positions(a: {0, 0, 0}, b: {0, 0, 0}, c: {0, 0, 0}),
                 spacing_cm: 100,
                 origin: {:xy, 0, 0}
               })
    end
  end

  describe "plan/2 column" do
    test "places drones along heading" do
      drones = [:a, :b, :c]

      assert {:ok, missions} =
               Formation.plan(:column, %{
                 drones: drones,
                 positions: positions(a: {0, -100, 0}, b: {0, 0, 0}, c: {0, 100, 0}),
                 spacing_cm: 100,
                 origin: {:xy, 0, 0},
                 heading_deg: 0
               })

      assert map_size(missions) == 3
      assert Mission.length(missions.a) == 0
      assert Mission.length(missions.b) == 0
      assert Mission.length(missions.c) == 0
    end
  end

  describe "plan/2 vee diamond echelon circle grid" do
    test "vee requires at least 3 drones" do
      assert {:error, :too_few_drones} =
               Formation.plan(:vee, %{
                 drones: [:a, :b],
                 positions: positions(a: {0, 0, 0}, b: {0, 0, 0})
               })
    end

    test "vee plans for 3 drones" do
      drones = [:a, :b, :c]
      pos = positions(a: {0, 0, 0}, b: {0, 0, 0}, c: {0, 0, 0})

      assert {:ok, missions} =
               Formation.plan(:vee, %{
                 drones: drones,
                 positions: pos,
                 spacing_cm: 100,
                 origin: {:xy, 0, 0}
               })

      assert map_size(missions) == 3
    end

    test "diamond requires exactly 4 drones" do
      assert {:error, :too_few_drones} =
               Formation.plan(:diamond, %{
                 drones: [:a, :b, :c],
                 positions: positions(a: {0, 0, 0}, b: {0, 0, 0}, c: {0, 0, 0})
               })

      assert {:error, :too_many_drones} =
               Formation.plan(:diamond, %{
                 drones: [:a, :b, :c, :d, :e],
                 positions:
                   positions(a: {0, 0, 0}, b: {0, 0, 0}, c: {0, 0, 0}, d: {0, 0, 0}, e: {0, 0, 0}),
                 spacing_cm: 100,
                 origin: {:xy, 0, 0}
               })
    end

    test "diamond plans four slots" do
      drones = [:a, :b, :c, :d]

      assert {:ok, missions} =
               Formation.plan(:diamond, %{
                 drones: drones,
                 positions:
                   positions(a: {0, 100, 0}, b: {100, 0, 0}, c: {0, -100, 0}, d: {-100, 0, 0}),
                 spacing_cm: 100,
                 origin: {:xy, 0, 0},
                 heading_deg: 0
               })

      assert map_size(missions) == 4
      assert Enum.all?(missions, fn {_k, m} -> Mission.length(m) == 0 end)
    end

    test "echelon and circle and grid plan" do
      three = [:a, :b, :c]
      pos3 = positions(a: {0, 0, 0}, b: {0, 0, 0}, c: {0, 0, 0})

      assert {:ok, _} =
               Formation.plan(:echelon, %{
                 drones: three,
                 positions: pos3,
                 spacing_cm: 100,
                 origin: {:xy, 0, 0},
                 side: :left
               })

      assert {:ok, _} =
               Formation.plan(:circle, %{
                 drones: three,
                 positions: pos3,
                 spacing_cm: 100,
                 radius_cm: 100,
                 origin: {:xy, 0, 0}
               })

      assert {:ok, _} =
               Formation.plan(:grid, %{
                 drones: three,
                 positions: pos3,
                 spacing_cm: 100,
                 origin: {:xy, 0, 0},
                 columns: 2
               })
    end
  end

  describe "plan/2 validation" do
    test "rejects separation violations" do
      drones = [:a, :b]
      pos = positions(a: {0, 0, 0}, b: {0, 0, 0})

      assert {:error, :separation_violation} =
               Formation.plan(:front, %{
                 drones: drones,
                 positions: pos,
                 spacing_cm: 40,
                 min_separation_cm: 80,
                 origin: {:xy, 0, 0}
               })
    end

    test "rejects missing leader" do
      drones = [:a, :b]
      pos = positions(a: {0, 0, 0}, b: {10, 0, 0})

      assert {:error, :leader_unavailable} =
               Formation.plan(:front, %{
                 drones: drones,
                 positions: pos,
                 leader: :missing,
                 spacing_cm: 100
               })
    end

    test "uses leader pose as origin" do
      drones = [:a, :b]
      # a at origin, b far east — centroid is (100,0), leader :a is (0,0)
      pos = positions(a: {0, 0, 0}, b: {200, 0, 0})

      assert {:ok, leader_plan} =
               Formation.plan(:front, %{
                 drones: drones,
                 positions: pos,
                 leader: :a,
                 spacing_cm: 100,
                 min_separation_cm: 80
               })

      assert {:ok, centroid_plan} =
               Formation.plan(:front, %{
                 drones: drones,
                 positions: pos,
                 origin: :centroid,
                 spacing_cm: 100,
                 min_separation_cm: 80
               })

      # Leader slots (-50,0)/(50,0): b travels ~150cm. Centroid slots (50,0)/(150,0): b travels ~50cm.
      assert forward_cm(leader_plan.b) > forward_cm(centroid_plan.b)
    end

    test "rejects unsupported formation" do
      assert {:error, :unsupported_formation} =
               Formation.plan(:spiral, %{
                 drones: [:a, :b],
                 positions: positions(a: {0, 0, 0}, b: {0, 0, 0})
               })
    end

    test "empty missions when already in slot" do
      drones = [:a, :b]
      pos = positions(a: {-50, 0, 0}, b: {50, 0, 0})

      assert {:ok, missions} =
               Formation.plan(:front, %{
                 drones: drones,
                 positions: pos,
                 spacing_cm: 100,
                 origin: {:xy, 0, 0},
                 heading_deg: 0
               })

      assert Mission.length(missions.a) == 0
      assert Mission.length(missions.b) == 0
    end

    test "accepts fractional yaw and coordinates" do
      assert {:ok, missions} =
               Formation.plan(:front, %{
                 drones: [:a, :b],
                 positions: %{
                   a: %{x: 0.5, y: 0.0, yaw: 12.5},
                   b: %{x: 0.0, y: 0.0, yaw: 359.9}
                 },
                 spacing_cm: 100,
                 min_separation_cm: 80,
                 origin: {:xy, 0, 0}
               })

      assert Mission.length(missions.a) > 0
    end

    test "rejects invalid options instead of raising" do
      base = %{
        drones: [:a, :b],
        positions: positions(a: {0, 0, 0}, b: {0, 0, 0}),
        origin: {:xy, 0, 0}
      }

      assert {:error, :invalid_option} = Formation.plan(:grid, Map.put(base, :columns, 0))
      assert {:error, :invalid_option} = Formation.plan(:front, Map.put(base, :spacing_cm, 0))
      assert {:error, :invalid_option} = Formation.plan(:echelon, Map.put(base, :side, :sideways))
    end

    test "rejects duplicate drone names" do
      assert {:error, :duplicate_drones} =
               Formation.plan(:front, %{
                 drones: [:a, :a],
                 positions: positions(a: {0, 0, 0}),
                 spacing_cm: 100,
                 origin: {:xy, 0, 0}
               })
    end

    test "accepts keyword opts and auto grid columns" do
      assert {:ok, missions} =
               Formation.plan(:front,
                 drones: [:a, :b],
                 positions: positions(a: {0, 0, 0}, b: {0, 0, 0}),
                 heading_deg: 0,
                 spacing_cm: 100,
                 min_separation_cm: 80,
                 origin: {:xy, 0, 0}
               )

      assert map_size(missions) == 2

      assert {:ok, grid} =
               Formation.plan(:grid, %{
                 drones: [:a, :b, :c, :d],
                 positions: positions(a: {0, 0, 0}, b: {0, 0, 0}, c: {0, 0, 0}, d: {0, 0, 0}),
                 spacing_cm: 100,
                 min_separation_cm: 50,
                 origin: {:xy, 0, 0},
                 columns: :auto
               })

      assert map_size(grid) == 4
    end

    test "rejects missing drones, bad heading, and non-map opts" do
      assert {:error, :too_few_drones} = Formation.plan(:front, %{positions: %{}})
      assert {:error, :too_few_drones} = Formation.plan(:front, %{drones: []})

      assert {:error, :invalid_option} =
               Formation.plan(:front, %{
                 drones: [:a, :b],
                 positions: positions(a: {0, 0, 0}, b: {0, 0, 0}),
                 heading_deg: 1.5,
                 origin: {:xy, 0, 0}
               })

      assert {:error, :unsupported_formation} = Formation.plan(:front, :not_a_map)
    end

    test "splits long relocation into SDK-sized forward segments" do
      # Slot for :a is at x=-50 for two-drone front at origin {0,0}; place a far away.
      assert {:ok, missions} =
               Formation.plan(:front, %{
                 drones: [:a, :b],
                 positions: %{
                   a: %{x: -50, y: -700, z: 0, yaw: 0},
                   b: %{x: 50, y: 0, z: 0, yaw: 0}
                 },
                 heading_deg: 0,
                 spacing_cm: 100,
                 min_separation_cm: 80,
                 origin: {:xy, 0, 0}
               })

      moves =
        missions.a
        |> Mission.commands()
        |> Enum.filter(&(&1.type == :move))

      assert match?([_, _ | _], moves)
      distances = Enum.map(moves, &Keyword.fetch!(&1.args, :distance))
      assert Enum.all?(distances, &(&1 >= 20 and &1 <= 500))
      assert Enum.sum(distances) == 700
    end

    test "redistributes remainder under 20 cm across long segments" do
      # Distance 510 → remainder 10 < 20, so first segment shrinks and rest is 20.
      assert {:ok, missions} =
               Formation.plan(:front, %{
                 drones: [:a, :b],
                 positions: %{
                   a: %{x: -50, y: -510, z: 0, yaw: 0},
                   b: %{x: 50, y: 0, z: 0, yaw: 0}
                 },
                 heading_deg: 0,
                 spacing_cm: 100,
                 min_separation_cm: 80,
                 origin: {:xy, 0, 0}
               })

      distances =
        missions.a
        |> Mission.commands()
        |> Enum.filter(&(&1.type == :move))
        |> Enum.map(&Keyword.fetch!(&1.args, :distance))

      assert Enum.sum(distances) == 510
      assert Enum.all?(distances, &(&1 >= 20 and &1 <= 500))
    end
  end
end
