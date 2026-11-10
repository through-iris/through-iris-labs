# The ep24 interview set: draw it, then say how it breaks

The video closes on five CDC structures (8:11). For each one, an interviewer
wants two things: the picture, and the failure. Try answering before you
open the file.

### 1. Two-flop synchronizer -- `rtl/sync_2ff.sv`
**Draw:** two flops in series on the destination clock, nothing between them.
**Breaks:** latency is 2 *or* 3 cycles, depending on how the first flop resolved,
so logic that counts on an exact latency is wrong. Logic between the flops
steals settling time. Synthesis must not split, duplicate, or optimize the pair
(`ASYNC_REG`). Run `python run.py bus --broken --inject` to watch a per-bit
synchronized bus deliver a value it never held.

### 2. Gray code -- `rtl/bus_xing.sv`
**Draw:** a counter, binary to Gray, a register, then the synchronizer.
**Breaks:** only if more than one bit changes per step (a non-sequential jump),
or if the conversion is combinational logic between the source flop and the
synchronizer. The `gray_chk` assertion in `sva/cdc_sva.sv` states the rule.

### 3. Async FIFO -- `rtl/async_fifo.sv`
**Draw:** dual-port RAM in the middle, write pointer and read pointer each
Gray-coded and synchronized into the other domain, an extra wrap bit on each.
**Breaks:** synchronizing binary pointers, or synchronizing the data. Full and
empty use a stale copy of the other pointer, so they are conservative, never
wrong: full for a cycle too long, never an overflow.

### 4. Reconvergence -- `rtl/broken/reconv_bad.sv`
**Draw:** two related signals, each with its own (correct) synchronizer, meeting
again in destination logic.
**Breaks:** they can arrive a cycle apart, so the logic sees a combination that
never existed at the source. Fix: cross them as one word -- a handshake
(`rtl/reconv_xing.sv`) or a Gray-coded value -- or synchronize one signal and
fan it out after the synchronizer.

### 5. Reset synchronizer -- `rtl/rst_sync.sv`
**Draw:** two flops with async clear; the first one's D tied to 1.
**Breaks:** a reset released asynchronously can release different flops on
different edges. The answer is "assert asynchronously, release synchronously":
`tb/tb_rst.sv` checks both halves.

**Bonus, since it comes up:** a one-cycle pulse into a slower clock can vanish
between two edges (`rtl/broken/pulse_sync_bad.sv`). Cross a toggle instead
(`rtl/pulse_sync.sv`), and know its limit: two events closer than ~3
destination cycles cancel.
