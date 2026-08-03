# Examples

## Crazyflie mock flight

Hardware-free Crazyflie path for ex_drone v0.3.0:

```shell
mix run examples/crazyflie_mock_flight.exs
```

See [docs/crazyflie.md](../docs/crazyflie.md).

## Good Advisor / Bad Advisor

Simulator-first swarm demo for ex_drone v0.2.0.

`:good` flies a modest mission. `:bad` attempts an illegal climb and is
rejected by per-drone safety. The swarm reports a partial result; processes
remain isolated.

```shell
mix run examples/good_bad_advisor.exs
```
