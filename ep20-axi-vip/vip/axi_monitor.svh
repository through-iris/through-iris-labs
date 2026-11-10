// axi_monitor -- watches the same pins the driver drives, rebuilds each
// transaction and its response, and broadcasts it on its analysis port (B1).
// Nobody drives anything to the monitor. It only watches, so it reports what
// happened on the bus, not what the driver meant to do.
//
// AW, W and B are collected separately and joined when the response arrives,
// so it works whichever of AW and W comes first.
class axi_monitor extends uvm_monitor;
  `uvm_component_utils(axi_monitor)

  virtual axi_if vif;
  uvm_analysis_port #(axi_seq_item) ap;
  int unsigned n_sent;                     // transactions broadcast

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap");
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db #(virtual axi_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "no virtual interface in uvm_config_db")
  endfunction

  task run_phase(uvm_phase phase);
    axi_seq_item aw_q[$], w_q[$], ar_q[$];
    axi_seq_item w_cur, t;
    forever begin
      @(posedge vif.clk);
      if (!vif.aresetn) continue;
      // ---- write address
      if (vif.awvalid && vif.awready) begin
        t = axi_seq_item::type_id::create("mon_wr");
        t.kind = AXI_WRITE; t.addr = vif.awaddr; t.len = vif.awlen; t.id = vif.awid;
        aw_q.push_back(t);
      end
      // ---- write data: one burst until WLAST
      if (vif.wvalid && vif.wready) begin
        if (w_cur == null) w_cur = axi_seq_item::type_id::create("mon_w");
        w_cur.data.push_back(vif.wdata);
        w_cur.strb.push_back(vif.wstrb);
        if (vif.wlast) begin
          w_q.push_back(w_cur);
          w_cur = null;
        end
      end
      // ---- write response: the transaction is complete
      if (vif.bvalid && vif.bready) begin
        if (aw_q.size() == 0 || w_q.size() == 0)
          `uvm_error("MON", "a write response with no complete write in flight")
        else begin
          t = aw_q.pop_front();
          w_cur = w_q.pop_front();
          t.data = w_cur.data; t.strb = w_cur.strb;
          w_cur = null;
          t.resp = axi_resp_e'(vif.bresp);
          broadcast(t);
        end
      end
      // ---- read address
      if (vif.arvalid && vif.arready) begin
        t = axi_seq_item::type_id::create("mon_rd");
        t.kind = AXI_READ; t.addr = vif.araddr; t.len = vif.arlen; t.id = vif.arid;
        ar_q.push_back(t);
      end
      // ---- read data, in order, until RLAST
      if (vif.rvalid && vif.rready) begin
        if (ar_q.size() == 0)
          `uvm_error("MON", "read data with no read in flight")
        else begin
          t = ar_q[0];
          t.data.push_back(vif.rdata);
          t.rresp.push_back(axi_resp_e'(vif.rresp));
          if (vif.rlast) begin
            void'(ar_q.pop_front());
            t.resp = t.rresp[0];
            broadcast(t);
          end
        end
      end
    end
  endtask

  // one broadcast: every subscriber gets the same transaction
  function void broadcast(axi_seq_item t);
    if (axi_trace_next) begin
      t.trace = 1;
      axi_trace_next = 0;
      `uvm_info("DUT", $sformatf("responds: %s %s", axi_pick(t.kind == AXI_WRITE, "BRESP", "RRESP"),
                axi_resp_name(t.resp)), UVM_NONE)
      `uvm_info("monitor", $sformatf("rebuilt from the pins: %s, %s -> analysis port, %0d subscriber%s",
                t.convert2string(), axi_resp_name(t.resp), ap.size(), axi_pick(ap.size() == 1, "", "s")), UVM_NONE)
    end
    n_sent++;
    ap.write(t);
  endfunction
endclass
