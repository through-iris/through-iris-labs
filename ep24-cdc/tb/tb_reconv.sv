// tb_reconv -- ep24 Break 2: reconvergence. The source sets en_a and en_b
// together and clears them together, so the destination must only ever see
// 00 or 11. 10 or 01 is a pairing that never happened at the source.
`timescale 1ps/1ps
module tb_reconv;
  `include "tb_common.svh"
  localparam int TOGGLES = 40;

  logic en_a = 1'b0, en_b = 1'b0, a_d, b_d, last_a = 1'b0;
`ifdef BROKEN
  reconv_bad  dut (.sclk, .srst_n, .en_a, .en_b, .dclk, .drst_n, .a_d, .b_d);
`else
  reconv_xing dut (.sclk, .srst_n, .en_a, .en_b, .dclk, .drst_n, .a_d, .b_d);
`endif

  int unsigned gap, seen = 0;
  logic run = 1'b0;

  initial begin
    wait (srst_n === 1'b1 && drst_n === 1'b1);   // either domain may leave reset first
    gap = src_cycles(12, 8);                     // room for a full handshake round trip
    repeat (4) @(posedge dclk);
    run = 1'b1;
    repeat (TOGGLES) begin
      repeat (gap) @(posedge sclk);
      {en_a, en_b} <= {2{~en_a}};                // always together
    end
    repeat (2 * gap) @(posedge sclk);
    if (seen != TOGGLES) fail($sformatf("destination saw %0d changes, source made %0d", seen, TOGGLES));
    finish_test("reconv");
  end

  always @(posedge dclk) if (run) begin
    if (a_d != b_d) fail($sformatf("destination sees en_a=%b en_b=%b -- the source never held that pair", a_d, b_d));
    else if (a_d != last_a) begin seen++; last_a <= a_d; end
  end
endmodule
