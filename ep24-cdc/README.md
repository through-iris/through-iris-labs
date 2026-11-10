# ep24 · Three CDC bugs that pass simulation, and how to catch them

Companion code for **Through Iris ep24: Clock Domain Crossings** (video link added at publish).

The episode's claim is that every CDC bug passes functional simulation by
construction. This lab lets you watch it happen. You run each broken design
from the video and it comes up green. Then you add the one technique that can
see that bug, and it fails. Then you run the fix with everything switched on,
and it passes.

It ends with a final lab: the AXI-to-APB bridge from ep06, with two CDC bugs
hidden in it for you to find.

```
python run.py
```

## The three bugs

| | the bug | why plain sim is green | what catches it | the fix |
|---|---|---|---|---|
| **1** | a binary bus, a synchronizer on every bit | every bit takes exactly 2 cycles in sim | metastability injection, or the Gray assertion | Gray code: `rtl/bus_xing.sv` |
| **2** | two related signals, synchronized separately, used together (reconvergence) | both take exactly 2 cycles in sim | metastability injection | cross them as one word: `rtl/reconv_xing.sv` |
| **3** | a one-cycle pulse into a slower clock | at a slow→fast ratio, nothing is lost | a fast→slow clock ratio, or the width assertion | cross a toggle: `rtl/pulse_sync.sv` |

None of the three is a missing synchronizer. Every bit that crosses has one.
That's what makes them survive review.

## Final lab: find the bugs in the bridge

ep06 called the AXI-to-APB bridge "a handshake into the bridge … and a response
all the way back", and said long APB wait states usually come from a clock
crossing. `rtl/broken/apb_bridge_bad.sv` is that bridge with its clock crossing
built in, the way it often gets written the first time: AXI-Lite on one clock,
APB on another. It passes plain simulation at the usual ratio, AXI fast and APB
slow. It has two CDC bugs.

```
python run.py bridge --broken --clocks fast2slow            # green
python run.py bridge --broken --clocks fast2slow --inject   # ?
python run.py bridge --broken --clocks slow2fast            # ?
```

Read the errors, then read the RTL. Each bug is one of the three above. Watch
out for the part that looks wrong and isn't. The answers are in
[`SOLUTION.md`](SOLUTION.md), and the fixed bridge is `rtl/apb_bridge.sv`.

The bridge testbench also checks ep06's APB rules on every cycle: SETUP for
exactly one cycle, then ACCESS, and nothing moves during a wait state. Those
checks stay green on the broken bridge, because the protocol was never the
problem.

## What `run.py` prints

On Verilator (Icarus skips the two assertion rows):

```
== the three breaks, as the episode tells them, then the final lab ==
  ok   PASS Break 1, plain sim: green, and wrong
  ok   FAIL Break 1 + injection: sees a value never held       ERROR destination saw 0 (0000) right after 1 (0001) ...
  ok   FAIL Break 1 + Gray assertion: caught with no injection Assertion failed ... crossing word changed 2 bits at once (0001 -> 0010)
  ok   PASS Fix: cross it as Gray code
  ok   PASS Break 2, plain sim: green, and wrong
  ok   FAIL Break 2 + injection: a pairing that never happened ERROR destination sees en_a=0 en_b=1 ...
  ok   PASS Fix: cross the pair as one word (handshake)
  ok   PASS Break 3, slow->fast: the ratio hides it
  ok   FAIL Break 3, fast->slow: pulses lost                   ERROR sent 40 pulses, destination saw 12 -- 28 lost
  ok   FAIL Break 3 + width assertion: fires on the first pulse Assertion failed in tb_pulse.dut.u_width_chk.a_width ...
  ok   PASS Fix: cross a toggle, not the pulse
  ok   PASS Final lab, AXI fast / APB slow: green
  ok   FAIL Final lab + injection: caught                      ERROR AXI read to 0x0c reached APB as a write ...
  ok   FAIL Final lab, APB clock faster: caught                ERROR write 0x04: no response after 47 AXI cycles ...
  ok   PASS Fix: each direction crosses as one handshake

== regression: fixed designs, injection on, 10 random clock seeds each ==
  ok   bus        10/10 seeds pass
  ...
  ok   bridge     10/10 seeds pass

ALL AS EXPECTED
```

A `FAIL` marked `ok` is a run that was supposed to fail, and did. The script
exits non-zero if any break stops failing or any fix stops passing. In the
regression every assertion stays bound, so the fixes are also checked against
the rules in `sva/`.

## Setup

You need Python 3 and the free [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build/releases)
(Icarus Verilog + Verilator) on your `PATH`.

| simulator | what runs | needs |
|---|---|---|
| **Verilator 5** (preferred) | everything, including the SVA checkers | a C++ compiler and `make` (standard on Linux and macOS) |
| **Icarus Verilog** | every scoreboard test; the two assertion-only rows are skipped | nothing else |

`run.py` uses Verilator if it can build with it, and Icarus otherwise. To pick
one, pass `--sim icarus` or `--sim verilator`.

