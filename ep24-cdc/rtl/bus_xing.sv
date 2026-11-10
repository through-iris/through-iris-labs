// bus_xing -- the fix for ep24 Break 1 (4:05): a multi-bit counter crossing
// as Gray code. Gray changes one bit per step, so a bit that arrives a cycle
// late just means the previous count, never a value the counter never held.
// The Gray word is a flop output: no logic between the source flop and the
// synchronizer (the "logic before sync" violation in the static report).
module bus_xing #(parameter int W = 4) (
  input  logic         sclk, srst_n,
  input  logic [W-1:0] cnt,          // binary count, source domain
  input  logic         dclk, drst_n,
  output logic [W-1:0] cnt_d);       // binary count, destination domain
  logic [W-1:0] gray_s, gray_d;
  always_ff @(posedge sclk or negedge srst_n)
    if (!srst_n) gray_s <= '0;
    else         gray_s <= (cnt >> 1) ^ cnt;          // binary -> Gray, registered
  sync_2ff #(W) u_sync (.clk(dclk), .rst_n(drst_n), .d(gray_s), .q(gray_d));
  for (genvar i = 0; i < W; i++) begin : g_bin         // Gray -> binary:
    assign cnt_d[i] = ^(gray_d >> i);                 // bit i = XOR of bits i and up
  end
endmodule
