// tb_bridge -- the final lab: AXI-Lite in on sclk, APB out on dclk. An AXI
// master issues random register writes and reads (some to unmapped addresses,
// which must come back SLVERR). An APB peripheral with 16 registers and 0-3
// wait states answers. Checked:
//   - each AXI transaction becomes exactly one APB transfer with the same
//     direction, address, and data
//   - every response arrives, with the right BRESP/RRESP and read data
//   - ep06's APB rules hold on every pclk cycle
// A final read-back of all 16 registers means a lost write cannot hide.
`timescale 1ps/1ps
module tb_bridge;
  `include "tb_common.svh"
  localparam int AW = 8, N = 150;

  logic          awvalid = 1'b0, wvalid = 1'b0, arvalid = 1'b0, bready = 1'b0, rready = 1'b0;
  logic          awready, wready, arready, bvalid, rvalid;
  logic [AW-1:0] awaddr = '0, araddr = '0;
  logic [31:0]   wdata = '0, rdata;
  logic [1:0]    bresp, rresp;
  logic          psel, penable, pwrite, pready = 1'b0, pslverr = 1'b0;
  logic [AW-1:0] paddr;
  logic [31:0]   pwdata, prdata = '0;

`ifdef BROKEN
  apb_bridge_bad #(AW) dut (
`else
  apb_bridge     #(AW) dut (
