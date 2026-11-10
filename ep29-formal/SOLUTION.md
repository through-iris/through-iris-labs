# Final lab: the solution

Spoilers for `rtl/broken/skid_bad.sv`. Run `python run.py skid bad` first, and
open the trace it leaves in `build/skid_bad/engine_0/trace.vcd` (GTKWave is in
the OSS CAD Suite). The trace is the clue.

## What fails, and what doesn't

```
FAIL skid/bad  as_count fails: step 5 = cycle 4
```

`as_m`, the VALID rule on the output, still holds. The buffer never changes
its output during a stall. What breaks is `as_count`: the checker counted more
words going in than the buffer is holding. A word was accepted and then lost.

## The trace, cycle by cycle

| cycle | what happens |
|---|---|
| 0 | reset |
| 1 | a word arrives, the output register is free: it goes to the output |
| 2 | a second word arrives, the output is stalled: it is parked in the skid register |
| 3 | a third word arrives **and** the output is ready. `s_ready` is high, so the word is accepted. The output takes the parked word |
| 4 | the third word is nowhere. `held` is 2, the buffer holds 1. `as_count` fails |

## The bug

```systemverilog
// accept a new word if there is room -- or if the output is draining anyway
assign s_ready = !sk_valid || m_ready;
```

It looks like an optimization. If the output is draining this cycle, there
will be room next cycle, so why not accept now? Because next cycle is too late.
On cycle 3 the only free register, the output, is taken by the parked word.
The new word has nowhere to go, and the `always_ff` block has no branch that
stores it. The fix is the line the comment talks you out of:

```systemverilog
assign s_ready = !sk_valid;
```

That costs one cycle of throughput, once, when the skid register drains. To
keep that cycle, the drain branch must move the parked word to the output
**and** park the new word in the same cycle. That's a real redesign, and the
same checker proves it or finds the trace.

## Why the episode's checker alone would not have caught it

The arbiter in the episode only needed the VALID rule. A buffer can keep that
rule perfectly and still drop data. That is a different kind of bug: data
integrity, not protocol. So the final lab adds one more property, a scoreboard
written as a property: words accepted minus words delivered must equal the
words held. Four lines, no transaction model, and formal checks it on every
cycle of every input sequence.

It is also a reachability lesson. The bug needs three things on one cycle: a
parked word, a ready output, and a new word arriving. A random test with a
mostly-ready slave rarely parks a word at all.
