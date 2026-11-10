// tb_rst -- rst_sync: reset must ASSERT the moment the raw reset falls (no
// clock needed) and RELEASE only on a clock edge -- the second one after the
// raw reset rises. Twenty resets at random, non-edge-aligned times.
`timescale 1ps/1ps
module tb_rst;
  int unsigned per = 7000, seed = 1;
  logic clk = 1'b0, arst_n = 1'b1, rst_n;
  int   errors = 0;
  time  last_edge = 0;

  rst_sync dut (.clk, .arst_n, .rst_n);

  function automatic int unsigned rnd(input int unsigned lo, input int unsigned hi);
    rnd = lo + ($unsigned($random(seed)) % (hi - lo + 1));
  endfunction
  task automatic fail(input string msg);
    errors++;
    if (errors <= 8) $display("[%0t ps] ERROR %s", $time, msg);
  endtask

  initial begin #(64'd2_000_000_000); $display("FAIL rst (watchdog)"); $finish; end
  always @(posedge clk) last_edge = $time;
  always @(posedge rst_n)                         // release only ever on a clock edge
    if ($time != last_edge) fail("rst_n released between clock edges");

  initial begin
    void'($value$plusargs("dst_ps=%d", per));
    void'($value$plusargs("seed=%d", seed));
    $display("[clk] clk %0d ps, seed %0d", per, seed);
    fork forever #(per / 2) clk = ~clk; join_none
    repeat (20) begin
      @(posedge clk); #(rnd(1, per - 1));         // anywhere but on an edge
      arst_n = 1'b0;
      #1 if (rst_n !== 1'b0) fail("reset did not assert asynchronously");
      repeat (rnd(1, 4)) @(posedge clk);
      #(rnd(1, per - 1)) arst_n = 1'b1;
      @(posedge clk); #1 if (rst_n !== 1'b0) fail("released on the first edge -- one flop short");
      @(posedge clk); #1 if (rst_n !== 1'b1) fail("not released on the second edge");
      repeat (rnd(0, 5)) @(posedge clk);
    end
    if (errors == 0) $display("PASS rst");
    else             $display("FAIL rst (%0d errors)", errors);
    $finish;
  end
endmodule
