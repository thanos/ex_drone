defmodule Drone.FormationTest do
  use ExUnit.Case, async: true

  alias Drone.{Formation, Mission}

  defp positions(pairs) do
    Map.new(pairs, fn {name, {x, y, yaw}} ->
      {name, %{x: x, y: y, z: 30, yaw: yaw}}
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

    test "shoulder_pair aliases front" do
      drones = [:good, :bad]
      pos = positions(good: {0, 0, 0}, bad: {0, 0, 0})

      assert {:ok, _} =
               Formation.plan(:shoulder_pair, %{
                 drones: drones,
                 positions: pos,
                 spacing_cm: 100,
                 origin: {:xy, 0, 0}
               })
    end
  end

  describe "plan/2 column" do
    test "places drones along heading" do
      drones = [:a, :b, :c]
      pos = positions(a: {0, 0, 0}, b: {0, 0, 0}, c: {0, 0, 0})

      assert {:ok, missions} =
               Formation.plan(:column, %{
                 drones: drones,
                 positions: pos,
                 spacing_cm: 100,
                 origin: {:xy, 0, 0},
                 heading_deg: 0
               })

      assert map_size(missions) == 3
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

    test "diamond requires 4 drones" do
      assert {:error, :too_few_drones} =
               Formation.plan(:diamond, %{
                 drones: [:a, :b, :c],
                 positions: positions(a: {0, 0, 0}, b: {0, 0, 0}, c: {0, 0, 0})
               })
    end

    test "diamond plans four slots" do
      drones = [:a, :b, :c, :d]
      pos = positions(a: {0, 0, 0}, b: {0, 0, 0}, c: {0, 0, 0}, d: {0, 0, 0})

      assert {:ok, missions} =
               Formation.plan(:diamond, %{
                 drones: drones,
                 positions: pos,
                 spacing_cm: 100,
                 origin: {:xy, 0, 0}
               })

      assert map_size(missions) == 4
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
      pos = positions(a: {100, 0, 0}, b: {100, 0, 0})

      assert {:ok, missions} =
               Formation.plan(:front, %{
                 drones: drones,
                 positions: pos,
                 leader: :a,
                 spacing_cm: 100,
                 min_separation_cm: 80
               })

      assert Mission.length(missions.a) > 0 or Mission.length(missions.b) > 0
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
      # heading 0 front with spacing 100 around origin → slots (-50,0) and (50,0)
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
  end
end
