defmodule Drone.Adapters.Crazyflie.USB.Unavailable do
  @moduledoc """
  Default USB backend when no native libusb integration is configured.

  Radio hardware requires an optional USB backend module passed as
  `usb_backend: Module` to `Drone.connect/2`. Every operation except
  `close/1` returns `{:error, :usb_backend_unavailable}`.

  Useful as a safe default so `radio://` URIs fail loudly instead of
  crashing when no backend is wired.

  ## Examples

      {:error, :usb_backend_unavailable} =
        Drone.Adapters.Crazyflie.USB.Unavailable.discover([])

      {:ok, drone} =
        Drone.connect(:crazyflie,
          uri: "radio://0/80/2M",
          usb_backend: MyApp.CrazyradioUSB
        )
  """

  @behaviour Drone.Adapters.Crazyflie.USB

  @doc """
  Always fails discovery with `:usb_backend_unavailable`.

  ## Parameters

    * `_opts` (`keyword()`) — ignored

  ## Returns

  `{:error, :usb_backend_unavailable}`.
  """
  @impl true
  def discover(_opts), do: {:error, :usb_backend_unavailable}

  @doc """
  Always fails open with `:usb_backend_unavailable`.

  ## Parameters

    * `_info` (`map()`) — ignored device info
    * `_opts` (`keyword()`) — ignored

  ## Returns

  `{:error, :usb_backend_unavailable}`.
  """
  @impl true
  def open(_info, _opts), do: {:error, :usb_backend_unavailable}

  @doc """
  Always fails control writes with `:usb_backend_unavailable`.
  """
  @impl true
  def control_write(_dev, _req, _value, _index, _data, _timeout),
    do: {:error, :usb_backend_unavailable}

  @doc """
  Always fails bulk writes with `:usb_backend_unavailable`.
  """
  @impl true
  def bulk_write(_dev, _ep, _data, _timeout), do: {:error, :usb_backend_unavailable}

  @doc """
  Always fails bulk reads with `:usb_backend_unavailable`.
  """
  @impl true
  def bulk_read(_dev, _ep, _max, _timeout), do: {:error, :usb_backend_unavailable}

  @doc """
  No-op close (nothing was opened).

  ## Returns

  Always `:ok`.
  """
  @impl true
  def close(_dev), do: :ok
end