**On Windows**, Verilator needs a compiler: unpack [w64devkit](https://github.com/skeeto/w64devkit/releases)
and add its `bin` to your `PATH`. Adding it at the end keeps your shell's own
`sed` and friends in front of w64devkit's. `run.py` calls
`verilator_bin` directly, because the `verilator` launcher is a Perl script
that usually can't run there. Each Verilator build takes about 20 s, and a
full run takes a few minutes.

## What's in here

| file | episode | what it is |
|---|---|---|
| `rtl/sync_2ff.sv` | 3:15 | the two-flop synchronizer, with the sim-only metastability injector (`CDC_INJECT`), line for line as on screen |
| `rtl/rst_sync.sv` | 7:33 | reset synchronizer: assert async, release on the clock, as on screen |
| `rtl/broken/bus_xing_bad.sv` | 4:05 | **Bug 1**: a synchronizer on every bit of a binary bus |
| `rtl/broken/reconv_bad.sv` | 5:24 | **Bug 2**: reconvergence |
| `rtl/broken/pulse_sync_bad.sv` | 5:24 | **Bug 3**: a one-cycle pulse into a slower clock |
| `rtl/bus_xing.sv` | 4:42 | fix 1: a counter crossing as Gray code |
| `rtl/reconv_xing.sv` | 5:24 | fix 2: two related controls crossing as one word |
| `rtl/pulse_sync.sv` | 5:24 | fix 3: toggle synchronizer, so an event crosses as a level change |
| `rtl/handshake_sync.sv` | 4:42 | REQ/ACK handshake for any multi-bit word, used by fix 2 and the bridge |
| `rtl/async_fifo.sv` | 4:42 | async FIFO, the standard structure for streaming data: only Gray pointers cross |
| `rtl/broken/apb_bridge_bad.sv` | 0:50, ep06 | **final lab**: the AXI-to-APB bridge, two CDC bugs |
| `rtl/apb_bridge.sv` | 0:50, ep06 | the fixed bridge |
| `SOLUTION.md` | | the final lab's answers |
| `sva/cdc_sva.sv` | 6:56 | the rules as assertions: Gray one-bit, data stable under REQ, pulse width |
| `sva/cdc_bind.sv` | 6:56 | attaches them with `bind`, so no design file is edited |
| `tb/clk_cfg.sv` | 6:56 | the clock randomization class from the video |
| `tb/tb_*.sv` | | one self-checking testbench per crossing |
| `INTERVIEW.md` | 8:11 | the five "draw it, say how it breaks" questions |

Each testbench takes two unrelated clocks, chosen per seed under `clk_cfg`'s
rules: 1–20 ns each, a random phase, and either side may be the faster one.
Each domain comes out of reset through `rst_sync`.

## Try it by hand

```
python run.py bus --broken                      # PASS: plain sim is blind
python run.py bus --broken --inject             # FAIL: injection exposes it
python run.py pulse --broken --clocks slow2fast # PASS: this ratio hides it
python run.py pulse --broken --clocks fast2slow # FAIL: pulses lost
python run.py fifo --inject --seed 42           # one regression seed
python run.py --seeds 100                       # a longer regression
```

Things worth trying:

- Pull `gray_s` out of the register in `bus_xing.sv` and drive the synchronizer
  straight from `(cnt >> 1) ^ cnt`. This is the "logic before sync" violation
  from the static report. Why does no simulation here catch it?
- In `async_fifo.sv`, synchronize `wbin` instead of `wgray`. Which of the tests
  notices, and on how many seeds?
- Shorten `gap` in `tb_pulse.sv` until the toggle synchronizer starts losing
  events. That is its documented limit.
- After the final lab, run `python run.py bridge --broken` with no `--clocks`
  over a few seeds. Why does it pass on some and fail on others?

## What the injector models, and where it stops

`CDC_INJECT` makes each bit of a synchronizer deliver after 2 or 3 destination
edges, chosen independently per bit. That is exactly the uncertainty the video
describes. It breaks any logic that depended on an exact latency, and any word
whose bits were synchronized one by one.

It is a model, not silicon. A per-bit delay is exact for a word that changes at
most once per synchronizer window, like the counter, the handshake REQ and ACK,
and the toggle. A FIFO pointer coming from a much faster clock can move several
steps between two samples. The model can then mix bits from two different
steps, which real hardware never does, because only the bit changing at the
sampling edge can go metastable. The mixed value is still older than the live
pointer, so the FIFO stays conservative, and the regression passes 200 of 200
random-clock seeds with injection on. Commercial CDC tools go further and
inject only when the source edge actually lands near the destination edge.

The other half of the episode, static CDC analysis, needs a commercial tool and
isn't covered here. The rules it enforces are the ones `sva/` asserts and
`rtl/broken/` breaks. It would have flagged both bridge bugs without running a
single simulation.

## License

MIT. Use it in your own testbench, your coursework, or your interview prep.
