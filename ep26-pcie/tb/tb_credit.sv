// tb_credit -- Break 2 (ep26, 5:05): the credit that never came back.
//
// A sender streams MWr into the receiver: one per cycle whenever it holds a
// posted-header credit and enough posted-data credits. Which writes miss
// every BAR comes from a file run.py writes (+missfile), drawn exactly as the
// episode's model draws them, so +seed=26 is the cold open: 8 misses.
//
//   +writes=N   stop after N writes (default 5000)
//   +nocheck    no end-of-test credit check: what the cold open's test had
//
// The test passes only if every write that hit a BAR reached memory, every
// miss was reported UR, and -- unless +nocheck -- every credit type is back at
// its advertised value once traffic drains. A link that stops moving for
// 1000 cycles is reported as the hang it is.
`timescale 1ns/1ps
module tb_credit;
  `include "tb_common.svh"
  localparam int PH = 8, PD = 64, MAXW = 8192, STUCK = 1000;

  logic        mwr_valid = 1'b0, ret_valid, ur, hit_valid;
  logic [31:0] mwr_addr = '0, mwr_data = '0, hit_addr, hit_data;
  logic [4:0]  mwr_len_dw = 5'd1;
  logic [2:0]  ret_pd;

`ifdef BROKEN
  fc_rx_bad #(.PH(PH), .PD(PD)) dut (.*);
`else
  fc_rx     #(.PH(PH), .PD(PD)) dut (.*);
`endif

  logic [0:0]  miss [MAXW];
  string       missfile = "";
  int unsigned writes = 5000, nsent = 0, nhit_sent = 0, nhit = 0, nmiss = 0, nur = 0;
  int          ph = PH, pd = PD;
  longint unsigned last_move = 0, last_send = 0;
  bit          check = 1, done = 0;
  int unsigned nxt_len = 1;               // the next write's size, 1..16 DW
  logic [31:0] exp_q [$];

  function automatic logic [31:0] pattern(input logic [31:0] a);
    pattern = a ^ 32'hC0DE_0026;
  endfunction

  // ---- the sender (the requester's transaction layer)
  always @(posedge clk) if (rst_n && !done) begin : send
    int need;
    if (ret_valid) begin ph = ph + 1; pd = pd + ret_pd; last_move = cyc; end
    mwr_valid <= 1'b0;
    need = (nxt_len + 3) / 4;
    if (nsent < writes && ph > 0 && pd >= need) begin
      logic [31:0] a;
      if (miss[nsent]) begin a = 32'h3000_0000 + {rnd(0, 32'hFFFF), 2'b00}; nmiss++; end
      else begin
        a = rnd(0, 1) ? 32'h1000_0000 + {rnd(0, 32'h3FFF), 2'b00}
                      : 32'h2000_0000 + {rnd(0, 32'h3FFFF), 2'b00};
        exp_q.push_back(a); nhit_sent++;
      end
      mwr_valid <= 1'b1; mwr_addr <= a; mwr_data <= pattern(a); mwr_len_dw <= nxt_len;
      ph = ph - 1; pd = pd - need;
      nsent++; last_move = cyc; last_send = cyc;
      nxt_len = rnd(1, 16);
    end
  end

  // ---- what reached memory, in order
  always @(posedge clk) if (rst_n) begin
    if (hit_valid) begin
      nhit++;
      if (exp_q.size() == 0) fail($sformatf("write to 0x%08h reached memory, none expected", hit_addr));
      else begin
        logic [31:0] e;
        e = exp_q.pop_front();
        if (hit_addr !== e || hit_data !== pattern(e))
          fail($sformatf("memory got 0x%08h at 0x%08h, expected the write to 0x%08h", hit_data, hit_addr, e));
      end
    end
    if (ur) nur++;
  end

  initial begin
    void'($value$plusargs("writes=%d", writes));
    void'($value$plusargs("missfile=%s", missfile));
    check = !$test$plusargs("nocheck");
    for (int i = 0; i < MAXW; i++) miss[i] = 1'b0;
    if (missfile != "") $readmemb(missfile, miss);
    $display("[cfg] PH %0d, PD %0d (16 B each), %0d writes, seed %0d, credit check %s",
             PH, PD, writes, seed, check ? "on" : "OFF");
    @(posedge rst_n);
    forever begin
      @(posedge clk);
      if (nsent == writes && cyc > last_move + 10) break;          // drained
      if (cyc > last_move + STUCK) begin
        fail($sformatf("hang: %0d of %0d writes sent, the last on cycle %0d, then nothing moved for %0d cycles",
                       nsent, writes, last_send, STUCK));
        $display("[credits] PH %0d of %0d, PD %0d of %0d", ph, PH, pd, PD);
        finish_test("credit");
      end
    end
    done = 1;
    if (exp_q.size() != 0) fail($sformatf("%0d writes never reached memory", exp_q.size()));
    if (nur != nmiss) fail($sformatf("%0d writes missed every BAR, %0d reported UR", nmiss, nur));
    if (check && (ph != PH || pd != PD))
      fail($sformatf("credits leaked: PH %0d of %0d back, PD %0d of %0d back, after traffic drained",
                     ph, PH, pd, PD));
    $display("[cov] %0d writes, %0d hit a BAR, %0d discarded as UR, last write on cycle %0d",
             nsent, nhit, nur, last_send);
    finish_test("credit");
  end
endmodule
