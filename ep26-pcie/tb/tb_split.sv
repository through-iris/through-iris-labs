// tb_split -- Break 1 (ep26, 4:10): one read, several completions.
//
// A requester issues memory reads to the completer and a read scoreboard
// checks every completion that comes back.
//   +story  the episode's read: tag 5, 512 bytes at 0x2040, MPS 256, RCB 64
//           -> completions of 192, 256 and 64 bytes
//   default 400 random reads: up to 4 in flight, tags reused once retired,
//           MPS 128/256/512, RCB 64/128, lengths up to MRRS (512 B), and any
//           read that would cross 4 KB split by the requester first (ep02)
//
// -DBROKEN swaps in the scoreboard that expects one completion per read. The
// design is the same in both builds: Break 1 is a testbench bug.
`timescale 1ns/1ps
module tb_split;
  `include "tb_common.svh"
  localparam int MRRS = 512, N = 400;

  logic [12:0] mps = 13'd256, rcb = 13'd64;
  logic        req_valid = 1'b0, req_ready, cpl_valid, cpl_ready = 1'b0;
  logic [7:0]  req_tag = '0, cpl_tag;
  logic [31:0] req_addr = '0, cpl_first_dw, cpl_last_dw;
  logic [10:0] req_len_dw = '0, cpl_len_dw;
  logic [12:0] cpl_byte_count;
  logic [6:0]  cpl_lower_addr;
  logic [3:0]  cut = '0;
  bit          story = 0;

  completer dut (.*);

  function automatic logic [31:0] mem(input logic [31:0] a);
    mem = {a[15:0], ~a[15:0]} ^ 32'h5EED_0026;
  endfunction

  // ---- per-tag record the requester keeps (what was asked)
  bit          pend [256];
  int unsigned owed [256];
  logic [31:0] next [256];
  longint unsigned sent_at [256];
  int unsigned ncpl = 0, nrd = 0, nretired = 0, max_split = 0, splits = 0;
  int unsigned cpl_per_rd [256];

  // ---- the scoreboard
  always @(posedge clk) if (rst_n && cpl_valid && cpl_ready) begin
    ncpl++;
`ifdef BROKEN
    // expects exactly one completion per read
    if (!pend[cpl_tag])
      fail($sformatf("unexpected CplD for tag %0d -- no read pending", cpl_tag));
    else begin
      if (cpl_len_dw * 4 != owed[cpl_tag])
        fail($sformatf("short read: tag %0d asked for %0d bytes, got %0d",
                       cpl_tag, owed[cpl_tag], cpl_len_dw * 4));
      pend[cpl_tag] = 0;                     // done, as far as it knows
      nretired++;
    end
`else
    // tracks bytes, not packets
    if (!pend[cpl_tag])
      fail($sformatf("unexpected CplD for tag %0d -- no read pending", cpl_tag));
    else begin
      if (cpl_byte_count != owed[cpl_tag])
        fail($sformatf("tag %0d: Byte Count %0d, but %0d bytes are owed",
                       cpl_tag, cpl_byte_count, owed[cpl_tag]));
      if (cpl_lower_addr != next[cpl_tag][6:0])
        fail($sformatf("tag %0d: Lower Address 0x%02h, expected 0x%02h",
                       cpl_tag, cpl_lower_addr, next[cpl_tag][6:0]));
      if (cpl_len_dw == 0 || cpl_len_dw * 4 > owed[cpl_tag])
        fail($sformatf("tag %0d: %0d DW returned, %0d bytes owed", cpl_tag, cpl_len_dw, owed[cpl_tag]));
      if (cpl_len_dw * 4 > mps)
        fail($sformatf("tag %0d: %0d bytes in one completion, Max_Payload_Size is %0d",
                       cpl_tag, cpl_len_dw * 4, mps));
      if (cpl_len_dw * 4 < owed[cpl_tag] && (next[cpl_tag] + cpl_len_dw * 4) % rcb != 0)
        fail($sformatf("tag %0d: completion ends at 0x%0h, not on the %0d-byte RCB",
                       cpl_tag, next[cpl_tag] + cpl_len_dw * 4, rcb));
      if (cpl_first_dw !== mem(next[cpl_tag]) || cpl_last_dw !== mem(next[cpl_tag] + cpl_len_dw * 4 - 4))
        fail($sformatf("tag %0d: data is not from 0x%0h", cpl_tag, next[cpl_tag]));
      owed[cpl_tag] -= cpl_len_dw * 4;
      next[cpl_tag] += cpl_len_dw * 4;
      cpl_per_rd[cpl_tag]++;
      if (owed[cpl_tag] == 0) begin          // retire at zero bytes
        pend[cpl_tag] = 0;
        nretired++;
        if (cpl_per_rd[cpl_tag] > 1) splits++;
        if (cpl_per_rd[cpl_tag] > max_split) max_split = cpl_per_rd[cpl_tag];
      end
    end
