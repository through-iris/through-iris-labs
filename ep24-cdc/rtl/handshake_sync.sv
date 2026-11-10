// handshake_sync -- move an arbitrary multi-bit word between unrelated clocks.
// ep24 (4:42): hold the data stable, cross ONE request bit, capture, cross
// the acknowledge back. The data bus itself is never synchronized; it is
// only sampled while it is guaranteed not to be changing.
//
// Four-phase: REQ up, ACK up, REQ down, ACK down. s_ready is low for the
// whole round trip, so throughput is one word per ~4 sync delays.
module handshake_sync #(parameter int W = 8) (
  input  logic         sclk, srst_n,             // source domain
  input  logic         s_valid,
  input  logic [W-1:0] s_data,
  output logic         s_ready,
  input  logic         dclk, drst_n,             // destination domain
  output logic         d_valid,                  // one dclk pulse per word
  output logic [W-1:0] d_data);

  logic         req, ack;                        // the only two signals that cross

  // ---- source: launch, then wait out the round trip
  logic         busy, ack_s;
  logic [W-1:0] data;                            // frozen while req is high
  sync_2ff #(1) u_ack (.clk(sclk), .rst_n(srst_n), .d(ack), .q(ack_s));
  always_ff @(posedge sclk or negedge srst_n)
    if (!srst_n) begin
      req <= 1'b0; busy <= 1'b0; data <= '0;
    end else if (!busy) begin
      if (s_valid) begin data <= s_data; req <= 1'b1; busy <= 1'b1; end
    end else if (req && ack_s)   req  <= 1'b0;   // ACK up: drop REQ
    else if (!req && !ack_s)     busy <= 1'b0;   // ACK down: done
  assign s_ready = !busy;

  // ---- destination: capture on the rising edge of the synced REQ
  logic req_d, req_q;
  sync_2ff #(1) u_req (.clk(dclk), .rst_n(drst_n), .d(req), .q(req_d));
  always_ff @(posedge dclk or negedge drst_n)
    if (!drst_n) begin
      req_q <= 1'b0; d_valid <= 1'b0; d_data <= '0;
    end else begin
      req_q   <= req_d;
      d_valid <= req_d && !req_q;
      if (req_d && !req_q) d_data <= data;       // stable: REQ has been high 2+ cycles
    end
  assign ack = req_q;                            // ACK follows REQ back
endmodule
