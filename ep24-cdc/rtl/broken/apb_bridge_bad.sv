// apb_bridge_bad -- the final lab. The same bridge as rtl/apb_bridge.sv, the
// way it often gets written the first time. It passes plain simulation at the
// usual clock ratio (AXI fast, APB slow). It contains two CDC bugs.
//
// Find them before you open SOLUTION.md. Every bug in it is one of the
// episode's three breaks. Start with:
//     python run.py bridge --broken --clocks fast2slow            # green
//     python run.py bridge --broken --clocks fast2slow --inject   # ?
//     python run.py bridge --broken --clocks slow2fast            # ?
module apb_bridge_bad #(parameter int AW = 8) (
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

  logic          busy_a, wr_a, tog_a, dir_a, done_s, done_q;
  logic [AW-1:0] addr_a;
  logic [31:0]   wdata_a;
  logic          tog_s, tog_q, dir_s, done_p, slverr_p;
  logic [31:0]   rdata_p;

  // ---- aclk: accept one transaction, flag it across, wait for done
  wire wr_go = !busy_a && awvalid && wvalid;     // AW and W together
  wire rd_go = !busy_a && arvalid && !wr_go;     // writes first
  assign awready = wr_go;
  assign wready  = wr_go;
  assign arready = rd_go;

  sync_2ff #(1) u_done (.clk(aclk), .rst_n(aresetn), .d(done_p), .q(done_s));

  always_ff @(posedge aclk or negedge aresetn)
    if (!aresetn) begin
      busy_a <= 1'b0; wr_a <= 1'b0; tog_a <= 1'b0; dir_a <= 1'b0;
      addr_a <= '0; wdata_a <= '0; done_q <= 1'b0;
      bvalid <= 1'b0; bresp <= 2'b00;
      rvalid <= 1'b0; rresp <= 2'b00; rdata <= '0;
    end else begin
      done_q <= done_s;
      if (wr_go || rd_go) begin                  // held until the next transaction
        busy_a <= 1'b1; wr_a <= wr_go; tog_a <= ~tog_a; dir_a <= wr_go;
        addr_a <= wr_go ? awaddr : araddr; wdata_a <= wdata;
      end
      if (done_s && !done_q) begin               // the answer is back
        if (wr_a) begin bvalid <= 1'b1; bresp <= {slverr_p, 1'b0}; end
        else      begin rvalid <= 1'b1; rresp <= {slverr_p, 1'b0}; rdata <= rdata_p; end
      end
      if (bvalid && bready) begin bvalid <= 1'b0; busy_a <= 1'b0; end
      if (rvalid && rready) begin rvalid <= 1'b0; busy_a <= 1'b0; end
    end

  // ---- pclk: ep06's state machine, IDLE -> SETUP -> ACCESS until PREADY
  sync_2ff #(1) u_tog (.clk(pclk), .rst_n(presetn), .d(tog_a), .q(tog_s));
  sync_2ff #(1) u_dir (.clk(pclk), .rst_n(presetn), .d(dir_a), .q(dir_s));

  always_ff @(posedge pclk or negedge presetn)
    if (!presetn) begin
      tog_q <= 1'b0; done_p <= 1'b0; rdata_p <= '0; slverr_p <= 1'b0;
      psel <= 1'b0; penable <= 1'b0; pwrite <= 1'b0; paddr <= '0; pwdata <= '0;
    end else begin
      tog_q  <= tog_s;
      done_p <= 1'b0;
      if (tog_s != tog_q) begin                  // SETUP: a new request
        psel <= 1'b1; pwrite <= dir_s; paddr <= addr_a; pwdata <= wdata_a;
      end else if (psel && !penable) begin       // ACCESS
        penable <= 1'b1;
      end else if (psel && pready) begin         // done
        psel <= 1'b0; penable <= 1'b0;
        rdata_p <= pwrite ? 32'h0 : prdata; slverr_p <= pslverr;
        done_p <= 1'b1;
      end
    end
endmodule
