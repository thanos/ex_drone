import Config

config :ex_drone,
  default_adapter: :sim

import_config "#{config_env()}.exs"
