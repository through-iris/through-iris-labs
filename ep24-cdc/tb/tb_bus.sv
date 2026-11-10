// tb_bus -- ep24 Break 1: a 4-bit counter crossing clocks.
// The source counts 0..15 and wraps; the destination must only ever see the
// value it saw last or the next one. 15 straight after 7 is the "value the
// counter never held" from the episode.
//
// Pacing: the counter steps at most once per ~4 destination cycles, so every
// value is visible for several cycles and any other value is a real error.
`timescale 1ps/1ps
module tb_bus;
  `include "tb_common.svh"
  localparam int W = 4, STEPS = 64;     // four laps, so 7->8 and 15->0 cross 4 times each

  logic [W-1:0] cnt = '0, cnt_d, last = '0;
`ifdef BROKEN
  bus_xing_bad #(W) dut (.sclk, .srst_n, .cnt, .dclk, .drst_n, .cnt_d);
`else
  bus_xing     #(W) dut (.sclk, .srst_n, .cnt, .dclk, .drst_n, .cnt_d);
`endif

  int unsigned gap, seen = 0;
  logic run = 1'b0;

  initial begin
    wait (srst_n === 1'b1 && drst_n === 1'b1);   // either domain may leave reset first
    gap = src_cycles(4, 2);
    repeat (4) @(posedge dclk);
    run = 1'b1;
    repeat (STEPS) begin
      repeat (gap) @(posedge sclk);
      cnt <= cnt + 1'b1;
    end
    repeat (2 * gap) @(posedge sclk);
    if (seen != STEPS) fail($sformatf("destination saw %0d steps, source made %0d", seen, STEPS));
    finish_test("bus");
  end

  always @(posedge dclk) if (run) begin
    if (cnt_d == last + 1'b1) begin seen++; last <= cnt_d; end
    else if (cnt_d != last)             // a glitch: report it, keep the last good value
      fail($sformatf("destination saw %0d (%b) right after %0d (%b) -- a value the counter never held there",
                     cnt_d, cnt_d, last, last));
  end
endmodule
