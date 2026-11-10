// Break 2 (B3, C2) -- a register adapter that drops the byte enables.
//
// "Registers are 32 bits, so a register write is a full word." The adapter
// still says it supports byte enables, so the register model writes one
// field by itself as a write of just that field's bytes: ctrl.en is byte 0,
// ctrl.mode is byte 1. This adapter turns each into a full-word write. The
// write of `en` lands on all four bytes and puts MODE back to 0.
//
// Every bus-level check is green: the slave did exactly what the pins told
// it, the scoreboard agrees, coverage fills. Only the register model knows
// the test meant something else. Caught by reading CTRL back by name and
// checking it against the mirror: ral.mirror(status, UVM_CHECK).
class axi_reg_adapter_no_strb extends axi_reg_adapter;
  `uvm_object_utils(axi_reg_adapter_no_strb)

  function new(string name = "axi_reg_adapter_no_strb");
    super.new(name);
  endfunction

  virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
    axi_seq_item t = axi_seq_item::type_id::create("reg_item");
    t.kind = (rw.kind == UVM_WRITE) ? AXI_WRITE : AXI_READ;
    t.addr = 16'(rw.addr);
    t.len  = 0;                              // a register is one beat
    t.id   = 4'hF;
    t.data = '{rw.data};
    t.strb = '{4'hF};                        // the bug: every byte, whatever rw.byte_en says
    t.trace = axi_trace_reg;
    return t;
  endfunction
endclass
