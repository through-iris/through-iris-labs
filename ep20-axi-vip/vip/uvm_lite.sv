// uvm_lite.sv -- the parts of UVM this lab uses, in plain SystemVerilog.
//
// This is NOT the UVM library. It is a small stand-in with the same class
// names and the same shape, so the VIP in this folder reads like the code in
// the episode (uvm_env, build_phase, type_id::create, analysis ports,
// uvm_config_db, objections, a register model) and still runs on a free
// simulator with nothing to download. Each piece here does the one job the
// lab needs from it, and nothing else:
//
//   uvm_component, phases   build top-down, connect, run (forked), check, report
//   objections              the run phase ends when the test drops its last one
//   the factory             type_id::create, and set_type_override, which is
//                           how the three breaks swap a component in (C1)
//   uvm_config_db           set/get by hierarchical path, "*" wildcards
//   analysis port / imp     one write() fanned out to every subscriber (A3)
//   sequencer / sequence    a mailbox: first come, first served, which is
//                           UVM's default arbitration (SEQ_ARB_FIFO)
//   register model          fields, registers, a map, an adapter, a mirror,
//                           auto-predict, and mirror() with a check (B3)
//
// What's left out: the full phase schedule, the report server's verbosity
// controls per id, sequence arbitration other than FIFO, the TLM FIFOs,
// callbacks, the register model's backdoor, frontdoor sequences and
// predictor component. Swap in the real library and the VIP classes need
// small changes, mostly in the register model (see README).
`timescale 1ns/1ps
package uvm_lite_pkg;

  // ---------------------------------------------------------------- reporting
  longint unsigned uvm_cycle = 0;           // tb_top counts clock edges
  event            uvm_tick;                // ...and fires this on each one
  int unsigned     uvm_errors = 0;
  int unsigned     uvm_id_count[string];    // errors per id: "SB", "RegModel", "axi_sva"
  int unsigned     uvm_objections = 0;
  bit              uvm_objection_raised = 0;
  bit              uvm_stop_request = 0;    // set by the hang watchdog in tb_top

  typedef enum int {UVM_NONE = 0, UVM_LOW = 100, UVM_MEDIUM = 200, UVM_HIGH = 300} uvm_verbosity;
  uvm_verbosity uvm_verbosity_level = UVM_LOW;

  function automatic void uvm_report_error(string id, string msg);
    uvm_errors++;
    if (uvm_id_count.exists(id)) uvm_id_count[id]++;
    else uvm_id_count[id] = 1;
    if (uvm_errors <= 10) $display("[cycle %0d] ERROR %s: %s", uvm_cycle, id, msg);
    if (uvm_errors == 10) $display("          (further errors counted, not printed)");
  endfunction

  function automatic void uvm_report_info(string id, string msg, uvm_verbosity v);
    if (v <= uvm_verbosity_level) $display("[cycle %0d] %-10s %s", uvm_cycle, id, msg);
  endfunction

  function automatic int unsigned uvm_count(string id);
    return uvm_id_count.exists(id) ? uvm_id_count[id] : 0;
  endfunction

  // "a.b.*" matches "a.b.c.d"; "*" matches anything; otherwise exact
  function automatic bit uvm_is_match(string pattern, string path);
    string pre;
    int n = pattern.len();
    if (pattern == "*") return 1;
    if (n < 2 || pattern[n - 1] != "*") return pattern == path;
    pre = pattern.substr(0, n - 2);
    return path.len() >= pre.len() && path.substr(0, pre.len() - 1) == pre;
  endfunction

  // ---------------------------------------------------------------- objects
  virtual class uvm_object;
    string m_name;
    function new(string name = "");
      m_name = name;
    endfunction
    function string get_name();
      return m_name;
    endfunction
    virtual function string get_type_name();
      return "uvm_object";
    endfunction
  endclass

  typedef class uvm_component;
  typedef class uvm_phase;

  // the factory's handle on a type: it knows how to make one
  virtual class uvm_object_wrapper;
    virtual function uvm_object create_object(string name);
      return null;
    endfunction
    virtual function uvm_component create_component(string name, uvm_component parent);
      return null;
    endfunction
    virtual function string get_type_name();
      return "";
    endfunction
  endclass

  // ---------------------------------------------------------------- the factory
  // One registry per type. create() asks the registry, and the registry makes
  // either the type itself or whatever a test overrode it with. That is the
  // whole point of create-not-new (C1): the env never names the override.
  class uvm_component_registry #(type T = uvm_component, string Tname = "<unknown>")
      extends uvm_object_wrapper;
    static uvm_component_registry #(T, Tname) m_me;
    static uvm_object_wrapper m_override;

    static function uvm_component_registry #(T, Tname) get();
      if (m_me == null) m_me = new();
      return m_me;
    endfunction

    virtual function uvm_component create_component(string name, uvm_component parent);
      T obj = new(name, parent);
      return obj;
    endfunction

    virtual function string get_type_name();
      return Tname;
    endfunction

    static function T create(string name, uvm_component parent);
      uvm_object_wrapper w = (m_override != null) ? m_override : get();
      uvm_component c = w.create_component(name, parent);
      T t;
      if (!$cast(t, c)) $fatal(1, "factory: %s is not a %s", w.get_type_name(), Tname);
      return t;
    endfunction

    static function void set_type_override(uvm_object_wrapper override_type);
      m_override = override_type;
    endfunction
  endclass

  class uvm_object_registry #(type T = uvm_object, string Tname = "<unknown>")
      extends uvm_object_wrapper;
    static uvm_object_registry #(T, Tname) m_me;
    static uvm_object_wrapper m_override;

    static function uvm_object_registry #(T, Tname) get();
      if (m_me == null) m_me = new();
      return m_me;
    endfunction

    virtual function uvm_object create_object(string name);
      T obj = new(name);
      return obj;
    endfunction

    virtual function string get_type_name();
      return Tname;
    endfunction

    // UVM's create takes a parent too; an object ignores it
    static function T create(string name = "", uvm_component parent = null);
      uvm_object_wrapper w = (m_override != null) ? m_override : get();
      uvm_object o = w.create_object(name);
      T t;
      if (!$cast(t, o)) $fatal(1, "factory: %s is not a %s", w.get_type_name(), Tname);
      return t;
    endfunction

    static function void set_type_override(uvm_object_wrapper override_type);
      m_override = override_type;
    endfunction
  endclass

  // ---------------------------------------------------------------- phases
  class uvm_phase;
    string m_name;
    function new(string name);
      m_name = name;
    endfunction
    function string get_name();
      return m_name;
    endfunction
    // the run phase lasts exactly as long as someone holds an objection (C3)
    function void raise_objection(uvm_object obj, string description = "");
      uvm_objections++;
      uvm_objection_raised = 1;
    endfunction
    function void drop_objection(uvm_object obj, string description = "");
      if (uvm_objections > 0) uvm_objections--;
    endfunction
  endclass

  // ---------------------------------------------------------------- components
  virtual class uvm_component extends uvm_object;
    uvm_component m_parent;
    uvm_component m_children[$];

    function new(string name, uvm_component parent);
      super.new(name);
      m_parent = parent;
      if (parent != null) parent.m_children.push_back(this);
    endfunction

    function string get_full_name();
      return (m_parent == null) ? m_name : {m_parent.get_full_name(), ".", m_name};
    endfunction

    virtual function void build_phase(uvm_phase phase); endfunction
    virtual function void connect_phase(uvm_phase phase); endfunction
    virtual task run_phase(uvm_phase phase); endtask
    virtual function void check_phase(uvm_phase phase); endfunction
    virtual function void report_phase(uvm_phase phase); endfunction
  endclass

  virtual class uvm_test extends uvm_component;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
  endclass
  virtual class uvm_env extends uvm_component;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
  endclass
  virtual class uvm_agent extends uvm_component;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
  endclass
  virtual class uvm_monitor extends uvm_component;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
  endclass
  virtual class uvm_scoreboard extends uvm_component;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
  endclass

  // ---------------------------------------------------------------- config_db
  // set(context, "inst", "field", value) stores a value for every component
  // whose full name matches context.inst; get() finds the latest match.
  class uvm_config_db #(type T = int);
    static string m_scope[$];
    static string m_field[$];
    static T      m_value[$];

    static function void set(uvm_component cntxt, string inst_name, string field_name, T value);
      string s = (cntxt == null) ? inst_name
               : (inst_name == "") ? cntxt.get_full_name()
               : {cntxt.get_full_name(), ".", inst_name};
      m_scope.push_back(s);
      m_field.push_back(field_name);
      m_value.push_back(value);
    endfunction

    static function bit get(uvm_component cntxt, string inst_name, string field_name, inout T value);
      string p = (cntxt == null) ? inst_name
               : (inst_name == "") ? cntxt.get_full_name()
               : {cntxt.get_full_name(), ".", inst_name};
      for (int i = m_scope.size() - 1; i >= 0; i--)
        if (m_field[i] == field_name && uvm_is_match(m_scope[i], p)) begin
          value = m_value[i];
          return 1;
        end
      return 0;
    endfunction
  endclass

  // ---------------------------------------------------------------- TLM: analysis
  // A one-way broadcast: write() returns at once, the producer never waits on
  // a subscriber, and it doesn't know how many there are (A3).
  virtual class uvm_analysis_if #(type T = int);
    pure virtual function void write(T t);
  endclass

  class uvm_analysis_port #(type T = int);
    string m_name;
    uvm_analysis_if #(T) m_subs[$];
    function new(string name);
      m_name = name;
    endfunction
    function void connect(uvm_analysis_if #(T) imp);
      m_subs.push_back(imp);
    endfunction
    function void write(T t);
      foreach (m_subs[i]) m_subs[i].write(t);
    endfunction
    function int size();
      return m_subs.size();
    endfunction
  endclass

  // the receiving end: forwards write() to the component that owns it
  class uvm_analysis_imp #(type T = int, type IMP = int) extends uvm_analysis_if #(T);
    IMP m_imp;
    function new(string name, IMP imp);
      m_imp = imp;
    endfunction
    virtual function void write(T t);
      m_imp.write(t);
    endfunction
  endclass

  // a component with one analysis_export and a write() to implement
  virtual class uvm_subscriber #(type T = int) extends uvm_component;
    uvm_analysis_imp #(T, uvm_subscriber #(T)) analysis_export;
    function new(string name, uvm_component parent);
      super.new(name, parent);
      analysis_export = new("analysis_export", this);
    endfunction
    pure virtual function void write(T t);
  endclass

  // ---------------------------------------------------------------- sequences
  class uvm_sequence_item extends uvm_object;
    event m_done;                          // item_done() fires it
    function new(string name = "");
      super.new(name);
    endfunction
  endclass

  // the register map talks to "a sequencer" without knowing its item type
  virtual class uvm_sequencer_base extends uvm_component;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    pure virtual task execute_item(uvm_sequence_item item);
  endclass

  class uvm_sequencer #(type REQ = uvm_sequence_item) extends uvm_sequencer_base;
    mailbox #(REQ) m_req_fifo;
    uvm_sequencer #(REQ) seq_item_export;  // what a driver's seq_item_port connects to

    function new(string name, uvm_component parent);
      super.new(name, parent);
      m_req_fifo = new();
      seq_item_export = this;
    endfunction

    // what finish_item does: queue the item -- first come, first served --
    // and return when the driver calls item_done()
    task send(REQ item);
      m_req_fifo.put(item);
      @(item.m_done);
    endtask

    virtual task execute_item(uvm_sequence_item item);
      REQ r;
      if (!$cast(r, item)) $fatal(1, "%s: wrong item type", get_full_name());
      send(r);
    endtask
  endclass

  class uvm_seq_item_pull_port #(type REQ = uvm_sequence_item);
    uvm_sequencer #(REQ) m_seqr;
    REQ m_cur;
    function void connect(uvm_sequencer #(REQ) seqr);
      m_seqr = seqr;
    endfunction
    task get_next_item(output REQ t);
      m_seqr.m_req_fifo.get(t);
      m_cur = t;
    endtask
    function void item_done();
      ->m_cur.m_done;
    endfunction
  endclass

  virtual class uvm_driver #(type REQ = uvm_sequence_item) extends uvm_component;
    uvm_seq_item_pull_port #(REQ) seq_item_port;
    function new(string name, uvm_component parent);
      super.new(name, parent);
      seq_item_port = new();
    endfunction
  endclass

  virtual class uvm_sequence #(type REQ = uvm_sequence_item) extends uvm_object;
    uvm_sequencer #(REQ) m_sequencer;
    function new(string name = "");
      super.new(name);
    endfunction
    task start(uvm_sequencer #(REQ) seqr);
      m_sequencer = seqr;
      body();
    endtask
    virtual task body(); endtask
    task start_item(REQ item); endtask     // FIFO arbitration: granted at once
    task finish_item(REQ item);
      m_sequencer.send(item);
    endtask
  endclass

  // ---------------------------------------------------------------- register model
  typedef bit [31:0] uvm_reg_data_t;
  typedef bit [31:0] uvm_reg_addr_t;
  typedef enum {UVM_IS_OK, UVM_NOT_OK} uvm_status_e;
  typedef enum {UVM_NO_CHECK, UVM_CHECK} uvm_check_e;
  typedef enum {UVM_READ, UVM_WRITE} uvm_access_e;

  typedef struct {
    uvm_access_e   kind;
    uvm_reg_addr_t addr;
    uvm_reg_data_t data;
    int            n_bits;
    bit [3:0]      byte_en;
    uvm_status_e   status;
  } uvm_reg_bus_op;

  int unsigned uvm_reg_checks = 0;          // mirror(UVM_CHECK) comparisons made

  typedef class uvm_reg;
  typedef class uvm_reg_map;

  // turns a register operation into a bus item, and the finished item back
  virtual class uvm_reg_adapter extends uvm_object;
    bit supports_byte_enable = 0;
    function new(string name = ""); super.new(name); endfunction
    pure virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
    pure virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
  endclass

  class uvm_reg_field extends uvm_object;
    uvm_reg        m_parent;
    int unsigned   m_lsb, m_size;
    string         m_access;               // "RW" or "RO"
    uvm_reg_data_t m_reset, m_mirrored, m_desired;

    function new(string name = ""); super.new(name); endfunction

    function void configure(uvm_reg parent, int unsigned size, int unsigned lsb_pos,
                            string access, uvm_reg_data_t reset);
      m_parent = parent; m_size = size; m_lsb = lsb_pos; m_access = access;
      m_reset = reset; m_mirrored = reset; m_desired = reset;
      parent.add_field(this);
    endfunction

    function uvm_reg_data_t mask();
      return ((64'd1 << m_size) - 1) << m_lsb;
    endfunction
    function uvm_reg_data_t get_mirrored_value(); return m_mirrored; endfunction
    function uvm_reg_data_t get(); return m_desired; endfunction
    function void set(uvm_reg_data_t value); m_desired = value & ((64'd1 << m_size) - 1); endfunction
    function string get_access(); return m_access; endfunction

    // the bytes this field lives in -- and is it alone in them?
    function bit [3:0] byte_lanes();
      bit [3:0] be = '0;
      for (int b = 0; b < 4; b++)
        if (mask() & (32'hFF << (8 * b))) be[b] = 1'b1;
      return be;
    endfunction
    extern function bit is_indv_accessible();

    // Write one field by name. If the field has its bytes to itself and the
    // adapter can do byte enables, this is a write of just those bytes, as in
    // UVM. Otherwise the whole register goes out, the other fields at their
    // desired values.
    extern task write(output uvm_status_e status, input uvm_reg_data_t value);
  endclass

  class uvm_reg extends uvm_object;
    uvm_reg_field  m_fields[$];
    uvm_reg_map    m_map;
    uvm_reg_addr_t m_offset;
    string         m_path;                 // "ral.ctrl", for messages

    function new(string name = ""); super.new(name); endfunction
    function void add_field(uvm_reg_field f); m_fields.push_back(f); endfunction
    function uvm_reg_addr_t get_address(); return m_map.m_base + m_offset; endfunction

    function uvm_reg_data_t get_mirrored_value();
      uvm_reg_data_t v = '0;
      foreach (m_fields[i]) v |= m_fields[i].m_mirrored << m_fields[i].m_lsb;
      return v;
    endfunction
    function uvm_reg_data_t get();
      uvm_reg_data_t v = '0;
      foreach (m_fields[i]) v |= m_fields[i].m_desired << m_fields[i].m_lsb;
      return v;
    endfunction
    function void set(uvm_reg_data_t value);
      foreach (m_fields[i]) m_fields[i].set(value >> m_fields[i].m_lsb);
    endfunction

    // auto-predict: the mirror follows what the bus did (only on OKAY).
    // A write moves only writable fields in the bytes that were enabled.
    function void predict(uvm_reg_data_t value, bit [3:0] byte_en, uvm_access_e kind);
      foreach (m_fields[i]) begin
        uvm_reg_field f = m_fields[i];
        if (kind == UVM_WRITE && (f.m_access == "RO" || (f.byte_lanes() & byte_en) == 0)) continue;
        f.m_mirrored = (value >> f.m_lsb) & ((64'd1 << f.m_size) - 1);
        f.m_desired  = f.m_mirrored;
      end
    endfunction

    extern task do_write(output uvm_status_e status, input uvm_reg_data_t value,
                         input bit [3:0] byte_en, input uvm_reg_field only = null);
    extern task write(output uvm_status_e status, input uvm_reg_data_t value);
    extern task read(output uvm_status_e status, output uvm_reg_data_t value);
    extern task mirror(output uvm_status_e status, input uvm_check_e check = UVM_NO_CHECK);
  endclass

  class uvm_reg_map extends uvm_object;
    uvm_reg_addr_t     m_base;
    uvm_reg            m_regs[$];
    uvm_sequencer_base m_sequencer;
    uvm_reg_adapter    m_adapter;
    bit                m_trace;            // +journey: print the register path once

    function new(string name = ""); super.new(name); endfunction
    function void add_reg(uvm_reg r, uvm_reg_addr_t offset);
      r.m_map = this; r.m_offset = offset; m_regs.push_back(r);
    endfunction

    // RAL drives through the same agent as everything else (C2)
    function void set_sequencer(uvm_sequencer_base sequencer, uvm_reg_adapter adapter);
      m_sequencer = sequencer; m_adapter = adapter;
    endfunction

    task do_bus(ref uvm_reg_bus_op rw);
      uvm_sequence_item item;
      if (m_sequencer == null || m_adapter == null)
        $fatal(1, "%s: set_sequencer() was never called", get_name());
      item = m_adapter.reg2bus(rw);
      m_sequencer.execute_item(item);      // a real bus transaction, through the driver
      m_adapter.bus2reg(item, rw);
    endtask
  endclass

  function bit uvm_reg_field::is_indv_accessible();
    foreach (m_parent.m_fields[i])
      if (m_parent.m_fields[i] != this && (m_parent.m_fields[i].byte_lanes() & byte_lanes()) != 0)
        return 0;
    return 1;
  endfunction

  task uvm_reg_field::write(output uvm_status_e status, input uvm_reg_data_t value);
    if (m_parent.m_map.m_adapter.supports_byte_enable && is_indv_accessible()) begin
      set(value);
      m_parent.do_write(status, (value << m_lsb) & mask(), byte_lanes(), this);
    end else begin
      set(value);
      m_parent.do_write(status, m_parent.get(), 4'hF);
    end
  endtask

  task uvm_reg::do_write(output uvm_status_e status, input uvm_reg_data_t value,
                         input bit [3:0] byte_en, input uvm_reg_field only = null);
    uvm_reg_bus_op rw;
    rw.kind = UVM_WRITE; rw.addr = get_address(); rw.data = value;
    rw.n_bits = 32; rw.byte_en = byte_en; rw.status = UVM_NOT_OK;
    if (m_map.m_trace) begin
      string fld = "";
      if (only != null) fld = {".", only.get_name()};
      uvm_report_info("RAL", $sformatf("%s%s is at 0x%04h: data 0x%08h, byte enables %b",
                      m_path, fld, rw.addr, value, byte_en), UVM_NONE);
    end
    m_map.do_bus(rw);
    status = rw.status;
    if (status == UVM_IS_OK) predict(value, byte_en, UVM_WRITE);
    if (m_map.m_trace) begin
      string said = "an error";
      if (status == UVM_IS_OK) said = "OKAY";
      uvm_report_info("RAL", $sformatf("%s: the bus said %s, mirror updated to 0x%08h", m_path,
                      said, get_mirrored_value()), UVM_NONE);
    end
  endtask

  task uvm_reg::write(output uvm_status_e status, input uvm_reg_data_t value);
    set(value);
    do_write(status, get(), 4'hF);
  endtask

  task uvm_reg::read(output uvm_status_e status, output uvm_reg_data_t value);
    uvm_reg_bus_op rw;
    rw.kind = UVM_READ; rw.addr = get_address(); rw.data = '0;
    rw.n_bits = 32; rw.byte_en = 4'hF; rw.status = UVM_NOT_OK;
    m_map.do_bus(rw);
    status = rw.status; value = rw.data;
    if (status == UVM_IS_OK) predict(value, 4'hF, UVM_READ);
  endtask

  // Read the register through the bus and, with UVM_CHECK, compare what came
  // back against what the model believes is there -- before updating it (B3).
  task uvm_reg::mirror(output uvm_status_e status, input uvm_check_e check = UVM_NO_CHECK);
    uvm_reg_data_t exp = get_mirrored_value(), got;
    read(status, got);
    if (check == UVM_CHECK) begin
      uvm_reg_checks++;
      if (status != UVM_IS_OK)
        uvm_report_error("RegModel", $sformatf("%s: read at 0x%04h returned an error response", m_path, get_address()));
      else if (got != exp) begin
        string why = "";
        foreach (m_fields[i]) begin
          uvm_reg_field f = m_fields[i];
          if (((got ^ exp) & f.mask()) != 0)
            why = {why, $sformatf(" %s is %0d, model says %0d;", f.get_name(),
                   (got & f.mask()) >> f.m_lsb, (exp & f.mask()) >> f.m_lsb)};
        end
        uvm_report_error("RegModel", $sformatf("%s read back 0x%08h, mirror says 0x%08h:%s",
                         m_path, got, exp, why.substr(0, why.len() - 2)));
      end
    end
  endtask

  virtual class uvm_reg_block extends uvm_object;
    uvm_reg m_regs[$];
    function new(string name = ""); super.new(name); endfunction
    pure virtual function void build();
    // read every register back and check it against the mirror
    task mirror(output uvm_status_e status, input uvm_check_e check = UVM_NO_CHECK);
      uvm_status_e s;
      status = UVM_IS_OK;
      foreach (m_regs[i]) begin
        m_regs[i].mirror(s, check);
        if (s != UVM_IS_OK) status = s;
      end
    endtask
  endclass

  // ---------------------------------------------------------------- run_test
  function automatic void m_all(uvm_component c, ref uvm_component all[$]);
    all.push_back(c);
    foreach (c.m_children[i]) m_all(c.m_children[i], all);
  endfunction

  function automatic void m_build(uvm_component c, uvm_phase ph);
    c.build_phase(ph);                     // top-down: the parent creates its children...
    foreach (c.m_children[i]) m_build(c.m_children[i], ph);   // ...then they build
  endfunction

  function automatic void m_connect(uvm_component c, uvm_phase ph);
    foreach (c.m_children[i]) m_connect(c.m_children[i], ph);
    c.connect_phase(ph);
  endfunction

  // build, connect, run until the last objection drops, check, report
  task automatic run_test(uvm_component top);
    uvm_phase ph;
    uvm_component all[$];
    ph = new("build");   m_build(top, ph);
    ph = new("connect"); m_connect(top, ph);
    m_all(top, all);
    ph = new("run");
    foreach (all[i]) begin
      automatic uvm_component c = all[i];
      automatic uvm_phase p = ph;
      fork
        c.run_phase(p);
      join_none
    end
    do @(uvm_tick);
    while (!(uvm_objection_raised && uvm_objections == 0) && !uvm_stop_request);
    ph = new("check");
    for (int i = all.size() - 1; i >= 0; i--) all[i].check_phase(ph);
    ph = new("report");
    for (int i = all.size() - 1; i >= 0; i--) all[i].report_phase(ph);
  endtask

endpackage
