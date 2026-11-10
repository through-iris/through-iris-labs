// tb_common.svh -- shared by every testbench: two unrelated clocks, a reset
// per domain, and one place that decides PASS or FAIL.
//
// Clock periods and phase come in as plusargs (run.py picks them under the
// same rules as clk_cfg.sv: 1-20 ns each, either side may be faster, a random
// skew), so one compiled testbench covers every clock ratio.

int unsigned src_ps = 4000, dst_ps = 10000, skew_ps = 1234, seed = 1;
logic sclk = 1'b0, dclk = 1'b0, arst_n = 1'b0;
logic srst_n, drst_n;
int   errors = 0;

initial begin
  void'($value$plusargs("src_ps=%d", src_ps));
  void'($value$plusargs("dst_ps=%d", dst_ps));
  void'($value$plusargs("skew_ps=%d", skew_ps));
  void'($value$plusargs("seed=%d", seed));
  $display("[clk] src %0d ps, dst %0d ps (%s), skew %0d ps, seed %0d", src_ps, dst_ps,
           src_ps < dst_ps ? "fast->slow" : src_ps > dst_ps ? "slow->fast" : "equal", skew_ps, seed);
  fork
    forever #(src_ps / 2) sclk = ~sclk;
    begin #(skew_ps); forever #(dst_ps / 2) dclk = ~dclk; end
    begin #(3 * (src_ps + dst_ps)); arst_n = 1'b1; end   // reset, released asynchronously
  join_none
end

// watchdog: a design that deadlocks (a FIFO that never says empty, a
// handshake that never acks) must FAIL, not hang the regression
initial begin
  #(64'd2_000_000_000);                     // 2 ms of sim time, ~20x the longest test
  fail("watchdog: test did not finish -- something is stuck");
  finish_test("watchdog");
end

// each domain leaves reset through its own reset synchronizer (ep24, 7:33)
rst_sync u_srst (.clk(sclk), .arst_n(arst_n), .rst_n(srst_n));
rst_sync u_drst (.clk(dclk), .arst_n(arst_n), .rst_n(drst_n));

function automatic int unsigned rnd(input int unsigned lo, input int unsigned hi);
  rnd = lo + ($unsigned($random(seed)) % (hi - lo + 1));
endfunction

// source cycles that cover n destination cycles plus m source cycles
function automatic int unsigned src_cycles(input int unsigned n, input int unsigned m);
  src_cycles = (n * dst_ps + m * src_ps + src_ps - 1) / src_ps;
endfunction

task automatic fail(input string msg);
  errors++;
  if (errors <= 8) $display("[%0t ps] ERROR %s", $time, msg);
  if (errors == 8) $display("          (further errors counted, not printed)");
endtask

task automatic finish_test(input string name);
  if (errors == 0) $display("PASS %s", name);
  else             $display("FAIL %s (%0d errors)", name, errors);
  $finish;
endtask
