# Good Advisor / Bad Advisor

Simulator-first swarm demo for ex_drone v0.2.0.

`:good` flies a modest mission. `:bad` attempts an illegal climb and is
rejected by per-drone safety. The swarm reports a partial result; processes
remain isolated.

Run from the project root:

```bash
mix run examples/good_bad_advisor.exs
```
