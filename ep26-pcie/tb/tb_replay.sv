// tb_replay -- Break 3 (ep26, 5:55): the replay counted twice.
//
// A transaction layer sends MWr TLPs through dll_tx, across a wire that can
// corrupt a TLP's link CRC, into dll_rx. ACK/NAK DLLPs come back after a
// delay. Three observers:
//   wire monitor  every TLP on the wire whose LCRC checks out
//   TL monitor    what dll_rx passes up to the transaction layer
//   link monitor  the data link rules: new sequence numbers go up by one,
//                 a NAK n is followed by a replay from n+1, and nothing
//                 already acknowledged is ever sent again
// The scoreboard expects every write exactly once, in order. -DBROKEN feeds
// it from the wire monitor instead of the TL monitor. The design is the same
// in both builds: Break 3 is a monitor in the wrong place.
//
//   +story   the episode: TLPs seq 10..15, the first copy of 12 corrupted
//   default  2000 TLPs, random corruption rate, DLLP delay and gaps, and a
//            starting sequence number that sometimes wraps past 4095
`timescale 1ns/1ps
module tb_replay;
  `include "tb_common.svh"
  localparam int MAXN = 4096;

  logic [11:0] seq0 = 12'd10, w_seq, acc_seq, d_seq, t_seq;
  logic        tlp_valid = 1'b0, tlp_ready, w_valid, w_bad = 1'b0, acc_valid;
  logic        d_valid, d_nak, t_valid = 1'b0, t_nak = 1'b0;
  logic [15:0] tlp_id = '0, w_id, acc_id;

  dll_tx u_tx (.clk, .rst_n, .seq0, .tlp_valid, .tlp_ready, .tlp_id,
               .w_valid, .w_seq, .w_id, .d_valid(t_valid), .d_nak(t_nak), .d_seq(t_seq));
  dll_rx u_rx (.clk, .rst_n, .seq0, .w_valid, .w_bad, .w_seq, .w_id,
               .acc_valid, .acc_seq, .acc_id, .d_valid, .d_nak, .d_seq);

  bit          story = 0;
  int unsigned n = 2000, bad_pct = 0, dly = 3, gap_pct = 0;
  int unsigned nwire = 0, ngood = 0, nacc = 0, nnak = 0, nreplayed = 0, nbad = 0;
  bit          corrupted_once [MAXN];

  // ---- the DLLP path back to the sender: a fixed delay
  logic        dv [16];
  logic        dn [16];
  logic [11:0] ds [16];
  always @(posedge clk) begin
    dv[0] <= d_valid; dn[0] <= d_nak; ds[0] <= d_seq;
    for (int i = 1; i < 16; i++) begin dv[i] <= dv[i-1]; dn[i] <= dn[i-1]; ds[i] <= ds[i-1]; end
  end
  always_comb begin
    t_valid = (dly == 0) ? d_valid : dv[dly-1];
    t_nak   = (dly == 0) ? d_nak   : dn[dly-1];
    t_seq   = (dly == 0) ? d_seq   : ds[dly-1];
  end

  // ---- the wire: decides, per TLP, whether its LCRC arrives broken
  always @(negedge clk) begin
    w_bad = 1'b0;
    if (w_valid) begin
      if (story) w_bad = (w_seq == 12'd12 && !corrupted_once[12]);
      else       w_bad = (rnd(0, 99) < bad_pct);
      if (w_bad) begin corrupted_once[w_seq] = 1; nbad++; end
    end
  end

  // ---- the scoreboard: every write once, in order
  int unsigned exp_id = 0, nobs = 0;
  bit          seen [MAXN];
  task automatic observe(input logic [15:0] id, input logic [11:0] seq, input string where);
    nobs++;
    if (seen[id])
      fail($sformatf("MWr seq %0d counted twice (%s)", seq, where));
    else begin
      seen[id] = 1;
      if (id != exp_id)
        fail($sformatf("MWr seq %0d arrived before seq %0d (%s)", seq, (seq0 + exp_id) % 4096, where));
      while (exp_id < MAXN && seen[exp_id]) exp_id++;
    end
  endtask

`ifdef DEBUG
  always @(posedge clk) if (rst_n)
    $display("[%0d] in v%0d id%0d rdy%0d | wire v%0d seq%0d id%0d bad%0d | acc v%0d seq%0d id%0d | dllp v%0d nak%0d %0d",
             cyc, tlp_valid, tlp_id, tlp_ready, w_valid, w_seq, w_id, w_bad, acc_valid, acc_seq, acc_id, t_valid, t_nak, t_seq);
`endif
  // ---- wire monitor and TL monitor
  always @(posedge clk) if (rst_n) begin
    if (w_valid) begin
      nwire++;
      if (!w_bad) begin
        ngood++;
`ifdef BROKEN
        observe(w_id, w_seq, "wire monitor");
`endif
      end
    end
    if (acc_valid) begin
      nacc++;
`ifndef BROKEN
      observe(acc_id, acc_seq, "transaction layer");
`endif
    end
  end

  // ---- hang: writes still owed, and nothing delivered for STUCK cycles
  localparam int STUCK = 1000;
  int unsigned     last_n = 0;
  longint unsigned last_acc = 0;
  always @(posedge clk) if (rst_n) begin
    if (exp_id != last_n) begin last_n = exp_id; last_acc = cyc; end
    else if (exp_id < n && cyc > last_acc + STUCK) begin
      fail($sformatf("hang: %0d of %0d writes delivered, %0d TLPs waiting on an ACK, nothing new accepted for %0d cycles",
                     exp_id, n, u_tx.n, STUCK));
      finish_test("replay");
    end
  end

  // ---- link monitor (sender side: it sees what the sender sees)
  logic [11:0] max_seq, acked, want;
  bit          any = 0, any_ack = 0, want_v = 0;
  function automatic bit le(input logic [11:0] a, input logic [11:0] b);   // a <= b, mod 4096
    logic [11:0] d;
    d = b - a;
    le = (d < 12'd2048);
  endfunction
  always @(posedge clk) if (rst_n) begin
    if (w_valid) begin
      if (want_v) begin
        if (w_seq != want) fail($sformatf("link: after NAK %0d the next TLP was seq %0d, not %0d", want - 1, w_seq, want));
        want_v = 0;
      end
      if (any_ack && le(w_seq, acked))
        fail($sformatf("link: seq %0d sent again after ACK %0d covered it", w_seq, acked));
      if (!any) begin
        if (w_seq != seq0) fail($sformatf("link: first TLP has seq %0d, not %0d", w_seq, seq0));
        max_seq = w_seq; any = 1;
      end else if (!le(w_seq, max_seq)) begin
        if (w_seq != max_seq + 12'd1) fail($sformatf("link: seq jumped from %0d to %0d", max_seq, w_seq));
        max_seq = w_seq;
      end else nreplayed++;
    end
    if (t_valid) begin
      if (!any_ack || !le(t_seq, acked)) begin acked = t_seq; any_ack = 1; end
      if (t_nak) begin
        nnak++;
        want = t_seq + 12'd1; want_v = 1;        // replayed or new, the next TLP is n+1
      end
    end
  end

  // ---- the transaction layer: sends writes 0..n-1
  initial begin
    story = $test$plusargs("story");
    if (story) begin n = 6; seq0 = 12'd10; dly = 3; end
    else begin
      n = 2000;
      seq0 = rnd(0, 1) ? rnd(0, 4095) : 4096 - rnd(1, 40);   // half the seeds wrap
      bad_pct = rnd(0, 8); dly = rnd(0, 12); gap_pct = rnd(0, 50);
    end
    $display("[cfg] %0d TLPs from seq %0d, %0d%% corrupted, DLLP delay %0d, seed %0d",
             n, seq0, bad_pct, dly, seed);
    @(posedge rst_n);
    // inputs change on the falling edge, so the DUT samples them stable
    for (int i = 0; i < n; i++) begin
      if (story && i == 5) begin                                 // seq 15 comes later
        @(negedge clk) tlp_valid = 1'b0;
        repeat (8) @(posedge clk);
      end
      while (!story && rnd(0, 99) < gap_pct) begin
        @(negedge clk) tlp_valid = 1'b0;
        @(posedge clk);
      end
      @(negedge clk);
      tlp_valid = 1'b1; tlp_id = i;
      while (!tlp_ready) @(negedge clk);
      @(posedge clk);                                            // taken on this edge
    end
    @(negedge clk) tlp_valid = 1'b0;
    repeat (400) begin
      @(posedge clk);
      if (exp_id == n && u_tx.n == 0) break;
    end
    if (exp_id != n) fail($sformatf("%0d of %0d writes delivered", exp_id, n));
    if (nobs != n)
`ifdef BROKEN
      fail($sformatf("the wire monitor counted %0d writes; %0d were sent", nobs, n));
`else
      fail($sformatf("the scoreboard counted %0d writes; %0d were sent", nobs, n));
`endif
    if (u_tx.n != 0) fail($sformatf("%0d TLPs never acknowledged", u_tx.n));
    $display("[count] the wire carried %0d TLPs, %0d with a good LCRC; the transaction layer accepted %0d",
             nwire, ngood, nacc);
    $display("[cov] %0d corrupted, %0d NAKs, %0d TLPs resent", nbad, nnak, nreplayed);
    finish_test("replay");
  end
endmodule
