// dll_rx -- the receiving half of the data link layer (ep26, 5:55).
//
// It accepts a TLP only if its link CRC is good AND it carries the next
// expected sequence number. Everything else is discarded:
//   bad LCRC        -> NAK (last good sequence number), unless one is already
//                      outstanding
//   ahead of next   -> a TLP was lost or bad: NAK, unless one is outstanding
//   behind next     -> a duplicate from a replay: ACK again, drop it
// Only accepted TLPs go up to the transaction layer: exactly one copy, in
// order. That is the layer a scoreboard should watch (ep26, C1).
module dll_rx (
  input  logic        clk, rst_n,
  input  logic [11:0] seq0,
  input  logic        w_valid, w_bad,       // w_bad: the LCRC check failed
  input  logic [11:0] w_seq,
  input  logic [15:0] w_id,
  output logic        acc_valid,            // up to the transaction layer
  output logic [11:0] acc_seq,
  output logic [15:0] acc_id,
  output logic        d_valid, d_nak,       // ACK / NAK back to the sender
  output logic [11:0] d_seq
);
  logic [11:0] nxt;
  logic        nak_sched;
  wire  [11:0] ahead = w_seq - nxt;         // 0: expected; 1..2047: ahead; else behind

  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) begin
      nxt <= seq0; nak_sched <= 1'b0; acc_valid <= 1'b0; d_valid <= 1'b0;
    end else begin
      acc_valid <= 1'b0; d_valid <= 1'b0;
      if (w_valid) begin
        if (w_bad || (ahead != 0 && ahead < 12'd2048)) begin
          if (!nak_sched) begin
            d_valid <= 1'b1; d_nak <= 1'b1; d_seq <= nxt - 12'd1; nak_sched <= 1'b1;
          end
        end else if (ahead == 0) begin
          acc_valid <= 1'b1; acc_seq <= w_seq; acc_id <= w_id;
          nxt <= nxt + 12'd1; nak_sched <= 1'b0;
          d_valid <= 1'b1; d_nak <= 1'b0; d_seq <= w_seq;
        end else begin
          d_valid <= 1'b1; d_nak <= 1'b0; d_seq <= nxt - 12'd1;
        end
      end
    end
endmodule
