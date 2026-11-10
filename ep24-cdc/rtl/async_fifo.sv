// async_fifo -- the async FIFO from ep24 (4:42). The data never crosses: it
// sits in a dual-port memory written on wclk and read on rclk. Only the two
// pointers cross, Gray-coded, so each increment flips exactly one bit and a
// late bit means "the old pointer", never a wild one.
//
// Pointers carry one extra bit (AW+1) to tell full from empty. Each side
// compares its own pointer against a synchronized, slightly stale copy of the
// other side's, which only ever makes full/empty conservative: full for a
// cycle too long, empty for a cycle too long, never overflow or underflow.
module async_fifo #(parameter int DW = 8, parameter int AW = 3) (
  input  logic          wclk, wrst_n, winc,
  input  logic [DW-1:0] wdata,
  output logic          wfull,
  input  logic          rclk, rrst_n, rinc,
  output logic [DW-1:0] rdata,
  output logic          rempty);

  logic [DW-1:0] mem [0:(1<<AW)-1];
  logic [AW:0]   wbin, wgray, wbin_n, wgray_n;   // write side
  logic [AW:0]   rbin, rgray, rbin_n, rgray_n;   // read side
  logic [AW:0]   wq_rgray, rq_wgray;             // the other side's, synced

  // ---- write domain
  assign wbin_n  = wbin + {{AW{1'b0}}, winc & ~wfull};
  assign wgray_n = (wbin_n >> 1) ^ wbin_n;       // binary -> Gray
  always_ff @(posedge wclk or negedge wrst_n)
    if (!wrst_n) begin wbin <= '0; wgray <= '0; end
    else         begin wbin <= wbin_n; wgray <= wgray_n; end
  always_ff @(posedge wclk)
    if (winc && !wfull) mem[wbin[AW-1:0]] <= wdata;
  sync_2ff #(AW+1) u_r2w (.clk(wclk), .rst_n(wrst_n), .d(rgray), .q(wq_rgray));
  // full: the next write pointer has lapped the read pointer exactly once,
  // which in Gray means the top two bits differ and the rest match
  always_ff @(posedge wclk or negedge wrst_n)
    if (!wrst_n) wfull <= 1'b0;
    else         wfull <= (wgray_n == {~wq_rgray[AW:AW-1], wq_rgray[AW-2:0]});

  // ---- read domain
  assign rbin_n  = rbin + {{AW{1'b0}}, rinc & ~rempty};
  assign rgray_n = (rbin_n >> 1) ^ rbin_n;
  always_ff @(posedge rclk or negedge rrst_n)
    if (!rrst_n) begin rbin <= '0; rgray <= '0; end
    else         begin rbin <= rbin_n; rgray <= rgray_n; end
  assign rdata = mem[rbin[AW-1:0]];
  sync_2ff #(AW+1) u_w2r (.clk(rclk), .rst_n(rrst_n), .d(wgray), .q(rq_wgray));
  always_ff @(posedge rclk or negedge rrst_n)
    if (!rrst_n) rempty <= 1'b1;
    else         rempty <= (rgray_n == rq_wgray);
endmodule
