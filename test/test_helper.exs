Mox.defmock(Drone.AdapterMock, for: Drone.Adapter)
Mox.defmock(Drone.CrazyflieUSBMock, for: Drone.Adapters.Crazyflie.USB)
Mox.defmock(Drone.CrazyflieTransportMock, for: Drone.Adapters.Crazyflie.Transport)

ExUnit.start(exclude: [:pending])

case Application.ensure_all_started(:ex_drone) do
  {:ok, _} -> :ok
  {:error, {:already_started, _}} -> :ok
  {:error, {:already_started, :ex_drone}} -> :ok
  _ -> :ok
end
