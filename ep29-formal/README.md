# ep29 · Three ways a formal result lies

Companion code for **Through Iris ep29: Formal Verification Explained** (video link added at publish).

A formal tool gives three answers: proven, a counterexample, or a bound. The
episode's claim is that each of them can lie, and each lie has a check that
exposes it. This lab runs all three on the episode's own designs, with free
tools, and shows the numbers from the video: a 3-cycle counterexample, a proof
that checks nothing, and a FIFO bug on cycle 65 that a bound of 20 cannot see.

It ends with a final lab: a skid buffer with one planted bug for you to find.

```
python run.py
```

## The three breaks

| | what lies | why | what catches it | the fix |
|---|---|---|---|---|
| **1** | a **counterexample** for a bug that isn't there | no input assumptions, so the tool drives an illegal input: master 0 drops VALID mid-stall | read the trace: the *input* broke the rule first | assume the VALID rule on each input, assert it on the output (assume-guarantee). The re-run finds the **real** bug, the cold open's 3-cycle trace |
| **2** | a **proof** that checks nothing | `assume !(s0_valid && s1_valid)` deletes the only world the grant bug lives in | `cover (s0_valid && s1_valid)` comes back **unreachable** | delete the assumption; check the covers before believing any proof |
| **3** | a **bounded pass** read as a proof | a 6-bit counter in a 64-entry FIFO wraps on the 64th push; the first failure is on cycle 65, past a bound of 20 | an unbounded engine (fails on cycle 65); `cover full` unreachable at bound 20; shrinking to DEPTH 4 fails on cycle 5 | a 7-bit counter: proven at every depth |

## What `run.py` prints

```
Cycles count from reset = cycle 0. sby reports a clocked property on the step
after the cycle it sampled, so its 'step N' is cycle N-1 here and in the episode.

== Break 1: too few assumptions ==
  ok   FAIL    no input assumptions: a counterexample...                      as_m fails: step 3 = cycle 2  -> M0 dropped VALID mid-stall: illegal input, SPURIOUS  [2s]
  ok   FAIL    assume the VALID rule on the inputs: the real bug (cold open)  as_m fails: step 3 = cycle 2  -> inputs legal, grant flipped M0->M1 mid-stall: REAL  [3s]
  ok   PASS    fix: hold the grant during a stall -> proven                     [3s]

== Break 2: too many assumptions ==
  ok   PASS    bug back in + 'never both' assumption: proves anyway             [3s]
  ok   FAIL    the covers catch it: both-requesting is unreachable            co_both UNREACHED  [3s]
  ok   PASS    honest assumptions: every cover reached                        co_both reached: step 2 = cycle 1  (all 3 covers reached)  [3s]

== Break 3: too little depth ==
  ok   PASS    6-bit count, bounded to depth 20: passes                         [3s]
  ok   UNKNOWN k-induction at depth 20: inconclusive                            [3s]
  ok   FAIL    bounded to depth 80: the bug, on cycle 65                      as_not_empty fails: step 66 = cycle 65  [5s]
  ok   FAIL    an unbounded engine (abc pdr): cycle 65                        as_not_empty fails: step 66 = cycle 65  [5s]
  ok   PASS    fix: a 7-bit count -> proven at every depth                      [3s]
  ok   FAIL    guard 1: cover 'full' at bound 20 -> unreachable               co_full UNREACHED  [3s]
  ok   PASS    ...at bound 80: first full on cycle 65                         co_full reached: step 66 = cycle 65  [17s]
  ok   FAIL    guard 2: DEPTH 4, CW 2 -> the same bug, cycle 5                as_not_empty fails: step 6 = cycle 5  [3s]

== Final lab: find the bug in the skid buffer ==
  ok   FAIL    rtl/broken/skid_bad.sv: caught -- which line? (SOLUTION.md)    as_count fails: step 5 = cycle 4  [3s]
  ok   PASS    rtl/skid.sv: proven                                              [3s]
  ok   PASS    ...and its covers reached                                      co_drain reached: step 4 = cycle 3  (all 2 covers reached)  [3s]

ALL AS EXPECTED  (65 s)
```

A `FAIL` marked `ok` is a run that was supposed to fail, and did. `UNKNOWN`
marked `ok` is the inconclusive answer, which is also the right one there. The
script exits non-zero if any break stops failing or any fix stops passing. It
checks the cycle each failure lands on, not just the verdict. For the
arbiter's counterexamples it also reads the trace and says what it shows:
an illegal input (spurious) or legal inputs and a broken output (real).

**Steps and cycles.** Reset is cycle 0, as in the episode. SymbiYosys reports a
clocked property on the step *after* the cycle it sampled. So `step 3` in a log
is the trace's cycle 2, and the FIFO's `step 66` is cycle 65. `run.py` prints
both.

## Setup

