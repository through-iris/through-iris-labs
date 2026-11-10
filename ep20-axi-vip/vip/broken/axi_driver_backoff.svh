// Break 3 (B1, B2) -- a driver that backs off when the slave is busy.
//
// "Don't hold the bus while the slave is busy: drop WVALID, wait a little,
// try again." Polite, and illegal: once VALID is up it must stay up, with
// its data, until READY (ep05). This slave happens not to care. It only acts
// on VALID and READY together, so every beat it takes is the right beat. The
// monitor samples on the handshake too, so it rebuilds the right
// transaction. The scoreboard agrees and coverage fills.
//
// A slave that registers VALID, or an interconnect that starts routing on
// it, would not be so forgiving. Caught only by the protocol assertions on
// the raw pins (sva/axi_sva.sv), which fire whether or not the transaction
// completed (B2).
class axi_driver_backoff extends axi_driver;
  `uvm_component_utils(axi_driver_backoff)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task drive_w_beat(axi_seq_item t, int i);
    vif.wvalid <= 1'b1;
    vif.wdata  <= t.data[i];
    vif.wstrb  <= t.strb[i];
    vif.wlast  <= (i == t.len);
    @(posedge vif.clk);
    while (!vif.wready) begin
      vif.wvalid <= 1'b0;                    // the bug: VALID drops before READY
      repeat (1 + gap()) @(posedge vif.clk);
      vif.wvalid <= 1'b1;
      @(posedge vif.clk);
    end
    vif.wvalid <= 1'b0;
  endtask
endclass
