// axi_scoreboard -- a reference model predicts the right response for each
// access, and a checker compares it to what the monitor saw (A2, B2, ep10).
//
// The model is the slave's spec, written a second time: its own copy of the
// registers and the memory, updated only from writes it has checked. It
// predicts the response of every transaction (OKAY, SLVERR, DECERR) and the
// data of every read beat. It never looks at the register model: RAL is what
// the test believes, the scoreboard is what the bus did.
class axi_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(axi_scoreboard)

  uvm_analysis_imp #(axi_seq_item, axi_scoreboard) analysis_export;

  localparam bit [31:0] ID_VALUE = 32'h4158_4931, STATUS_VALUE = 32'h0000_0001;
  localparam bit [31:0] CTRL_MASK = 32'h0000_0301, BASE_MASK = 32'h0000_F000;

  bit [31:0] ctrl = 32'h0, base = 32'h0000_1000;   // reset values, from the spec
  bit [31:0] mem [256];                             // zero after reset
  int unsigned n_compared, n_mismatch;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    analysis_export = new("analysis_export", this);
  endfunction

  function axi_resp_e predict_resp(bit [15:0] a, axi_kind_e kind);
    if (a[15:8] == 8'h00)
      case (a[7:0])
        8'h00, 8'h0C: return kind == AXI_WRITE ? AXI_SLVERR : AXI_OKAY;
        8'h04, 8'h08: return AXI_OKAY;
        default:      return AXI_DECERR;
      endcase
    if (a[15:10] == {base[15:12], 2'b00}) return ctrl[0] ? AXI_OKAY : AXI_SLVERR;
    return AXI_DECERR;
  endfunction

  function bit [31:0] predict_word(bit [15:0] a);
    if (a[15:8] == 8'h00)
      case (a[7:0])
        8'h00:   return ID_VALUE;
        8'h04:   return ctrl;
        8'h08:   return base;
        8'h0C:   return STATUS_VALUE;
        default: return '0;
      endcase
    return mem[a[9:2]];
  endfunction

  function bit [31:0] merge(bit [31:0] old, bit [31:0] d, bit [3:0] s);
    for (int b = 0; b < 4; b++) if (s[b]) old[8*b +: 8] = d[8*b +: 8];
    return old;
  endfunction

  function void mismatch(string msg);
    n_mismatch++;
    `uvm_error("SB", msg)
  endfunction

  // every transaction the monitor broadcasts arrives here
  function void write(axi_seq_item t);
    axi_resp_e exp = predict_resp(t.addr, t.kind);
    bit ok = 1;
    n_compared++;
    if (t.data.size() != t.len + 1) begin
      mismatch($sformatf("%s: %0d beats seen, AxLEN says %0d", t.convert2string(), t.data.size(), t.len + 1));
      return;
    end
    if (t.kind == AXI_WRITE) begin
      if (t.resp != exp) begin
        mismatch($sformatf("%s: BRESP %s, the model expected %s", t.convert2string(), axi_resp_name(t.resp), axi_resp_name(exp)));
        ok = 0;
      end else if (exp == AXI_OKAY)
        for (int i = 0; i <= t.len; i++) begin   // the model takes the write, byte by byte
          bit [15:0] a = t.addr + 16'(4 * i);
          if (a[15:8] == 8'h00) begin
            if (a[7:0] == 8'h04) ctrl = merge(ctrl, t.data[i], t.strb[i]) & CTRL_MASK;
            if (a[7:0] == 8'h08) base = merge(base, t.data[i], t.strb[i]) & BASE_MASK;
          end else
            mem[a[9:2]] = merge(mem[a[9:2]], t.data[i], t.strb[i]);
        end
    end else
      for (int i = 0; i <= t.len; i++) begin
        bit [15:0] a = t.addr + 16'(4 * i);
        if (t.rresp[i] != exp) begin
          mismatch($sformatf("read 0x%04h beat %0d: RRESP %s, the model expected %s", t.addr, i + 1,
                             axi_resp_name(t.rresp[i]), axi_resp_name(exp)));
          ok = 0;
          break;
        end
        if (exp == AXI_OKAY && t.data[i] != predict_word(a)) begin
          mismatch($sformatf("read 0x%04h beat %0d: RDATA 0x%08h, the model expected 0x%08h", t.addr, i + 1,
                             t.data[i], predict_word(a)));
          ok = 0;
          break;
        end
      end
    if (t.trace)
      `uvm_info("scoreboard", axi_pick(ok, $sformatf("%s, as the reference model predicted: pass",
                                     axi_resp_name(exp)), "mismatch flagged"), UVM_NONE)
  endfunction
endclass
