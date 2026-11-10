// axi_agent -- the one component that touches the pins (A2, ep08): the
// sequencer feeds the driver, the driver drives, the monitor watches.
class axi_sequencer extends uvm_sequencer #(axi_seq_item);
  `uvm_component_utils(axi_sequencer)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass

class axi_agent extends uvm_agent;
  `uvm_component_utils(axi_agent)

  axi_sequencer seqr;
  axi_driver    drv;
  axi_monitor   mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    seqr = axi_sequencer::type_id::create("seqr", this);
    drv  = axi_driver   ::type_id::create("drv",  this);
    mon  = axi_monitor  ::type_id::create("mon",  this);
  endfunction

  function void connect_phase(uvm_phase phase);
    drv.seq_item_port.connect(seqr.seq_item_export);
  endfunction
endclass
