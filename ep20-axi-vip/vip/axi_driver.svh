// axi_driver -- turns a transaction into the AXI write or read channels (B1),
// honouring every handshake: a VALID, once raised, stays up with its payload
// held until READY (ep05). Then it puts the response back on the same item.
//
// Pins are driven with nonblocking assignments just after a rising edge, and
// READY is sampled at the edge, the same way the slave sees it.
//
// Break 3 (vip/broken/axi_driver_backoff.svh) is a factory override of
// drive_w_beat() below.
class axi_driver extends uvm_driver #(axi_seq_item);
  `uvm_component_utils(axi_driver)

  virtual axi_if vif;
  axi_cfg        cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db #(virtual axi_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "no virtual interface in uvm_config_db")
    if (!uvm_config_db #(axi_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "no axi_cfg in uvm_config_db")
  endfunction

  task run_phase(uvm_phase phase);
    axi_seq_item req;
    idle();
    while (!vif.aresetn) @(posedge vif.clk);
    forever begin
      seq_item_port.get_next_item(req);
      if (req.trace) begin
        `uvm_info("sequencer", {"hands the driver: ", req.convert2string()}, UVM_NONE)
        axi_trace_next = 1;                        // so the monitor tags its copy
      end
      if (req.kind == AXI_WRITE) drive_write(req);
      else                       drive_read(req);
      seq_item_port.item_done();
    end
  endtask

  function void idle();
    vif.awvalid <= 1'b0; vif.wvalid <= 1'b0; vif.bready <= 1'b0;
    vif.arvalid <= 1'b0; vif.rready <= 1'b0;
    vif.awid <= '0; vif.awaddr <= '0; vif.awlen <= '0; vif.awsize <= 3'd2; vif.awburst <= 2'b01;
    vif.arid <= '0; vif.araddr <= '0; vif.arlen <= '0; vif.arsize <= 3'd2; vif.arburst <= 2'b01;
    vif.wdata <= '0; vif.wstrb <= '0; vif.wlast <= 1'b0;
  endfunction

  function int unsigned gap();
    return ($urandom_range(0, 3) == 0) ? $urandom_range(0, cfg.max_gap) : 0;
  endfunction

  // ---- write: AW and W go out together, then the driver waits for B
  task drive_write(axi_seq_item t);
    axi_drv_waiting = $sformatf("AWREADY/WREADY on the write to 0x%04h", t.addr);
    fork
      begin
        repeat (gap()) @(posedge vif.clk);
        vif.awvalid <= 1'b1; vif.awid <= t.id; vif.awaddr <= t.addr; vif.awlen <= t.len;
        vif.awsize <= 3'd2; vif.awburst <= 2'b01;  // 4 bytes a beat, INCR
        do @(posedge vif.clk); while (!vif.awready);
        vif.awvalid <= 1'b0;
        if (t.trace) `uvm_info("driver", $sformatf("AW: 0x%04h, AWLEN %0d, taken", t.addr, t.len), UVM_NONE)
      end
      for (int i = 0; i <= t.len; i++) begin
        drive_w_beat(t, i);
        if (t.trace) `uvm_info("driver", $sformatf("W beat %0d of %0d: 0x%08h, WSTRB %h%s", i + 1, t.len + 1,
                                t.data[i], t.strb[i], axi_pick(i == t.len, ", WLAST", "")), UVM_NONE)
      end
    join
    axi_drv_waiting = $sformatf("BVALID on the write to 0x%04h", t.addr);
    forever begin                                  // BREADY, with a little backpressure
      vif.bready <= ($urandom_range(0, 3) != 0);
      @(posedge vif.clk);
      if (vif.bvalid && vif.bready) break;
    end
    vif.bready <= 1'b0;
    t.resp = axi_resp_e'(vif.bresp);
    axi_drv_waiting = "the next item from the sequencer";
  endtask

  // one W beat. Any idle time goes BEFORE VALID; once VALID is up it is held,
  // with the data, until the slave takes it.
  virtual task drive_w_beat(axi_seq_item t, int i);
    repeat (gap()) @(posedge vif.clk);
    vif.wvalid <= 1'b1;
    vif.wdata  <= t.data[i];
    vif.wstrb  <= t.strb[i];
    vif.wlast  <= (i == t.len);
    do @(posedge vif.clk); while (!vif.wready);
    vif.wvalid <= 1'b0;
  endtask

  // ---- read: AR, then collect R beats until RLAST
  task drive_read(axi_seq_item t);
    axi_drv_waiting = $sformatf("ARREADY on the read from 0x%04h", t.addr);
    repeat (gap()) @(posedge vif.clk);
    vif.arvalid <= 1'b1; vif.arid <= t.id; vif.araddr <= t.addr; vif.arlen <= t.len;
    vif.arsize <= 3'd2; vif.arburst <= 2'b01;
    do @(posedge vif.clk); while (!vif.arready);
    vif.arvalid <= 1'b0;
    axi_drv_waiting = $sformatf("RVALID/RLAST on the read from 0x%04h", t.addr);
    t.data.delete(); t.rresp.delete();
    forever begin
      vif.rready <= ($urandom_range(0, 3) != 0);
      @(posedge vif.clk);
      if (vif.rvalid && vif.rready) begin
        t.data.push_back(vif.rdata);
        t.rresp.push_back(axi_resp_e'(vif.rresp));
        if (vif.rlast) break;
      end
    end
    vif.rready <= 1'b0;
    t.resp = t.rresp[0];
    axi_drv_waiting = "the next item from the sequencer";
  endtask
endclass
