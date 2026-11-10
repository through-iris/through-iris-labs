// axi_sva -- the protocol checker (A2, B2, ep05): the AXI rules, asserted on
// the raw pins. It watches every cycle, independently of the monitor, so it
// fires the instant a rule breaks, whether or not a transaction completes.
// It checks both sides: the driver's VALIDs and the slave's.
//
// The handshake rules are concurrent assertions. The burst bookkeeping
// (WLAST, RLAST, a response only after the write it answers, matching IDs)
// needs counters, so it is written as a clocked block with immediate asserts.
`timescale 1ns/1ps
module axi_sva (axi_if bus);
  import uvm_lite_pkg::*;

  function automatic void fail(string msg);
    uvm_report_error("axi_sva", msg);
  endfunction

  default clocking cb @(posedge bus.clk); endclocking
  default disable iff (!bus.aresetn);

  // ---- once VALID is up, it stays up, with its payload held, until READY
  a_aw_valid: assert property (bus.awvalid && !bus.awready |=> bus.awvalid)
    else fail("AWVALID dropped before AWREADY");
  a_aw_hold:  assert property (bus.awvalid && !bus.awready |=> $stable({bus.awid, bus.awaddr, bus.awlen, bus.awsize, bus.awburst}))
    else fail("AW changed while AWVALID waited for AWREADY");
  a_w_valid:  assert property (bus.wvalid && !bus.wready |=> bus.wvalid)
    else fail("WVALID dropped before WREADY");
  a_w_hold:   assert property (bus.wvalid && !bus.wready |=> $stable({bus.wdata, bus.wstrb, bus.wlast}))
    else fail("WDATA/WSTRB/WLAST changed while WVALID waited for WREADY");
  a_ar_valid: assert property (bus.arvalid && !bus.arready |=> bus.arvalid)
    else fail("ARVALID dropped before ARREADY");
  a_ar_hold:  assert property (bus.arvalid && !bus.arready |=> $stable({bus.arid, bus.araddr, bus.arlen, bus.arsize, bus.arburst}))
    else fail("AR changed while ARVALID waited for ARREADY");
  a_b_valid:  assert property (bus.bvalid && !bus.bready |=> bus.bvalid)
    else fail("BVALID dropped before BREADY");
  a_b_hold:   assert property (bus.bvalid && !bus.bready |=> $stable({bus.bid, bus.bresp}))
    else fail("BRESP/BID changed while BVALID waited for BREADY");
  a_r_valid:  assert property (bus.rvalid && !bus.rready |=> bus.rvalid)
    else fail("RVALID dropped before RREADY");
  a_r_hold:   assert property (bus.rvalid && !bus.rready |=> $stable({bus.rid, bus.rdata, bus.rresp, bus.rlast}))
    else fail("RDATA/RRESP/RLAST changed while RVALID waited for RREADY");

  // ---- bursts: WLAST and RLAST on the right beat, no 4 KB crossing (ep02),
  // a write response only after its address and last data beat, IDs echoed
  int unsigned aw_len_q[$], aw_id_q[$], w_beats_q[$], ar_len_q[$], ar_id_q[$];
  int unsigned w_beat = 0, r_beat = 0, w_done = 0, aw_done = 0, b_done = 0;

  always @(posedge bus.clk) if (bus.aresetn) begin
    if (bus.awvalid && bus.awready) begin
      if ({4'd0, bus.awaddr[11:0]} + 16'(4 * (bus.awlen + 1)) > 16'h1000)
        fail($sformatf("write burst at 0x%04h, %0d beats, crosses a 4 KB boundary", bus.awaddr, bus.awlen + 1));
      aw_len_q.push_back(bus.awlen); aw_id_q.push_back(bus.awid); aw_done++;
    end
    if (bus.wvalid && bus.wready) begin
      w_beat++;
      if (bus.wlast) begin w_beats_q.push_back(w_beat); w_beat = 0; w_done++; end
    end
    while (aw_len_q.size() > 0 && w_beats_q.size() > 0) begin
      if (w_beats_q[0] != aw_len_q[0] + 1)
        fail($sformatf("WLAST on beat %0d of a %0d-beat write", w_beats_q[0], aw_len_q[0] + 1));
      void'(aw_len_q.pop_front());
      void'(w_beats_q.pop_front());
    end
    if (bus.bvalid && bus.bready) begin
      if (b_done >= aw_done || b_done >= w_done)
        fail("BVALID before the write's address and last data beat were taken");
      else if (bus.bid != aw_id_q[0])
        fail($sformatf("BID %0d, the write was AWID %0d", bus.bid, aw_id_q[0]));
      if (aw_id_q.size() > 0) void'(aw_id_q.pop_front());
      b_done++;
    end
    if (bus.arvalid && bus.arready) begin
      if ({4'd0, bus.araddr[11:0]} + 16'(4 * (bus.arlen + 1)) > 16'h1000)
        fail($sformatf("read burst at 0x%04h, %0d beats, crosses a 4 KB boundary", bus.araddr, bus.arlen + 1));
      ar_len_q.push_back(bus.arlen); ar_id_q.push_back(bus.arid);
    end
    if (bus.rvalid && bus.rready) begin
      if (ar_len_q.size() == 0) fail("RVALID with no read in flight");
      else begin
        r_beat++;
        if (bus.rid != ar_id_q[0]) fail($sformatf("RID %0d, the read was ARID %0d", bus.rid, ar_id_q[0]));
        if (bus.rlast != (r_beat == ar_len_q[0] + 1))
          fail($sformatf("RLAST %0d on beat %0d of a %0d-beat read", bus.rlast, r_beat, ar_len_q[0] + 1));
        if (bus.rlast || r_beat == ar_len_q[0] + 1) begin
          void'(ar_len_q.pop_front()); void'(ar_id_q.pop_front()); r_beat = 0;
        end
      end
    end
  end
endmodule
