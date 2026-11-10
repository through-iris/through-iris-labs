// tb_top -- the module the VIP plugs into (A1): a clock, a reset, the DUT,
// the virtual interface between them, the protocol assertions on the pins,
// and one call to run_test().
//
//   +UVM_TESTNAME=axi_test     the test (or one of the three breaks)
//   +seed=N                    random seed (run.py also passes +verilator+seed+N)
//   +busy=P                    percent of cycles the slave is busy (default 25)
//   +txns=N                    random transactions after configuration (default 300)
//   +journey                   print one register write's and one write's whole trip
//
// A run that stops moving fails with a "hang:" line: nothing handshakes on
// any channel for HANG cycles while the test still holds its objection.
`timescale 1ns/1ps
module tb_top;
  import uvm_lite_pkg::*;
  import axi_vip_pkg::*;

  localparam int HANG = 2000;

  logic clk = 1'b0, aresetn = 1'b0, busy = 1'b0;
  int unsigned busy_pct = 25;
  longint unsigned last_move = 0;

  axi_if bus (clk, aresetn);

  axi_slave dut (
    .aclk(clk), .aresetn(aresetn), .busy(busy),
    .awid(bus.awid), .awaddr(bus.awaddr), .awlen(bus.awlen), .awsize(bus.awsize),
    .awburst(bus.awburst), .awvalid(bus.awvalid), .awready(bus.awready),
    .wdata(bus.wdata), .wstrb(bus.wstrb), .wlast(bus.wlast), .wvalid(bus.wvalid), .wready(bus.wready),
    .bid(bus.bid), .bresp(bus.bresp), .bvalid(bus.bvalid), .bready(bus.bready),
    .arid(bus.arid), .araddr(bus.araddr), .arlen(bus.arlen), .arsize(bus.arsize),
    .arburst(bus.arburst), .arvalid(bus.arvalid), .arready(bus.arready),
    .rid(bus.rid), .rdata(bus.rdata), .rresp(bus.rresp), .rlast(bus.rlast),
    .rvalid(bus.rvalid), .rready(bus.rready));

  axi_sva u_sva (bus);

  always #5 clk = ~clk;

  always @(posedge clk) begin
    uvm_cycle <= uvm_cycle + 1;
    busy <= ($urandom_range(0, 99) < busy_pct);
    ->uvm_tick;
  end

  // ---- hang watchdog: the test holds its objection, and nothing moves
  always @(posedge clk) if (aresetn && !uvm_stop_request) begin
    if ((bus.awvalid && bus.awready) || (bus.wvalid && bus.wready) || (bus.bvalid && bus.bready) ||
        (bus.arvalid && bus.arready) || (bus.rvalid && bus.rready))
      last_move = uvm_cycle;
    else if (uvm_objections > 0 && uvm_cycle - last_move > HANG) begin
      uvm_report_error("hang", $sformatf("nothing moved on the bus for %0d cycles; the driver is waiting for %s",
                                         HANG, axi_drv_waiting));
      uvm_stop_request = 1;
    end
  end

  initial begin
    string name = "axi_test";
    uvm_component test;
    void'($value$plusargs("seed=%d", axi_seed));
    void'($value$plusargs("busy=%d", busy_pct));
    void'($value$plusargs("UVM_TESTNAME=%s", name));
    axi_journey = $test$plusargs("journey");
    test = axi_create_test(name);
    if (test == null) $fatal(1, "no test called %s", name);
    uvm_config_db #(virtual axi_if)::set(null, "uvm_test_top", "vif", bus);
    fork
      begin repeat (4) @(posedge clk); aresetn <= 1'b1; end
    join_none
    run_test(test);
    $finish;
  end

  // the last line of defence: a run can't outlive this, whatever hangs
  initial begin
    #(64'd50_000_000);
    $display("[cycle %0d] ERROR hang: the simulation ran 5,000,000 cycles", uvm_cycle);
    $finish;
  end
endmodule
