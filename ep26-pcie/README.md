# ep26 · Three PCIe bugs where every packet is fine

Companion code for **Through Iris ep26: PCI Express for Verification** (video link added at publish).

The episode's claim is that a PCI Express bug rarely breaks a packet. It
breaks the bookkeeping around one. This lab runs the three bugs from the
video. Every packet in it is legal, and each run still goes wrong: an error
storm on a correct design, a link that stops for good, and a monitor that
counts writes that were never sent twice. Then it runs the fix for each one.

```
python run.py
```

## The three bugs

| | the bug | what you see | what catches it | the fix |
|---|---|---|---|---|
| **1** | a read scoreboard that expects one completion per read | a 512-byte read comes back as 192 + 256 + 64 bytes: "short read", then two "unexpected CplD" on a correct design | the completer was allowed to split | track bytes owed per tag, check Byte Count and Lower Address, retire at zero: `tb/tb_split.sv` |
| **2** | a receiver that keeps the credit of a write it discards as Unsupported Request | 2,312 writes, then nothing, forever. No error, no timeout | an end-of-test check that every credit type is back where it started | the discard path returns the credit too: `rtl/fc_rx.sv` |
| **3** | a scoreboard fed by a monitor on the wire | TLP 12 is corrupted and replayed with 13 and 14: the wire shows 8 good writes, the receiver accepted 6 | watching what the transaction layer accepts | feed the scoreboard from above the data link layer: `tb/tb_replay.sv` |

Break 1 and Break 3 are testbench bugs on a correct design. Only Break 2 is in
the RTL, and its packets are legal too.

## What `run.py` prints

```
== the three breaks, as the episode tells them ==
  ok   FAIL Break 1: the scoreboard that expects one           [cycle 3] ERROR short read: tag 5 asked for 512 bytes, got 192
  ok   PASS Fix: track bytes per tag, retire at zero
  ok   FAIL Break 2: the cold open, 2312 writes then nothing   [cycle 4236] ERROR hang: 2312 of 5000 writes sent, the last on cycle 3235, then nothing moved fo
  ok   FAIL Break 2 + end-of-test credit check                 [cycle 214] ERROR credits leaked: PH 7 of 8 back, PD 62 of 64 back, after traffic drained
  ok   PASS Fix: a discarded write gives its credit back
  ok   FAIL Break 3: a wire monitor counts the replay          [cycle 9] ERROR MWr seq 13 counted twice (wire monitor)
  ok   PASS Fix: the scoreboard watches the transaction layer

== regression: fixed designs and checkers, 10 random seeds each ==
  ok   split    10/10 seeds pass
  ok   credit   10/10 seeds pass
  ok   replay   10/10 seeds pass

ALL AS EXPECTED
```

A `FAIL` marked `ok` is a run that was supposed to fail, and did. The script
exits non-zero if any break stops failing or any fix stops passing. That
output is from Icarus. Verilator draws its random numbers in a different
order, so some counts differ there: the `PD 62 of 64` in the credit check,
for example. The three breaks fail the same way on both simulators.

Every testbench ends a run that stops moving. The run fails with a `hang:`
line saying how far it got, instead of waiting forever.

The numbers are the episode's numbers:
- **Break 1:** tag 5, 512 bytes at 0x2040, Max_Payload_Size 256, Read Completion Boundary 64.
- **Break 2:** 8 posted-header credits. Seed 26 draws which writes miss every BAR exactly as the episode's model does, so the hang lands after the same 2,312 writes.
- **Break 3:** TLPs 10 to 15, with the first copy of 12 corrupted.

## Setup

You need Python 3 and the free [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build/releases)
on your `PATH`. The testbenches are plain SystemVerilog, with no UVM, and run
on either simulator:

| simulator | needs |
|---|---|
| **Verilator 5** (preferred) | a C++ compiler and `make` (standard on Linux and macOS) |
| **Icarus Verilog** | nothing else; the full run takes about a minute |

`run.py` uses Verilator if it can build with it, and Icarus otherwise. Pass
`--sim icarus` or `--sim verilator` to pick one. **On Windows**, Verilator
needs [w64devkit](https://github.com/skeeto/w64devkit/releases) on your
`PATH` (add it at the end). `run.py` calls `verilator_bin` directly, because
the `verilator` launcher is a Perl script that usually can't run there.

## What's in here

| file | episode | what it is |
|---|---|---|
| `rtl/completer.sv` | B1 | answers reads with completions, split at Max_Payload_Size and on the RCB, tags interleaved |
| `rtl/fc_rx.sv` | B3 | posted-write flow control on the receive side: header and data credits, BAR decode, UR discard |
| `rtl/broken/fc_rx_bad.sv` | B3, cold open | **Bug 2**: the same receiver with one line changed |
| `rtl/dll_tx.sv` | B4 | data link layer, sending side: sequence numbers, the replay buffer, ACK/NAK, the replay timer |
| `rtl/dll_rx.sv` | B4 | data link layer, receiving side: accept only the next sequence number with a good LCRC |
| `tb/tb_split.sv` | B1, B2, C2 | the read scoreboard. `-DBROKEN` is **Bug 1**, the one that expects one completion; the fix is the one on screen in C2, plus a completion timeout |
| `tb/tb_credit.sv` | B3, C3 | a saturating write stream, and the end-of-test credit check from C3 |
| `tb/tb_replay.sv` | B4, C1 | wire monitor, transaction-layer monitor, and a link monitor with C1's three rules. `-DBROKEN` is **Bug 3**, the scoreboard fed from the wire |
| `tb/tb_common.svh` | | the clock, reset, seeded random, PASS/FAIL |

Scene ids (A1–C4) are the episode's sections, in order.

## Try it by hand

```
python run.py split --broken --story          # FAIL: three completions, one expected
python run.py credit --broken --seed 26 --nocheck
python run.py credit --broken --seed 26 --writes 200
python run.py replay --broken --story         # FAIL: 13 and 14 counted twice
python run.py --seeds 100                     # a longer regression
```

Things worth trying:

- Run `credit --broken --nocheck` for seeds 1 to 10. Most of them hang, each
  at a different write count, but seeds 2 and 10 pass. Work out why, by
  counting how many writes miss every BAR in each seed. Then run seed 2
  again without `--nocheck`. Which check still catches the bug?
- In `fc_rx.sv`, return the data credits rounded down instead of up. Which
  check fails, and how many writes does it take?
- In `dll_tx.sv`, delete the replay timer. The story still passes, but most
  random seeds now end in `hang: ... TLPs waiting on an ACK`. Pick one and
  work out which TLP was lost for good. (Hint: what happens when a replayed
  TLP is corrupted too, and why doesn't the receiver NAK it again?)
- Make the wire monitor in `tb_replay.sv` correct without moving it: apply
  the receiver's two rules (good LCRC, next sequence number) in the monitor
  itself, as C1 says to when the wire is all you can tap.

## What the model leaves out

This is the transaction and data link layers, one packet per clock. There is
no physical layer (training, encoding, lanes), which C1 leaves to the VIP.
Flow control models posted header and data credits only; non-posted and
completion credits work the same way. DLLPs are never corrupted here, so the
replay timer is exercised only by a replay that is itself corrupted. Reads
are whole double words, so the first and last byte enables are always full.

## License

MIT. Use it in your own testbench, your coursework, or your interview prep.