`endif
    if (story) $display("[cycle %0d] CplD tag %0d  %0d B  Byte Count %0d  Lower Address 0x%02h",
                        cyc, cpl_tag, cpl_len_dw * 4, cpl_byte_count, cpl_lower_addr);
  end

  // ---- completion timeout: a read still owed bytes past the limit is named
  localparam int CPL_TIMEOUT = 2000;
  always @(posedge clk) if (rst_n)
    for (int t = 0; t < 256; t++)
      if (pend[t] && cyc - sent_at[t] == CPL_TIMEOUT)
        fail($sformatf("tag %0d: no completion for %0d cycles, %0d bytes still owed", t, CPL_TIMEOUT, owed[t]));

  // ---- hang: reads outstanding, and nothing retired for longer than the
  // timeout. The timeout above names the tag; this ends the run.
  int unsigned     last_n = 0;
  longint unsigned last_ret = 0;
  always @(posedge clk) if (rst_n) begin
    if (nretired != last_n) begin last_n = nretired; last_ret = cyc; end
    else if (nrd != nretired && cyc > last_ret + CPL_TIMEOUT + 500) begin
      fail($sformatf("hang: %0d of %0d reads retired, then nothing for %0d cycles",
                     nretired, nrd, CPL_TIMEOUT + 500));
      finish_test("split");
    end
  end

  // ---- the requester
  task automatic issue(input logic [7:0] t, input logic [31:0] a, input int unsigned nbytes);
    if (pend[t]) fail($sformatf("requester reused tag %0d while it was pending", t));
    pend[t] = 1; owed[t] = nbytes; next[t] = a; sent_at[t] = cyc; cpl_per_rd[t] = 0;
    @(negedge clk);                          // inputs change on the falling edge
    req_tag = t; req_addr = a; req_len_dw = nbytes / 4; req_valid = 1'b1;
    while (!req_ready) @(negedge clk);
    @(posedge clk);                          // taken on this edge
    @(negedge clk) req_valid = 1'b0;
    nrd++;
    if (story) $display("[cycle %0d] MRd  tag %0d  %0d B at 0x%0h", cyc, t, nbytes, a);
  endtask

  function automatic int free_tag();
    int c = 0;
    for (int k = 0; k < 64; k++) begin
      c = rnd(0, 31);
      if (!pend[c]) return c;
    end
    return -1;
  endfunction

  always @(posedge clk) cpl_ready <= story ? 1'b1 : (rnd(0, 3) != 0);
  always @(posedge clk) cut <= story ? 4'd0 : (rnd(0, 2) == 0 ? rnd(1, 8) : 0);

  initial begin
    story = $test$plusargs("story");
    if (!story) begin
      mps = 13'd128 << rnd(0, 2);
      rcb = 13'd64 << rnd(0, 1);
    end
    $display("[cfg] MPS %0d, RCB %0d, MRRS %0d, seed %0d", mps, rcb, MRRS, seed);
    @(posedge rst_n); repeat (2) @(posedge clk);
    if (story) issue(8'd5, 32'h2040, 512);
    else while (nrd < N) begin : traffic
      int t, nb;
      logic [31:0] a;
      t = free_tag();
      if (t < 0 || (nrd - nretired) >= 4) begin @(posedge clk); continue; end
      a  = {rnd(0, 32'h3FFF), 2'b00} + 32'h0001_0000;
      nb = 4 * rnd(1, MRRS / 4);
      if (rnd(0, 7) == 0) begin a = (a | 32'hFFF) - 4 * rnd(0, 7) - 3; a[1:0] = 2'b00; end  // near 4 KB
      if (a / 4096 != (a + nb - 1) / 4096) begin   // ep02: never cross 4 KB -- split it first
        int first;
        first = 4096 - (a % 4096);
        issue(t, a, first);
        while (free_tag() < 0 || (nrd - nretired) >= 4) @(posedge clk);
        t = free_tag();
        issue(t, a + first, nb - first);
      end else
        issue(t, a, nb);
    end
    // drain, then nothing may be left owed
    repeat (CPL_TIMEOUT + 10) begin
      @(posedge clk);
      if (nretired == nrd) break;
    end
`ifndef BROKEN
    for (int t = 0; t < 256; t++)
      if (pend[t]) fail($sformatf("tag %0d still owed %0d bytes at end of test", t, owed[t]));
`endif
    repeat (5) @(posedge clk);
    $display("[cov] %0d reads, %0d completions, %0d reads split, at most %0d completions for one read",
             nrd, ncpl, splits, max_split);
    finish_test("split");
  end
endmodule