`endif
    .aclk(sclk), .aresetn(srst_n),
    .awvalid, .wvalid, .arvalid, .bready, .rready, .awready, .wready, .arready, .bvalid, .rvalid,
    .awaddr, .araddr, .wdata, .bresp, .rresp, .rdata,
    .pclk(dclk), .presetn(drst_n),
    .psel, .penable, .pwrite, .paddr, .pwdata, .pready, .pslverr, .prdata);

  // ---- what crossed: the AXI side records each transaction as {write, addr, wdata}
  logic [AW+32:0] exp_q [$];
  logic [AW+32:0] e_x;
  int unsigned    napb = 0, nwr = 0, nrd = 0, nerr = 0, turns = 0;
  logic           last_wr = 1'b0;

  function automatic string dir(input logic w);
    dir = w ? "write" : "read";
  endfunction

  // ---- the APB peripheral (dclk): 16 registers at 0x00-0x3C, SLVERR above
  logic [31:0]   regs [0:15];
  int unsigned   waits = 0;
  logic          p_psel = 1'b0, p_pen = 1'b0, p_rdy = 1'b0;
  logic [AW+32:0] p_ctl = '0;
  initial for (int i = 0; i < 16; i++) regs[i] = '0;

  always @(posedge dclk) if (drst_n === 1'b1) begin
    // ep06's rules, every cycle
    if (penable && !psel)
      fail("APB: PENABLE without PSEL");
    if (psel && penable && !(p_psel && (!p_pen || !p_rdy)))
      fail("APB: ACCESS without a SETUP cycle before it");
    if (p_psel && !p_pen && !(psel && penable))
      fail("APB: SETUP not followed by ACCESS");
    if (p_psel && p_pen && !p_rdy && !(psel && penable && {pwrite, paddr, pwdata} === p_ctl))
      fail("APB: control moved during a wait state");

    pready <= 1'b0;
    if (psel && !penable) waits = rnd(0, 3);
    else if (psel && penable && !pready) begin
      if (waits != 0) waits--;
      else begin                                    // complete the transfer
        napb++;
        if (exp_q.size() == 0)
          fail($sformatf("APB %s at 0x%02h that the AXI side never sent", dir(pwrite), paddr));
        else begin
          e_x = exp_q.pop_front();
          if (pwrite !== e_x[AW+32] || paddr !== e_x[AW+31:32])
            fail($sformatf("AXI %s to 0x%02h reached APB as a %s to 0x%02h",
                           dir(e_x[AW+32]), e_x[AW+31:32], dir(pwrite), paddr));
          else if (pwrite && pwdata !== e_x[31:0])
            fail($sformatf("AXI write to 0x%02h: sent %08h, APB wrote %08h", paddr, e_x[31:0], pwdata));
        end
        pready  <= 1'b1;
        pslverr <= paddr >= 8'h40;
        prdata  <= (!pwrite && paddr < 8'h40) ? regs[paddr[5:2]] : 32'hDEAD_BEEF;
        if (pwrite && paddr < 8'h40) regs[paddr[5:2]] <= pwdata;
      end
    end
    p_psel = psel; p_pen = penable; p_rdy = pready; p_ctl = {pwrite, paddr, pwdata};
  end

  // ---- the AXI master (sclk)
  logic [31:0]  model [0:15];                       // what software believes is there
  int unsigned  limit;
  initial for (int i = 0; i < 16; i++) model[i] = '0;

  task automatic timeout(input string what);
    fail($sformatf("%s: no response after %0d AXI cycles -- the transaction was lost", what, limit));
    finish_test("bridge");
  endtask

  task automatic axi_write(input logic [AW-1:0] a, input logic [31:0] d);
    int unsigned da, dw, db;
    exp_q.push_back({1'b1, a, d});
    da = rnd(0, 2); dw = rnd(0, 2); db = rnd(0, 3);
    awaddr <= a; wdata <= d;
    for (int i = 0; ; i++) begin                    // AW and W, in either order
      if (i == da) awvalid <= 1'b1;
      if (i == dw) wvalid  <= 1'b1;
      @(posedge sclk);
      if (awvalid && wvalid && awready && wready) break;
      if (i > limit) timeout($sformatf("write 0x%02h", a));
    end
    awvalid <= 1'b0; wvalid <= 1'b0;
    for (int i = 0; ; i++) begin
      if (i == db) bready <= 1'b1;
      @(posedge sclk);
      if (bvalid && bready) break;
      if (i > limit) timeout($sformatf("write 0x%02h", a));
    end
    bready <= 1'b0;
    if (bresp !== (a < 8'h40 ? 2'b00 : 2'b10))
      fail($sformatf("write 0x%02h: BRESP %b", a, bresp));
    if (a < 8'h40) model[a[5:2]] = d; else nerr++;
    nwr++;
  endtask

  task automatic axi_read(input logic [AW-1:0] a);
    int unsigned dr, dd;
    exp_q.push_back({1'b0, a, 32'h0});
    dr = rnd(0, 2); dd = rnd(0, 3);
    araddr <= a;
    for (int i = 0; ; i++) begin
      if (i == dr) arvalid <= 1'b1;
      @(posedge sclk);
      if (arvalid && arready) break;
      if (i > limit) timeout($sformatf("read 0x%02h", a));
    end
    arvalid <= 1'b0;
    for (int i = 0; ; i++) begin
      if (i == dd) rready <= 1'b1;
      @(posedge sclk);
      if (rvalid && rready) break;
      if (i > limit) timeout($sformatf("read 0x%02h", a));
    end
    rready <= 1'b0;
    if (rresp !== (a < 8'h40 ? 2'b00 : 2'b10))
      fail($sformatf("read 0x%02h: RRESP %b", a, rresp));
    else if (a < 8'h40 && rdata !== model[a[5:2]])
      fail($sformatf("read 0x%02h: expected %08h, got %08h", a, model[a[5:2]], rdata));
    if (a >= 8'h40) nerr++;
    nrd++;
  endtask

  logic [AW-1:0] a;
  logic          w;
  initial begin
    wait (srst_n === 1'b1 && drst_n === 1'b1);    // either domain may leave reset first
    limit = src_cycles(80, 40);                    // a generous round trip
    repeat (4) @(posedge dclk);
    @(posedge sclk);
    repeat (N) begin
      a = (rnd(0, 9) == 0) ? AW'(rnd(16, 63) * 4) : AW'(rnd(0, 15) * 4);
      w = rnd(0, 1) != 0;
      if (w != last_wr) turns++;
      last_wr = w;
      if (w) axi_write(a, $random(seed));
      else   axi_read(a);
      repeat (rnd(0, 2)) @(posedge sclk);
    end
    for (int i = 0; i < 16; i++) axi_read(AW'(i * 4));   // read everything back
    if (napb != nwr + nrd)
      fail($sformatf("%0d AXI transactions became %0d APB transfers", nwr + nrd, napb));
    $display("[cov] writes %0d, reads %0d, SLVERR %0d, direction changes %0d", nwr, nrd, nerr, turns);
    finish_test("bridge");
  end
endmodule
