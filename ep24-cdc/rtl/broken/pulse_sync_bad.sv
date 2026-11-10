// pulse_sync_bad -- ep24 Break 3 (5:24): a one-cycle pulse pushed straight
// through a two-flop synchronizer. When the source clock is faster, the
// pulse can start and end between two destination edges, and the event is
// simply lost. Same ports as pulse_sync, which crosses a toggle instead.
module pulse_sync_bad (
  input  logic sclk, srst_n, spulse,
  input  logic dclk, drst_n,
  output logic dpulse);
  logic p_s, p_q, p_d;
  always_ff @(posedge sclk or negedge srst_n)
    if (!srst_n) p_s <= 1'b0;
    else         p_s <= spulse;
  sync_2ff #(1) u_sync (.clk(dclk), .rst_n(drst_n), .d(p_s), .q(p_q));  // BUG
  always_ff @(posedge dclk or negedge drst_n)
    if (!drst_n) p_d <= 1'b0;
    else         p_d <= p_q;
  assign dpulse = p_q && !p_d;
endmodule
