// sync_2ff -- the two-flop synchronizer from Through Iris ep24 (3:15).
// One bit (or a Gray-coded word) crosses into clk's domain. With CDC_INJECT
// defined, each bit independently arrives after 2 or 3 edges, the latency
// uncertainty real metastability gives you, so logic that assumed an exact
// count fails in simulation instead of in silicon.
module sync_2ff #(parameter int W = 1) (
  input  logic         clk, rst_n,   // destination
  input  logic [W-1:0] d,            // other domain
  output logic [W-1:0] q);
  (* ASYNC_REG = "TRUE" *) logic [W-1:0] s1, s2;
  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) {s2, s1} <= '0;
    else        {s2, s1} <= {s1, d};  // no logic between
`ifdef CDC_INJECT   // sim only: 2 or 3 edges, per bit
  logic [W-1:0] s3, late;
  always_ff @(posedge clk) begin s3 <= s2; late <= W'($urandom); end
  assign q = (late & s3) | (~late & s2);
`else
  assign q = s2;
`endif
endmodule
