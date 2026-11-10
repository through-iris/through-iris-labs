// axi_env -- where it all comes together (C1, C2). The env builds the
// components and connects them. It knows which components exist and that
// they need connecting; AXI timing and register addresses live inside the
// pieces.
class axi_env extends uvm_env;
  `uvm_component_utils(axi_env)

  axi_agent       agt;
  axi_scoreboard  sb;
  axi_coverage    cov;
  axi_reg_block   ral;
  axi_reg_adapter adapter;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // C1: every component through the factory -- create, never new -- so a
  // test can override any one of them without editing this file
  function void build_phase(uvm_phase phase);
    agt = axi_agent     ::type_id::create("agt", this);
    sb  = axi_scoreboard::type_id::create("sb",  this);
    cov = axi_coverage  ::type_id::create("cov", this);
    ral = axi_reg_block ::type_id::create("ral", this);
    ral.build();
    adapter = axi_reg_adapter::type_id::create("adapter", this);
    uvm_config_db #(axi_reg_block)::set(null, "*", "ral", ral);   // for the sequences
  endfunction

  // C2: the VIP in a few lines
  function void connect_phase(uvm_phase phase);
    // one monitor feeds both consumers:
    agt.mon.ap.connect(sb.analysis_export);
    agt.mon.ap.connect(cov.analysis_export);

    // RAL drives through the same agent:
    ral.map.set_sequencer(agt.seqr, adapter);
  endfunction
endclass
