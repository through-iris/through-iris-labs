# ep20 · A complete AXI VIP, and three ways it goes green without checking

Companion code for **Through Iris ep20: Build a Complete AXI UVM Verification IP From Scratch** (video link added at publish).

The episode's claim is that the components aren't the VIP. The connections
are. This lab is the whole VIP from the video: agent, scoreboard, coverage,
register model, protocol assertions, env, virtual sequence and test, around a
small AXI4 slave. Then it breaks one connection at a time. In each break the
two numbers the episode tells you to read come out green, zero mismatches and
100% coverage, and the run is still wrong. Each one is caught by a different
piece of the VIP. Then it runs the fix for each one.

```
python run.py
```

## Not the UVM library

The episode is UVM. This lab runs on a free simulator with nothing to
download, and there is no UVM library in the OSS CAD Suite. So
`vip/uvm_lite.sv` is a small stand-in, about 600 lines, with UVM's names and
shape: `uvm_component` and its phases, objections, the factory
(`type_id::create`, `set_type_override`), `uvm_config_db`, analysis ports,
a sequencer and sequences, and a register model with a map, an adapter and a
mirror. It is **not** UVM and doesn't try to be complete. Each class does the
one job this lab needs from it. What it buys you is that the VIP code reads
like the code on screen: `class axi_env extends uvm_env`,
`agt.mon.ap.connect(sb.analysis_export)`,
`ral.map.set_sequencer(agt.seqr, adapter)`, `phase.raise_objection(this)`.
The differences from the screen are listed below, under "How close this is
to the code on screen".

## The three bugs

| | the bug | what you see | what catches it | the fix |
|---|---|---|---|---|
| **1** | coverage was added by copying the scoreboard's `connect` line, and the original line went with it | 0 mismatches, 100% covered. The scoreboard was never sent a transaction, so it never had one to get wrong | `check_phase` in the test: the scoreboard must have compared every transaction the monitor broadcast | `agt.mon.ap.connect(sb.analysis_export)`: `vip/axi_env.svh` |
| **2** | a register adapter that drives `WSTRB = 4'hF` whatever the byte enables say | 0 mismatches, 100% covered. The slave did exactly what the pins said, and the scoreboard agrees. But `ral.ctrl.en.write(1)` was a full-word write, and it put `ctrl.mode` back to 0 | reading the register back by name and checking it against the mirror: `ral.mirror(status, UVM_CHECK)` | the adapter passes `rw.byte_en` to `WSTRB`: `vip/axi_reg_block.svh` |
| **3** | a driver that drops `WVALID` while the slave is busy, then tries again | 0 mismatches, 100% covered. This slave only acts on VALID and READY together, so it takes every beat correctly. The monitor samples on the handshake, so it rebuilds the right transaction | the protocol assertions on the raw pins: `WVALID dropped before WREADY` | idle time goes before VALID; once VALID is up it stays up until READY: `vip/axi_driver.svh` |

All three are VIP bugs on a correct design. None of them is in the RTL, and
each one leaves the scoreboard and coverage green. That's the point of the
episode's parts list: each part catches something the other parts can't.

Each break is the same test with one component swapped in through the
factory (C1). The env file is never edited:

```systemverilog
class axi_test_backoff extends axi_test;
  function void build_phase(uvm_phase phase);
    axi_driver::type_id::set_type_override(axi_driver_backoff::get_type());
    super.build_phase(phase);
  endfunction
endclass
```

## What `run.py` prints

```
== the three breaks: both numbers green, and still wrong ==
  ok   FAIL Break 1: coverage subscribed, scoreboard not   0 mismatches, 100.0% covered   ERROR test: scoreboard compared 0 of the 317 transactions the monitor broadcast
  ok   PASS Fix: connect the monitor to both               0 mismatches, 100.0% covered
  ok   FAIL Break 2: an adapter that drops byte enables    0 mismatches, 100.0% covered   ERROR RegModel: ral.ctrl read back 0x00000001, mirror says 0x00000101: mode is 0, model says 1
  ok   PASS Fix: the adapter passes byte_en to WSTRB       0 mismatches, 100.0% covered
  ok   FAIL Break 3: a driver that backs off when stalled  0 mismatches, 100.0% covered   ERROR axi_sva: WVALID dropped before WREADY
  ok   PASS Fix: once VALID is up, hold it until READY     0 mismatches, 100.0% covered

== regression: the fixed VIP, 10 random seeds ==
  ok   axi_test   10/10 seeds pass

ALL AS EXPECTED
```

