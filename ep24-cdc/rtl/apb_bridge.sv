// apb_bridge -- the AXI-to-APB bridge from ep06, with the clock crossing ep06
// only waved at (ep06: "the request has to be synchronised across, acted on,
// and synchronised back"). ep24 (0:50) names this bridge as the crossing every
// chip has. AXI-Lite slave on aclk, APB master on pclk, unrelated clocks.
//
// The fix for the final lab: everything that crosses goes through a
// handshake_sync as ONE word. {write, addr, wdata} goes over, and
// {slverr, rdata} comes back. No bit of a transaction gets a synchronizer of
// its own.
//
// Kept small on purpose: one transaction in flight, AW and W accepted
// together, writes before reads, APB3 (no PSTRB/PPROT), 32-bit data.
module apb_bridge #(parameter int AW = 8) (
  // AXI-Lite slave (aclk)
  input  logic          aclk, aresetn,
  input  logic          awvalid, wvalid, arvalid, bready, rready,
  output logic          awready, wready, arready, bvalid, rvalid,
  input  logic [AW-1:0] awaddr, araddr,
  input  logic [31:0]   wdata,
  output logic [1:0]    bresp, rresp,
  output logic [31:0]   rdata,
  // APB master (pclk)
  input  logic          pclk, presetn,
  output logic          psel, penable, pwrite,
  output logic [AW-1:0] paddr,
  output logic [31:0]   pwdata,
  input  logic          pready, pslverr,
  input  logic [31:0]   prdata);

  localparam int RQ = 1 + AW + 32;                 // {write, addr, wdata}
  localparam int RS = 1 + 32;                      // {slverr, rdata}

  logic          req_ready, req_valid_p, rsp_valid, rsp_ready, rsp_pend;
  logic [RQ-1:0] req_data_p;
  logic [RS-1:0] rsp_data, rsp_p;
  logic          busy_a, wr_a;

  // ---- aclk: accept one transaction, send it across, wait for the answer
  wire wr_go = !busy_a && req_ready && awvalid && wvalid;   // AW and W together
  wire rd_go = !busy_a && req_ready && arvalid && !wr_go;   // writes first
  assign awready = wr_go;
  assign wready  = wr_go;
  assign arready = rd_go;

  handshake_sync #(RQ) u_req (
    .sclk(aclk), .srst_n(aresetn), .s_valid(wr_go || rd_go),
    .s_data(wr_go ? {1'b1, awaddr, wdata} : {1'b0, araddr, 32'h0}), .s_ready(req_ready),
    .dclk(pclk), .drst_n(presetn), .d_valid(req_valid_p), .d_data(req_data_p));

  always_ff @(posedge aclk or negedge aresetn)
    if (!aresetn) begin
      busy_a <= 1'b0; wr_a <= 1'b0;
      bvalid <= 1'b0; bresp <= 2'b00;
      rvalid <= 1'b0; rresp <= 2'b00; rdata <= '0;
    end else begin
      if (wr_go || rd_go) begin busy_a <= 1'b1; wr_a <= wr_go; end
      if (rsp_valid) begin                         // the answer is back
        if (wr_a) begin bvalid <= 1'b1; bresp <= {rsp_data[32], 1'b0}; end   // SLVERR = 2'b10
        else      begin rvalid <= 1'b1; rresp <= {rsp_data[32], 1'b0}; rdata <= rsp_data[31:0]; end
      end
      if (bvalid && bready) begin bvalid <= 1'b0; busy_a <= 1'b0; end
      if (rvalid && rready) begin rvalid <= 1'b0; busy_a <= 1'b0; end
    end

  // ---- pclk: ep06's state machine, IDLE -> SETUP -> ACCESS until PREADY
  always_ff @(posedge pclk or negedge presetn)
    if (!presetn) begin
      psel <= 1'b0; penable <= 1'b0; pwrite <= 1'b0; paddr <= '0; pwdata <= '0;
      rsp_pend <= 1'b0; rsp_p <= '0;
    end else begin
      if (req_valid_p) begin                       // SETUP: the whole word arrived at once
        psel <= 1'b1; {pwrite, paddr, pwdata} <= req_data_p;
      end else if (psel && !penable) begin         // ACCESS
        penable <= 1'b1;
      end else if (psel && pready) begin           // done
        psel <= 1'b0; penable <= 1'b0;
        rsp_p <= {pslverr, pwrite ? 32'h0 : prdata}; rsp_pend <= 1'b1;
      end
      if (rsp_pend && rsp_ready) rsp_pend <= 1'b0; // accepted by the return handshake
    end

  handshake_sync #(RS) u_rsp (
    .sclk(pclk), .srst_n(presetn), .s_valid(rsp_pend), .s_data(rsp_p), .s_ready(rsp_ready),
    .dclk(aclk), .drst_n(aresetn), .d_valid(rsp_valid), .d_data(rsp_data));
endmodule
