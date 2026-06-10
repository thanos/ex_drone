defmodule Drone.Safety.PolicyTest do
  use ExUnit.Case, async: true

  alias Drone.{Safety.Geofence, Safety.Policy}

  describe "default/0" do
    test "returns default outdoor safety policy" do
      policy = Policy.default()
      assert policy.max_altitude_cm == 300
      assert policy.max_distance_cm == 1000
      assert policy.min_battery_percent == 15
      assert policy.battery_warning_percent == 20
      assert policy.allowlist == nil
      assert policy.dry_run == false
      assert policy.indoor == false
      assert policy.prop_guards == false
    end
  end

  describe "indoor/0" do
    test "returns indoor safety policy with tighter limits" do
      policy = Policy.indoor()
      assert policy.max_altitude_cm == 200
      assert policy.max_distance_cm == 500
      assert policy.min_battery_percent == 20
      assert policy.battery_warning_percent == 25
      assert policy.indoor == true
      assert policy.prop_guards == true
    end
  end

  describe "unrestricted/0" do
    test "returns unrestricted policy with no limits" do
      policy = Policy.unrestricted()
      assert policy.max_altitude_cm == nil
      assert policy.max_distance_cm == nil
      assert policy.min_battery_percent == 0
      assert policy.battery_warning_percent == 0
    end
  end

  describe "new/1" do
    test "creates policy from default with overrides" do
      policy = Policy.new(max_altitude_cm: 500)
      assert policy.max_altitude_cm == 500
      assert policy.max_distance_cm == 1000
    end

    test "applies indoor preset and allows overrides" do
      policy = Policy.new(indoor: true, max_altitude_cm: 500)
      assert policy.indoor == true
      assert policy.max_altitude_cm == 500
      assert policy.max_distance_cm == 500
    end

    test "creates policy with geofence" do
      geofence = Geofence.radius(500)
      policy = Policy.new(geofence: geofence)
      assert policy.geofence == geofence
    end
  end
end
