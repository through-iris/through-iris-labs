// axi_reg_block -- the register model (A2, B3, ep04): a mirror of the
// slave's registers, so a test reads and writes config by name, not address.
// The table is the slave's register map, written once:
//
//   offset  register  field        bits    access  reset
//   0x00    id        id           [31:0]  RO      0x4158_4931
//   0x04    ctrl      en           [0]     RW      0
//                     mode         [9:8]   RW      0
//   0x08    base      page         [15:12] RW      1   (the window at 0x1000)
//   0x0C    status    ready        [0]     RO      1
//
// axi_reg_adapter turns a register access into an axi_seq_item, so it goes
// out through the same sequencer, driver and pins as everything else (C2).
class axi_reg_id extends uvm_reg;
  `uvm_object_utils(axi_reg_id)
  uvm_reg_field id;
  function new(string name = "id"); super.new(name); endfunction
  function void build();
    id = new("id"); id.configure(this, 32, 0, "RO", 32'h4158_4931);
  endfunction
endclass

class axi_reg_ctrl extends uvm_reg;
  `uvm_object_utils(axi_reg_ctrl)
  uvm_reg_field en, mode;
  function new(string name = "ctrl"); super.new(name); endfunction
  function void build();
    en   = new("en");   en.configure(this, 1, 0, "RW", 0);
    mode = new("mode"); mode.configure(this, 2, 8, "RW", 0);
  endfunction
endclass

class axi_reg_base extends uvm_reg;
  `uvm_object_utils(axi_reg_base)
  uvm_reg_field page;
  function new(string name = "base"); super.new(name); endfunction
  function void build();
    page = new("page"); page.configure(this, 4, 12, "RW", 1);
  endfunction
endclass

class axi_reg_status extends uvm_reg;
  `uvm_object_utils(axi_reg_status)
  uvm_reg_field ready;
  function new(string name = "status"); super.new(name); endfunction
  function void build();
    ready = new("ready"); ready.configure(this, 1, 0, "RO", 1);
  endfunction
endclass

class axi_reg_block extends uvm_reg_block;
  `uvm_object_utils(axi_reg_block)

  axi_reg_id     id;
  axi_reg_ctrl   ctrl;
  axi_reg_base   base;
  axi_reg_status status;
  uvm_reg_map         map;

  function new(string name = "ral");
    super.new(name);
  endfunction

  virtual function void build();
    map    = new("map");
    map.m_base = 16'h0000;
    id     = axi_reg_id    ::type_id::create("id");     id.build();
    ctrl   = axi_reg_ctrl  ::type_id::create("ctrl");   ctrl.build();
    base   = axi_reg_base  ::type_id::create("base");   base.build();
    status = axi_reg_status::type_id::create("status"); status.build();
    map.add_reg(id,     16'h00);
    map.add_reg(ctrl,   16'h04);
    map.add_reg(base,   16'h08);
    map.add_reg(status, 16'h0C);
    m_regs = '{id, ctrl, base, status};
    foreach (m_regs[i]) m_regs[i].m_path = {get_name(), ".", m_regs[i].get_name()};
  endfunction
endclass

// register operation <-> AXI transaction
class axi_reg_adapter extends uvm_reg_adapter;
  `uvm_object_utils(axi_reg_adapter)

  function new(string name = "axi_reg_adapter");
    super.new(name);
    supports_byte_enable = 1;
  endfunction

  virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
    axi_seq_item t = axi_seq_item::type_id::create("reg_item");
    t.kind = (rw.kind == UVM_WRITE) ? AXI_WRITE : AXI_READ;
    t.addr = 16'(rw.addr);
    t.len  = 0;                              // a register is one beat
    t.id   = 4'hF;
    t.data = '{rw.data};
    t.strb = '{rw.byte_en};                  // only the bytes the access is for
    t.trace = axi_trace_reg;
    return t;
  endfunction

  virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
    axi_seq_item t;
    if (!$cast(t, bus_item)) $fatal(1, "axi_reg_adapter: not an axi_seq_item");
    rw.kind   = (t.kind == AXI_WRITE) ? UVM_WRITE : UVM_READ;
    rw.addr   = t.addr;
    rw.data   = (t.kind == AXI_READ) ? t.data[0] : rw.data;
    rw.status = (t.resp == AXI_OKAY) ? UVM_IS_OK : UVM_NOT_OK;
  endfunction
endclass
