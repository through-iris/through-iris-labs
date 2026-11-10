// Break 1 (A3, C2) -- the env with one line missing from connect_phase.
//
// Coverage was added later, by copying the scoreboard's connect line and
// changing the name. The original line went with it. Every transaction still
// reaches the coverage collector, so coverage climbs to 100%. The scoreboard
// gets nothing, and a scoreboard that gets nothing reports zero mismatches.
// Two green numbers, and nothing was checked.
//
// Caught by axi_test's check_phase: the scoreboard must have compared every
// transaction the monitor broadcast.
class axi_env_no_sb extends axi_env;
  `uvm_component_utils(axi_env_no_sb)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void connect_phase(uvm_phase phase);
    // one monitor feeds both consumers:
    agt.mon.ap.connect(cov.analysis_export);

    // RAL drives through the same agent:
    ral.map.set_sequencer(agt.seqr, adapter);
  endfunction
endclass
