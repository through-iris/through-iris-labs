// axi_rand_seq -- random traffic: reads and writes, bursts of 1-8 beats, to
// the memory window, the read-only registers and unmapped space.
class axi_rand_seq extends uvm_sequence #(axi_seq_item);
  `uvm_object_utils(axi_rand_seq)

  int unsigned n = 100;
  bit [15:0]   win_base = 16'h1000;   // where the memory window is
  int          force_kind = -1;       // -1: random; else every item is this kind
  bit          mem_only;              // only the memory window
  bit          trace_first_write;     // +journey: trace the first write

  function new(string name = "axi_rand_seq");
    super.new(name);
  endfunction

  task body();
    repeat (n) begin
      axi_seq_item t = axi_seq_item::type_id::create("t");
      start_item(t);
      t.win_base = win_base;
      if (!t.randomize() with { force_kind >= 0 -> kind == axi_kind_e'(force_kind[0]);
                                mem_only -> region == AXI_MEM; })
        `uvm_error("SEQ", "randomize() failed")
      if (trace_first_write && t.kind == AXI_WRITE) begin
        t.trace = 1;
        trace_first_write = 0;
        `uvm_info("vseq", {"creates ", t.convert2string()}, UVM_NONE)
      end
      finish_item(t);
    end
  endtask
endclass

// axi_vseq -- the virtual sequence the test starts (B1, B3, C3).
//   1. traffic before configuration: the window is off, so SLVERR
//   2. configure by name: the base address, a mode, the enable (B3)
//   3. read every register back and check it against the mirror
//   4. random traffic into the new window
//   5. read every register back again
class axi_vseq extends uvm_sequence #(axi_seq_item);
  `uvm_object_utils(axi_vseq)

  axi_reg_block ral;
  axi_cfg       cfg;

  function new(string name = "axi_vseq");
    super.new(name);
  endfunction

  task body();
    uvm_status_e status;
    axi_rand_seq rs;
    if (!uvm_config_db #(axi_reg_block)::get(null, "", "ral", ral)) `uvm_fatal("VSEQ", "no register model")
    if (!uvm_config_db #(axi_cfg)::get(null, "uvm_test_top.env", "cfg", cfg)) `uvm_fatal("VSEQ", "no axi_cfg")

    // 1. the window is where BASE says (the mirror knows the reset value), and off
    for (int k = 0; k < 2; k++) begin
      rs = axi_rand_seq::type_id::create("pre");
      rs.n = 3; rs.force_kind = k; rs.mem_only = 1;
      rs.win_base = 16'(ral.base.get_mirrored_value());
      rs.start(m_sequencer);
    end

    // 2. configuration, by name: the test says what it means, not where it lives
    ral.base.page.write(status, cfg.base_page);        // set the slave's base address
    ral.map.m_trace = axi_journey;                     // +journey: follow this one
    axi_trace_reg   = axi_journey;
    if (axi_journey) `uvm_info("test", $sformatf("ral.ctrl.mode.write(status, %0d)", cfg.mode), UVM_NONE)
    ral.ctrl.mode.write(status, cfg.mode);             // enable a mode
    ral.map.m_trace = 0;
    axi_trace_reg   = 0;
    ral.ctrl.en.write(status, 1);                      // and switch the window on

    // 3. is the DUT what the test believes?
    ral.mirror(status, UVM_CHECK);

    // 4. traffic, into the window where the mirror says it now is
    rs = axi_rand_seq::type_id::create("traffic");
    rs.n = cfg.n_txns;
    rs.win_base = 16'(ral.base.get_mirrored_value());
    rs.trace_first_write = axi_journey;
    rs.start(m_sequencer);

    // 5. and again at the end
    ral.mirror(status, UVM_CHECK);
  endtask
endclass
