// tb_fifo -- the async FIFO under unrelated clocks: fill it to full, drain
// it to empty (three laps), then random traffic both ways. Every word must
// come out once, in order, unchanged; full and empty must both be reached.
// Here sclk is the write clock and dclk the read clock.
`timescale 1ps/1ps
module tb_fifo;
  `include "tb_common.svh"
  localparam int DW = 8, AW = 3, WORDS = 400, LAPS = 3;
  typedef enum {FILL, DRAIN, MIX} mode_t;

  logic          winc = 1'b0, rinc = 1'b0, wfull, rempty;
  logic [DW-1:0] wdata = '0, rdata;
  logic [DW-1:0] sent [0:WORDS-1];
  int unsigned   nw = 0, nr = 0, full_blocked = 0, empty_blocked = 0;
  mode_t         mode = FILL;

  async_fifo #(DW, AW) dut (.wclk(sclk), .wrst_n(srst_n), .winc, .wdata, .wfull,
                            .rclk(dclk), .rrst_n(drst_n), .rinc, .rdata, .rempty);

  // write side
  always @(posedge sclk) if (srst_n && drst_n) begin
    if (winc && !wfull) begin sent[nw] = wdata; nw++; end
    if (winc &&  wfull) full_blocked++;
    winc  <= (nw + (winc && !wfull) < WORDS) && (mode == FILL || (mode == MIX && rnd(0, 1) == 1));
    wdata <= DW'(rnd(0, 255));
  end

  // read side
  always @(posedge dclk) if (srst_n && drst_n) begin
    if (rinc && !rempty) begin
      if (nr >= nw)                fail($sformatf("read word %0d before it was written", nr));
      else if (rdata !== sent[nr]) fail($sformatf("word %0d: wrote %02h, read %02h", nr, sent[nr], rdata));
      nr++;
    end
    if (rinc && rempty) empty_blocked++;
    rinc <= (mode == DRAIN) || (mode == MIX && rnd(0, 1) == 1);
  end

  initial begin
    wait (srst_n === 1'b1 && drst_n === 1'b1);   // either domain may leave reset first
    repeat (LAPS) begin
      mode = FILL;  wait (wfull);
      repeat (src_cycles(6, 2)) @(posedge sclk);   // sit at full: writes must block
      mode = DRAIN; wait (rempty && nr == nw);
      repeat (src_cycles(6, 2)) @(posedge sclk);   // sit at empty: reads must block
    end
    mode = MIX;   wait (nw == WORDS);
    mode = DRAIN; wait (nr == WORDS);
    repeat (src_cycles(8, 8)) @(posedge sclk);
    $display("[cov] words %0d; write cycles blocked by full %0d; read cycles blocked by empty %0d",
             nr, full_blocked, empty_blocked);
    if (full_blocked == 0)  fail("never saw a write blocked by full");
    if (empty_blocked == 0) fail("never saw a read blocked by empty");
    finish_test("fifo");
  end
endmodule
