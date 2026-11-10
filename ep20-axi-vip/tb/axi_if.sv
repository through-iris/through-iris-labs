// axi_if -- the AXI pins between the VIP and the design (A1: "the DUT sits
// outside, joined by a virtual interface"). The driver drives the master
// side, the monitor and the assertions only watch.
//
// AXI4, 32-bit data, 16-bit addresses, 4-bit IDs. AxSIZE is always 4 bytes
// and AxBURST always INCR in this lab, so the slave ignores both.
interface axi_if (input logic clk, input logic aresetn);
  // write address
  logic [3:0]  awid;
  logic [15:0] awaddr;
  logic [7:0]  awlen;
  logic [2:0]  awsize;
  logic [1:0]  awburst;
  logic        awvalid, awready;
  // write data
  logic [31:0] wdata;
  logic [3:0]  wstrb;
  logic        wlast, wvalid, wready;
  // write response
  logic [3:0]  bid;
  logic [1:0]  bresp;
  logic        bvalid, bready;
  // read address
  logic [3:0]  arid;
  logic [15:0] araddr;
  logic [7:0]  arlen;
  logic [2:0]  arsize;
  logic [1:0]  arburst;
  logic        arvalid, arready;
  // read data
  logic [3:0]  rid;
  logic [31:0] rdata;
  logic [1:0]  rresp;
  logic        rlast, rvalid, rready;
endinterface
