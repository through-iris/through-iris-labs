// pulse_sync -- carry a one-cycle event from any clock to any other clock.
// The fix for ep24 Break 3 (5:24): a one-cycle pulse can fall between two
// edges of a slower clock and vanish. Crossing a *toggle* instead of the pulse
// turns the event into a level change, and a level is held until it is seen.
//
// Limit: two events closer than ~3 destination cycles merge into one toggle
// pair and cancel. If the source can fire that fast, use a handshake or a FIFO.
module pulse_sync (
  input  logic sclk, srst_n, spulse,   // source domain
  input  logic dclk, drst_n,           // destination domain
  output logic dpulse);
  logic tog, tog_q, tog_d;
  always_ff @(posedge sclk or negedge srst_n)
    if (!srst_n)     tog <= 1'b0;
    else if (spulse) tog <= ~tog;      // event -> level change
  sync_2ff #(1) u_sync (.clk(dclk), .rst_n(drst_n), .d(tog), .q(tog_q));
  always_ff @(posedge dclk or negedge drst_n)
    if (!drst_n) tog_d <= 1'b0;
    else         tog_d <= tog_q;
  assign dpulse = tog_q ^ tog_d;       // level change -> one dclk pulse
endmodule