You need Python 3 and the free [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build/releases)
on your `PATH`. It has SymbiYosys (`sby`), Yosys with the
[yosys-slang](https://github.com/povik/yosys-slang) SystemVerilog front end, and
the solvers (yices, abc). Nothing else is needed. The whole run takes about a
minute.

**On Windows** the suite's tools also need its `lib` folder. In Git Bash:

```
export PATH=/c/path/to/oss-cad-suite/bin:/c/path/to/oss-cad-suite/lib:$PATH
```

(`run.py` adds `lib` itself if it finds `sby`.) Or run the suite's
`environment.bat` in `cmd`.

## What's in here

| file | episode | what it is |
|---|---|---|
| `rtl/arb2.sv` | A2, B2 | the running example: two masters, one stream port, owner held during a stall (fixed) |
| `rtl/broken/arb2_bad.sv` | cold open, B2 | the same arbiter before the fix: the grant flips mid-stall |
| `rtl/fifo.sv` | B4 | 64-entry stream FIFO. `CW` is the counter width: 6 is the break, 7 the fix |
| `sva/arb2_props.sv` | C1 | the formal testbench: reset, assumes on the inputs, asserts on the output, covers, `bind` |
| `sva/fifo_props.sv` | B4 | `as_not_empty`, and `co_full`: "cover the deepest state you rely on" |
| `formal/arb2.sby` | B1–B3 | tasks `spurious`, `real`, `fixed`, `over`, `over_cov`, `cover` |
| `formal/fifo.sby` | B4 | tasks `bmc20`, `kind20`, `bmc80`, `pdr`, `fixed`, `cov20`, `cov80`, `small` |
| `rtl/broken/skid_bad.sv`, `rtl/skid.sv` | | **final lab**: a 2-entry skid buffer with one bug, and the fix |
| `sva/skid_props.sv`, `formal/skid.sby` | | its checker: the VALID rule, plus a scoreboard written as a property |
| `SOLUTION.md` | | the final lab's answer |
| `run.py` | | runs everything above in episode order and checks every result |

Every `.sby` task can be run by hand:

```
python run.py arb2 real          # one task: verdict, cycle, and what the trace shows
python run.py fifo bmc80
cd formal && sby -f arb2.sby real   # or sby itself; the trace is in arb2_real/engine_0/trace.vcd
```

Open a trace with `gtkwave build/arb2_real/engine_0/trace.vcd`. GTKWave is in
the suite.

## How close this is to the code on screen

The episode shows full SVA:

```systemverilog
as_m: assert property (@(posedge clk) disable iff (rst)
        m_valid && !m_ready |=> m_valid && $stable(m_data));
```

The free flow reads SystemVerilog through yosys-slang. That keeps everything
else the episode shows: concurrent `assert`, `assume` and `cover property`,
clocking, `disable iff`, `$past`, `$stable`, labels and `bind`. What it doesn't
support yet is the sequence operators `|=>`, `|->` and `##`. So each rule is the
same check written in one cycle:

```systemverilog
as_m: assert property (@(posedge clk) disable iff (rst)
        $past(m_valid && !m_ready && !rst) -> m_valid && $stable(m_data));
```

For a one-cycle antecedent, `a |=> b` and `$past(a) -> b` are the same
property. `&& !rst` inside `$past` keeps the reset cycle out, which is what
`disable iff` does to an attempt that starts in reset. Two other differences:

- **Reset.** On screen it's `initial assume (rst);`. yosys-slang can't read a
  net inside `initial`, so the checkers assume `rst == !started`, where
  `started` is a flop that is 0 in the first cycle only.
- **Liveness** (`s_eventually`, the episode's C2) is not in this lab. yosys-slang
  doesn't support it. Yosys's own parser has a liveness extension, but SymbiYosys
  only proves liveness with the `suprove` engine, which the Windows build of
  the suite doesn't ship. The bounded form the episode recommends,
  `##[0:MAX_WAIT]`, is an exercise below.

The plain `read_verilog -formal` parser accepts even less. It has no clocked
`assert property`, no `bind`, and no `|=>`. That's why this lab uses
yosys-slang.

## Try it

- **Break 1, half fixed.** Delete only `am_s1` from `sva/arb2_props.sv` and run
  `python run.py arb2 real`. Now a spurious trace and the real one are both 3
  cycles long, and the solver hands you whichever it finds first. Read the
  trace and decide which it is before you look at what `run.py` says. Then
  ask: with the RTL fixed, would this run ever pass?
- **Break 2, quieter.** Replace the over-constraint with
  `assume property (@(posedge clk) m_ready);`, a slave that is never busy,
  and run the `over` and `over_cov` tasks. The grant bug is still in. What
  proves now, and which cover tells you why?
- **Break 3, the bound.** The bug is on cycle 65. Set the `bmc80` task's
  `depth` to 65, 66 and 67 in `formal/fifo.sby`. Only 67 fails. Why two more
  than the cycle? (Hint: `depth N` covers steps 0 to N-1, and read the steps
  note above.)
- **Guard 2.** Change the `small` task to DEPTH 8, `AW=3`, `CW=3`. Predict the
  failing cycle before you run it.
- **A bounded wait.** Add `as_wait` to `arb2_props.sv`: once `s0_valid` is high,
  `s0_ready` within 4 cycles. Without `|->` and `##`, you need a small counter.
  It fails. Find the assumption it needs (hint: what if the slave never
  becomes ready?), add the weakest one that makes it pass, and add a cover to
  check you didn't overdo it.

## License

MIT. Use it in your own flow, your coursework, or your interview prep.