A `FAIL` marked `ok` is a run that was supposed to fail, and did. The script
exits non-zero if any break stops failing or any fix stops passing. The
middle column is the two numbers from the end of each run. They read the
same on every row, and three of those rows are wrong.

The three fix rows run the same configuration: `axi_test` on seed 1, with no
override. The VIP is built once. A break is only a different
`+UVM_TESTNAME`.

Every run ends if it stops moving. If the test still holds its objection and
nothing handshakes on any channel for 2,000 cycles, the run fails with a
`hang:` line that says what the driver was waiting for. A run that spins
without advancing time is stopped by `run.py` after 300 s.

## Follow one write

`--journey` prints the episode's two paths for one transaction each: B3's
register path, a named field write turned into AXI traffic, and B1/B2's
write from the sequence to the pins and back to both subscribers.

```
[cycle 53] test       ral.ctrl.mode.write(status, 1)
[cycle 53] RAL        ral.ctrl.mode is at 0x0004: data 0x00000100, byte enables 0010
[cycle 53] sequencer  hands the driver: write 0x0004, 1 beat, WSTRB 2
[cycle 54] driver     AW: 0x0004, AWLEN 0, taken
[cycle 57] driver     W beat 1 of 1: 0x00000100, WSTRB 2, WLAST
[cycle 59] DUT        responds: BRESP OKAY
[cycle 59] monitor    rebuilt from the pins: write 0x0004, 1 beat, WSTRB 2, OKAY -> analysis port, 2 subscribers
[cycle 59] scoreboard OKAY, as the reference model predicted: pass
[cycle 59] coverage   sampled: write, 1 beat, OKAY, partial strobes -- coverage now 80.6%
[cycle 59] RAL        ral.ctrl: the bus said OKAY, mirror updated to 0x00000100
[cycle 78] vseq       creates write 0x23b8, 7 beats, WSTRB 8 f 5 f f f f
[cycle 78] sequencer  hands the driver: write 0x23b8, 7 beats, WSTRB 8 f 5 f f f f
[cycle 79] driver     AW: 0x23b8, AWLEN 6, taken
[cycle 80] driver     W beat 1 of 7: 0xff162184, WSTRB 8
[cycle 81] driver     W beat 2 of 7: 0xcdeb254c, WSTRB f
[cycle 83] driver     W beat 3 of 7: 0x8845ae94, WSTRB 5
[cycle 84] driver     W beat 4 of 7: 0xe34ca4e8, WSTRB f
[cycle 86] driver     W beat 5 of 7: 0x9159ecd0, WSTRB f
[cycle 90] driver     W beat 6 of 7: 0x6ebe0e00, WSTRB f
[cycle 92] driver     W beat 7 of 7: 0x88ef4d2b, WSTRB f, WLAST
[cycle 95] DUT        responds: BRESP OKAY
[cycle 95] monitor    rebuilt from the pins: write 0x23b8, 7 beats, WSTRB 8 f 5 f f f f, OKAY -> analysis port, 2 subscribers
[cycle 95] scoreboard OKAY, as the reference model predicted: pass
[cycle 95] coverage   sampled: write, 7 beats, OKAY, partial strobes -- coverage now 86.1%
[report] 0 mismatches, 100.0% covered | scoreboard compared 317 of 317 | RAL checks 8, 0 wrong | protocol violations 0
PASS axi_test
```

## Setup

You need Python 3 and the free [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build/releases)
on your `PATH`.

