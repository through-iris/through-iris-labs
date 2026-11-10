// reconv_xing -- the fix for ep24 Break 2 (5:24). Two related controls that
// must be seen together cross as ONE word through a handshake, so the
// destination only ever sees a pairing the source actually held.
module reconv_xing (
  input  logic sclk, srst_n,
  input  logic en_a, en_b,           // source: always set and cleared together
  input  logic dclk, drst_n,
  output logic a_d, b_d);
  logic [1:0] last, pair_d;
  logic       ready;
  // launch a transfer whenever the pair differs from what was last sent
  wire        send = ready && ({en_a, en_b} != last);
  always_ff @(posedge sclk or negedge srst_n)
    if (!srst_n)   last <= 2'b00;
    else if (send) last <= {en_a, en_b};
  handshake_sync #(2) u_hs (
    .sclk(sclk), .srst_n(srst_n), .s_valid(send), .s_data({en_a, en_b}), .s_ready(ready),
    .dclk(dclk), .drst_n(drst_n), .d_valid(), .d_data(pair_d));
  assign {a_d, b_d} = pair_d;
endmodule
