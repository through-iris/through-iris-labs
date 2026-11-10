# Final lab: the solution

Spoilers for `rtl/broken/apb_bridge_bad.sv`. Run the three commands in its
header first, and read the error messages. They are the clues.

## Bug 1: the direction bit got its own synchronizer (Break 2, reconvergence)

```systemverilog
sync_2ff #(1) u_tog (.clk(pclk), .rst_n(presetn), .d(tog_a), .q(tog_s));
sync_2ff #(1) u_dir (.clk(pclk), .rst_n(presetn), .d(dir_a), .q(dir_s));
...
if (tog_s != tog_q) begin
  psel <= 1'b1; pwrite <= dir_s; ...
```

The request toggle and the direction bit change on the same `aclk` edge. Each
gets its own two-flop synchronizer, and the APB side uses them together. In
plain simulation both synchronizers take exactly two cycles, so `dir_s` is
always ready when the toggle arrives. In silicon, each one takes 2 *or* 3
cycles on its own. When the toggle wins, the APB transfer launches with the
*previous* transaction's direction:

```
ERROR AXI write to 0x0c reached APB as a read to 0x0c
```

That error only shows up when the direction changes between two transactions,
which is why the testbench counts direction changes in its `[cov]` line.

It looks safe, which is what makes it a good bug. Everyone knows a control bit
crossing a clock needs a synchronizer, and `dir_a` got one. The mistake is that
two synchronized bits get used as a pair.

## Bug 2: "done" crosses back as a one-cycle pulse (Break 3, short pulses)

```systemverilog
done_p <= 1'b1;            // for one pclk cycle
...
sync_2ff #(1) u_done (.clk(aclk), .rst_n(aresetn), .d(done_p), .q(done_s));
```

The designer assumed APB is always the slow side. At that ratio a one-`pclk`
pulse lasts several `aclk` cycles, and it is always seen. Run the APB clock
faster than the AXI clock, which a low-power mode or a later SoC can easily do,
and the pulse falls between two `aclk` edges. The response is never
delivered and the AXI master waits forever:

```
ERROR read 0x20: no response after 47 AXI cycles -- the transaction was lost
```

`python run.py bridge --broken` (random clocks, no injection) fails on about
half the seeds, which is the half where `pclk` is faster.

## The part that is NOT a bug

```systemverilog
psel <= 1'b1; pwrite <= dir_s; paddr <= addr_a; pwdata <= wdata_a;
```

`addr_a` and `wdata_a` come straight from the `aclk` domain with no
synchronizer, and that is correct. They were registered on the same edge as the
toggle and do not change again until the next transaction, so by the time the
toggle has crossed they have been stable for 2+ cycles. That is the
handshake's rule from 4:42: hold the data, cross one bit, sample the data. The
same goes for `rdata_p` and `slverr_p` on the way back.

So the fix is not "add more synchronizers". It is to cross *fewer* bits. Bug 1
is the opposite mistake: `dir_a` should have been sampled like `addr_a`, with
no synchronizer at all.

## The fix: `rtl/apb_bridge.sv`

Each direction crosses through one `handshake_sync` as one word:
`{write, addr, wdata}` goes over and `{slverr, rdata}` comes back. One request
bit and one acknowledge cross in each direction, and every other bit is
sampled while it is held. It passes with injection on, at every clock ratio.

A static CDC tool would have flagged both bugs without a single simulation:
two synchronizers converging in `pclk` logic (reconvergence), and a pulse
crossing into a domain that may be slower (pulse width). That is the episode's
6:09 point. Simulation only finds them if you make it less blind.