| simulator | needs |
|---|---|
| **Verilator 5** | a C++ compiler and `make` (standard on Linux and macOS). The constraint solver Verilator calls for `randomize()`, `z3`, ships in the suite |
| **Icarus Verilog** | not supported. The VIP is classes with constraints, mailboxes, virtual interfaces and a covergroup, and Icarus doesn't support those yet. `--sim icarus` says so and stops |

This is the only lab in the repo that is Verilator-only, the way ep29 is
SymbiYosys-only. The VIP builds once, which takes about a minute, and then
each run takes about 3 seconds. The full `run.py` takes about two minutes.

**On Windows**, Verilator needs [w64devkit](https://github.com/skeeto/w64devkit/releases)
on your `PATH` (add it at the end). `run.py` calls `verilator_bin` directly,
because the `verilator` launcher is a Perl script that usually can't run
there.

## What's in here

| file | episode | what it is |
|---|---|---|
| `rtl/axi_slave.sv` | A1, B1, B3 | the DUT: an AXI4 slave with ID, CTRL, BASE and STATUS registers and a 1 KB memory window that BASE places and CTRL.EN switches on |
| `tb/axi_if.sv` | A1 | the virtual interface: the five AXI channels |
| `tb/tb_top.sv` | A1, C3 | clock, reset, the DUT, the interface into `uvm_config_db`, the hang watchdog, `run_test()` |
| `sva/axi_sva.sv` | A2, B2 | the protocol assertions (ep05): VALID held until READY, payload stable, WLAST and RLAST on the right beat, IDs echoed, no 4 KB crossing |
| `vip/uvm_lite.sv`, `vip/uvm_lite_macros.svh` | | the UVM stand-in described above |
| `vip/axi_seq_item.svh` | B1 | the transaction: an address, data, a burst, with constraints; and `axi_cfg`, the test's settings |
| `vip/axi_driver.svh` | A2, B1 | the driver (ep08): items to pins, every handshake honoured |
| `vip/axi_monitor.svh` | A2, A3, B1 | the monitor: pins to transactions, broadcast on `ap` |
| `vip/axi_agent.svh` | A2 | sequencer, driver and monitor in one agent |
| `vip/axi_scoreboard.svh` | A2, B2 | reference model and checker (ep10): predicts every response and every read beat |
| `vip/axi_coverage.svh` | A2, B2 | the covergroup (ep11): kind, burst length, response, strobes, two crosses. 22 bins |
| `vip/axi_reg_block.svh` | A2, B3 | the register model (ep04) and `axi_reg_adapter` |
| `vip/axi_env.svh` | C1, C2 | `build_phase` and `connect_phase`, as on screen |
| `vip/axi_vseq.svh` | B1, B3, C3 | the virtual sequence: traffic before the window is on, configuration by name, read-back, random traffic, read-back |
| `vip/axi_test.svh` | C3, B4 | the test, its two numbers and the count beside them, and the three break tests |
| `vip/broken/axi_env_no_sb.svh` | A3, C2 | **Bug 1**: the env with one `connect` line missing |
| `vip/broken/axi_reg_adapter_no_strb.svh` | B3, C2 | **Bug 2**: the adapter with one line changed |
| `vip/broken/axi_driver_backoff.svh` | B1, B2 | **Bug 3**: the driver's W beat, backing off |
| `vip/axi_vip_pkg.sv` | | the package that includes the VIP files in build order |

Scene ids (A1–C4) are the episode's sections, in order. The episode has no
breaks of its own. Each of these lands on one of its lines: A3's "the
connections are the VIP", B3's "a later read-back can be checked against
what the test believes is there", and B2's assertions that fire "whether or
not any transaction completed".

### The slave

| address | register | access | reset | |
|---|---|---|---|---|
| `0x0000` | ID | RO | `0x4158_4931` | "AXI1" |
| `0x0004` | CTRL | RW | `0` | `[0]` EN: the window answers (else SLVERR); `[9:8]` MODE: wait states before BVALID and the first RVALID |
| `0x0008` | BASE | RW | `0x1000` | `[15:12]` PAGE: the window sits at PAGE × 4 KB |
| `0x000C` | STATUS | RO | `1` | |
| BASE + `0x000`–`0x3FF` | memory | RW | `0` | 256 words, writes honour WSTRB |

Anything else answers DECERR, and a write to ID or STATUS answers SLVERR.
`tb_top` makes the slave drop every READY on a random 25% of cycles, so every
handshake gets a stall.

## How close this is to the code on screen

`axi_env`'s `connect_phase` is the C2 code line for line. `build_phase` is
C1's four `create` calls plus two lines a register model needs:
`ral.build()`, and creating the `adapter` that C2 passes to
`set_sequencer`. The test's `run_phase` is C3's:

```systemverilog
phase.raise_objection(this);
axi_vseq::type_id::create("vs").start(env.agt.seqr);
phase.drop_objection(this);
```

The test's `build_phase` gets the virtual interface from `uvm_config_db`
first, because `tb_top` puts it there, then sets it for `"*"` as on screen.
It also randomizes and sets an `axi_cfg`: the base page, the mode, the
driver's idle gaps. That's the "different config" C3 says a new test is.

Two things from the episode are simplified:

- **The virtual sequence** runs on the one agent's sequencer, as C3's code
  does. With one agent there are no other sequencers for it to coordinate.
- **RAL prediction** is auto-predict: the mirror follows each access when
  the bus answers OKAY. UVM can also run a separate predictor off the
  monitor. With one master the two give the same mirror.

## Try it by hand

```
python run.py axi_test --journey             # follow one register write and one write
python run.py axi_test_no_strb               # FAIL: the read-back sees MODE lost
python run.py axi_test_backoff --busy 0      # FAIL: the slave is never busy, and still
python run.py axi_test --seed 7 --busy 60 --txns 1000
python run.py --seeds 100                    # a longer regression
```

Things worth trying:

- Make the slave ignore WSTRB on memory writes (the ep04 bug: `mem[...] <= wdata`
  in `rtl/axi_slave.sv`). Run `axi_test`: the scoreboard catches it. Now run
  `axi_test_no_sb`. Which error is left, and what would the log have said if
  the test had no `check_phase`?
- Break 2 is caught by the first read-back. The read-back at the end of the
  sequence passes, even though MODE is still wrong. Why? (Hint: what does
  `mirror()` do to the mirror after it compares?)
- `axi_test_backoff --busy 0` still fails, with a slave that is never busy.
  Find the cycle the first `WVALID dropped` fires on and read the pins there.
  What is the slave waiting for? (It's allowed to wait for it.) Then make
  the backoff driver start each W beat only after AW is taken. Does it pass
  now, and is the driver fixed?
- Make the slave's BVALID wait for BREADY:
  `assign bvalid = ... && bready;`. Every check here stays green, because
  this driver raises BREADY without waiting for BVALID. It is still an AXI
  violation: a source must not wait for READY before it asserts VALID. Make
  the driver hold BREADY low until it sees BVALID. What happens, and which
  line tells you?
- Add a third subscriber, a transaction logger that prints every write to
  the register page, to `connect_phase`. Check that you didn't touch the
  scoreboard or the coverage collector to do it (B2).
- Add a coverpoint for the region a transaction went to (registers, window,
  unmapped). Does the sequence still reach 100%? If not, is the coverage
  model wrong, or the sequence?

## What the model leaves out

One master, one transaction at a time: no outstanding transactions or
out-of-order IDs (ep03). INCR bursts of 1 to 8 beats, 4 bytes a beat, no
WRAP, FIXED, narrow or exclusive accesses. The slave decodes a burst on its
first address, and the sequences never let one leave its region. The agent
is always active. `uvm_lite` has no report server controls, sequence
arbitration other than FIFO, TLM FIFOs, callbacks, register backdoor, or
predictor component. Coverage uses Verilator's own covergroup support,
which reports the total but not per-bin holes yet, so a hole is reported as
a number below 100%.

## License

MIT. Use it in your own testbench, your coursework, or your interview prep.
