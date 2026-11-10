// axi_coverage -- the coverage collector (A2, B2, ep11): a covergroup sampled
// with every transaction the monitor broadcasts. It records what happened on
// the bus, not what the sequences asked for.
//
// The claim it makes: reads and writes, of one beat, a short burst and a
// long one, each answered OKAY, SLVERR and DECERR, with full and partial
// strobes. Twenty-two bins, and a run passes only at 100%.
class axi_coverage extends uvm_subscriber #(axi_seq_item);
  `uvm_component_utils(axi_coverage)

  axi_seq_item t;
  bit          partial;                // a write with any strobe not 4'hF
  int unsigned n_sampled;

  covergroup cg;
    cp_kind: coverpoint t.kind {
      bins read  = {AXI_READ};
      bins write = {AXI_WRITE};
    }
    cp_len: coverpoint t.len {
      bins single = {0};
      bins short_ = {[1:3]};           // 2-4 beats
      bins long_  = {[4:7]};           // 5-8 beats
    }
    cp_resp: coverpoint t.resp {
      bins okay   = {AXI_OKAY};
      bins slverr = {AXI_SLVERR};
      bins decerr = {AXI_DECERR};
    }
    cp_strb: coverpoint partial iff (t.kind == AXI_WRITE) {
      bins full    = {0};
      bins partial = {1};
    }
    kind_x_len:  cross cp_kind, cp_len;
    kind_x_resp: cross cp_kind, cp_resp;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg = new();
  endfunction

  function void write(axi_seq_item tr);
    t = tr;
    partial = 0;
    foreach (tr.strb[i]) if (tr.strb[i] != 4'hF) partial = 1;
    n_sampled++;
    cg.sample();
    if (tr.trace)
      `uvm_info("coverage", $sformatf("sampled: %s, %0d beat%s, %s%s -- coverage now %0.1f%%",
                axi_pick(tr.kind == AXI_WRITE, "write", "read"), tr.len + 1, axi_pick(tr.len == 0, "", "s"),
                axi_resp_name(tr.resp),
                axi_pick(tr.kind == AXI_WRITE, axi_pick(partial, ", partial strobes", ", full strobes"), ""),
                cg.get_coverage()), UVM_NONE)
  endfunction

  function real get_coverage();
    return cg.get_coverage();
  endfunction
endclass
