defmodule Drone.Adapters.Crazyflie.LoggingTest do
  use ExUnit.Case, async: true

  alias Drone.Adapters.Crazyflie.Logging

  test "builds TOC and control packets" do
    assert %{port: 5, channel: 0, payload: <<0x03>>} = Logging.get_toc_info()
    assert %{payload: <<0x02, 7::little-16>>} = Logging.get_toc_item(7)
    assert %{port: 5, channel: 1, payload: <<0x05>>} = Logging.reset()

    create = Logging.create_block_v2(0, [{1, 10}, {1, 20}])
    assert <<0x06, 0, 1, 10::little-16, 1, 20::little-16>> = create.payload

    start = Logging.start_block_v2(0, 100)
    assert <<0x08, 0, 100::little-16>> = start.payload
  end

  test "parses TOC info and items" do
    assert {:ok, %{count: 2, max_blocks: 16, max_ops: 128}} =
             Logging.parse_toc_info(<<0x03, 2::little-16, 1::little-32, 16, 128>>)

    assert {:ok, %{id: 3, type: 1, group: "pm", name: "batteryLevel"}} =
             Logging.parse_toc_item(<<0x02, 3::little-16, 1, "pm", 0, "batteryLevel", 0>>)
  end

  test "resolves layout and parses log data" do
    items = [
      %{id: 10, type: 1, group: "pm", name: "batteryLevel"},
      %{id: 20, type: 1, group: "sys", name: "canfly"}
    ]

    assert {:ok, layout} = Logging.resolve_layout(items)
    assert [{1, 10}, {1, 20}] = Logging.layout_ops(layout)

    assert {:ok, %{battery: 88, estimator_ready: true}} =
             Logging.parse_data(<<0, 1, 2, 3, 88, 1>>, layout)

    assert {:ok, %{battery: 10, estimator_ready: false}} =
             Logging.parse_data(<<0, 0, 0, 0, 10, 0>>, layout)
  end

  test "falls back to pm.vbat voltage mapping" do
    items = [
      %{id: 1, type: 7, group: "pm", name: "vbat"},
      %{id: 2, type: 1, group: "sys", name: "canfly"}
    ]

    assert {:ok, layout} = Logging.resolve_layout(items)
    volts = 3.6
    payload = <<0, 0, 0, 0, volts::little-float-32, 1>>

    assert {:ok, %{battery: pct, estimator_ready: true}} = Logging.parse_data(payload, layout)
    assert pct == Logging.battery_percent_from_vbat(3.6)
  end

  test "rejects incomplete TOC layouts" do
    assert {:error, :missing_battery_log_var} = Logging.resolve_layout([])

    assert {:error, :missing_sys_canfly} =
             Logging.resolve_layout([%{id: 1, type: 1, group: "pm", name: "batteryLevel"}])
  end
end
