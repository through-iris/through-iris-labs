// bus_xing_bad -- ep24 Break 1 (4:05): a two-flop synchronizer on every bit
// of a binary counter. 0111 -> 1000 flips all four bits; each synchronizer
// may resolve a cycle early or late, so for one cycle the receiver can see
// 1111 -- fifteen, a value the counter never held.
//
// It passes plain simulation (every bit resolves identically, by
// construction). Run it with injection to see it fail.
module bus_xing_bad #(parameter int W = 4) (
  input  logic         sclk, srst_n,
  input  logic [W-1:0] cnt,
  input  logic         dclk, drst_n,
  output logic [W-1:0] cnt_d);
  logic [W-1:0] cnt_s;
  always_ff @(posedge sclk or negedge srst_n)
    if (!srst_n) cnt_s <= '0;
    else         cnt_s <= cnt;
  sync_2ff #(W) u_sync (.clk(dclk), .rst_n(drst_n), .d(cnt_s), .q(cnt_d));  // BUG
endmodule
