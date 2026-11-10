// rst_sync -- reset synchronizer from Through Iris ep24 (7:33).
// Asserts asynchronously (no clock needed), releases on this domain's clock,
// so every flop leaves reset on the same edge.
module rst_sync (
  input  logic clk, arst_n,    // raw async reset
  output logic rst_n);         // for this domain
  (* ASYNC_REG = "TRUE" *) logic r1, r2;
  always_ff @(posedge clk or negedge arst_n)
    if (!arst_n) {r2, r1} <= 2'b00;      // assert: now
    else         {r2, r1} <= {r1, 1'b1}; // release: on clk
  assign rst_n = r2;
endmodule
