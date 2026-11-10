// reconv_bad -- ep24 Break 2 (5:24): reconvergence. en_a and en_b are set
// and cleared together in the source, each gets its own (correct!) two-flop
// synchronizer, and the destination combines them again. Each crossing is
// safe alone; together they can arrive a cycle apart, and the combining
// logic sees a pairing that never happened at the source.
module reconv_bad (
  input  logic sclk, srst_n,
  input  logic en_a, en_b,
  input  logic dclk, drst_n,
  output logic a_d, b_d);
  logic a_s, b_s;
  always_ff @(posedge sclk or negedge srst_n)
    if (!srst_n) {a_s, b_s} <= 2'b00;
    else         {a_s, b_s} <= {en_a, en_b};
  sync_2ff #(1) u_sync_a (.clk(dclk), .rst_n(drst_n), .d(a_s), .q(a_d));
  sync_2ff #(1) u_sync_b (.clk(dclk), .rst_n(drst_n), .d(b_s), .q(b_d));  // BUG: reconverges
endmodule
