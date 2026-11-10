# Through Iris · labs

Runnable companion code for the Through Iris hardware-verification series.
Each folder is one episode: the RTL from the video, the broken versions it
explains, self-checking testbenches, and one command that runs them all on
free simulators.

| lab | episode | run |
|---|---|---|
| [`ep20-axi-vip`](ep20-axi-vip/) | A complete AXI VIP from an empty file (agent, scoreboard, coverage, register model, assertions, env, test), and three ways it goes green without checking: a scoreboard nobody connected, a register write that clears its neighbour, a driver that drops VALID | `cd ep20-axi-vip && python run.py` |
| [`ep24-cdc`](ep24-cdc/) | Three CDC bugs that pass simulation, and how to catch them. Ends with a final lab: find the two CDC bugs in ep06's AXI-to-APB bridge | `cd ep24-cdc && python run.py` |
| [`ep26-pcie`](ep26-pcie/) | Three PCIe bugs where every packet is legal: a read that comes back in pieces, a credit that never comes back, a replay counted twice | `cd ep26-pcie && python run.py` |
| [`ep29-formal`](ep29-formal/) | Three ways a formal result lies: a counterexample that isn't a bug, a proof that checks nothing, a bound read as a proof. Ends with a final lab: find the bug in a skid buffer | `cd ep29-formal && python run.py` |

Every push runs every lab in CI: the simulation labs on Verilator and Icarus
(ep20 on Verilator only), the formal lab on SymbiYosys. The broken designs are
part of that check: a lab only passes if each break still fails where the
episode says it does.

Requirements: Python 3 and the [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build/releases).
MIT licensed.
