// axi_test -- the test at the top (C3). Short, because the env did the hard
// part: put the settings in uvm_config_db, build the env, and in the run
// phase start one virtual sequence under an objection.
//
// Then read two numbers (B4, C3): did anything mismatch, and did you cover
// what you meant to. check_phase adds the count that makes the first number
// mean something: the scoreboard must have compared every transaction the
// monitor broadcast (ep10: "zero mismatches, also zero transactions").
class axi_test extends uvm_test;
  `uvm_component_utils(axi_test)

  axi_env        env;
  axi_cfg        cfg;
  virtual axi_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    int unsigned n;
    if (!uvm_config_db #(virtual axi_if)::get(this, "", "vif", vif))   // from tb_top
      `uvm_fatal("NOVIF", "tb_top did not set the virtual interface")
    cfg = axi_cfg::type_id::create("cfg");
    if (!cfg.randomize()) `uvm_fatal("CFG", "axi_cfg randomize() failed")
    if ($value$plusargs("txns=%d", n)) cfg.n_txns = n;
    uvm_config_db #(virtual axi_if)::set(this, "*", "vif", vif);
    uvm_config_db #(axi_cfg)::set(this, "*", "cfg", cfg);
    env = axi_env::type_id::create("env", this);
    $display("[cfg] %s, seed %0d: BASE page %0d (window 0x%04h), MODE %0d, driver gaps up to %0d, %0d transactions",
             get_type_name(), axi_seed, cfg.base_page, 16'(cfg.base_page) << 12, cfg.mode, cfg.max_gap, cfg.n_txns);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    axi_vseq::type_id::create("vs").start(env.agt.seqr);
    phase.drop_objection(this);
  endtask

  function void check_phase(uvm_phase phase);
    int unsigned seen = env.agt.mon.n_sent;
    if (seen == 0)
      `uvm_error("test", "the monitor broadcast nothing")
    if (env.sb.n_compared != seen)
      `uvm_error("test", $sformatf("scoreboard compared %0d of the %0d transactions the monitor broadcast",
                                   env.sb.n_compared, seen))
    if (env.cov.n_sampled != seen)
      `uvm_error("test", $sformatf("coverage sampled %0d of the %0d transactions the monitor broadcast",
                                   env.cov.n_sampled, seen))
    if (env.cov.get_coverage() < 100.0)
      `uvm_error("test", $sformatf("coverage %0.1f%%: a bin the test meant to hit was never hit", env.cov.get_coverage()))
  endfunction

  // the two numbers, and the counts beside them
  function void report_phase(uvm_phase phase);
    $display("[report] %0d mismatches, %0.1f%% covered | scoreboard compared %0d of %0d | RAL checks %0d, %0d wrong | protocol violations %0d",
             env.sb.n_mismatch, env.cov.get_coverage(), env.sb.n_compared, env.agt.mon.n_sent,
             uvm_reg_checks, uvm_count("RegModel"), uvm_count("axi_sva"));
    if (uvm_errors == 0) $display("PASS %s", get_type_name());
    else                 $display("FAIL %s (%0d errors)", get_type_name(), uvm_errors);
  endfunction
endclass

// ---- the three breaks. Each one is the same test with ONE component swapped
// through the factory (C1) -- the env file is never edited.

// Break 1 (A3, C2): an env whose connect_phase subscribes coverage only
class axi_test_no_sb extends axi_test;
  `uvm_component_utils(axi_test_no_sb)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    axi_env::type_id::set_type_override(axi_env_no_sb::get_type());
    super.build_phase(phase);
  endfunction
endclass

// Break 2 (B3, C2): a register adapter that drops the byte enables
class axi_test_no_strb extends axi_test;
  `uvm_component_utils(axi_test_no_strb)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    axi_reg_adapter::type_id::set_type_override(axi_reg_adapter_no_strb::get_type());
    super.build_phase(phase);
  endfunction
endclass

// Break 3 (B1, B2): a driver that backs off while the slave is busy
class axi_test_backoff extends axi_test;
  `uvm_component_utils(axi_test_backoff)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    axi_driver::type_id::set_type_override(axi_driver_backoff::get_type());
    super.build_phase(phase);
  endfunction
endclass

// what UVM's run_test() does with +UVM_TESTNAME
function automatic uvm_component axi_create_test(string name);
  case (name)
    "axi_test":         return axi_test        ::type_id::create("uvm_test_top", null);
    "axi_test_no_sb":   return axi_test_no_sb  ::type_id::create("uvm_test_top", null);
    "axi_test_no_strb": return axi_test_no_strb::type_id::create("uvm_test_top", null);
    "axi_test_backoff": return axi_test_backoff::type_id::create("uvm_test_top", null);
    default:            return null;
  endcase
endfunction
