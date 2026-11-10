// dll_tx -- the sending half of the data link layer (ep26, 5:55 "Break 3").
//
// Every TLP from the transaction layer gets the next 12-bit sequence number
// and a copy in the replay buffer, then goes on the wire. The copy stays
// until an ACK covers it:
//   ACK n  purges every TLP up to and including n
//   NAK n  purges up to n, then replays everything after n, in order
//   no ACK or NAK for REPLAY_T cycles with TLPs unacknowledged -> replay
//          (the replay timer; it recovers a replay that was itself corrupted)
// A replay has priority over new TLPs; new TLPs wait while the buffer is full.
module dll_tx #(parameter int RB = 16, REPLAY_T = 48) (
  input  logic        clk, rst_n,
  input  logic [11:0] seq0,                 // first sequence number after reset
  input  logic        tlp_valid,
  output logic        tlp_ready,
  input  logic [15:0] tlp_id,
  output logic        w_valid,              // the wire: one TLP per cycle
  output logic [11:0] w_seq,
  output logic [15:0] w_id,
  input  logic        d_valid, d_nak,       // ACK / NAK DLLPs from the receiver
  input  logic [11:0] d_seq
);
  logic [15:0] rbuf [RB];
  logic [11:0] base;                        // oldest unacknowledged sequence number
  int          n, send;                     // entries held, next one to send
  int          timer;

  assign tlp_ready = (n < RB);

  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) begin
      base <= seq0; n <= 0; send <= 0; timer <= 0; w_valid <= 1'b0;
    end else begin : step
      logic [11:0] b;
      int k, nn, ss, tt;
      logic app;
      b = base; nn = n; ss = send; tt = timer + 1;
      if (d_valid) begin
        k = (d_seq - b + 12'd1) & 12'hFFF;         // TLPs this DLLP acknowledges
        if (k <= nn) begin                          // (a stale one acknowledges none)
          b = b + k; nn = nn - k; ss = (ss > k) ? ss - k : 0;
          if (k > 0) tt = 0;
        end
        if (d_nak) begin ss = 0; tt = 0; end
      end
      if (nn > 0 && tt >= REPLAY_T) begin ss = 0; tt = 0; end
      if (nn == 0) tt = 0;
      app = tlp_valid && tlp_ready;                 // the handshake the sender saw
      if (app) begin                                // append the new TLP
        rbuf[(b + nn) % RB] <= tlp_id;
        nn = nn + 1;
      end
      w_valid <= 1'b0;
      if (ss < nn) begin                            // replay first, then new
        w_valid <= 1'b1;
        w_seq   <= b + ss;
        w_id    <= (app && ss == nn - 1) ? tlp_id : rbuf[(b + ss) % RB];   // just appended
        ss = ss + 1;
      end
      base <= b; n <= nn; send <= ss; timer <= tt;
    end
endmodule
