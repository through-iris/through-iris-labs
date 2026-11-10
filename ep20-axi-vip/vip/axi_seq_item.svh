// axi_seq_item -- one AXI transaction: "an address, data, a burst" (B1).
//
// The sequence randomizes the request half. The driver fills in the response
// half on the same object once the slave answers; the monitor builds its own
// copy from the pins. Constraints keep each burst inside one region of the
// slave (registers, the memory window, or unmapped space) and inside 1 KB,
// so it never crosses the 4 KB line either (ep02). Half the unmapped
// accesses aim just past the end of the window.
typedef enum bit {AXI_READ = 1'b0, AXI_WRITE = 1'b1} axi_kind_e;
typedef enum bit [1:0] {AXI_OKAY = 2'b00, AXI_EXOKAY = 2'b01, AXI_SLVERR = 2'b10, AXI_DECERR = 2'b11} axi_resp_e;
typedef enum bit [1:0] {AXI_MEM = 2'd0, AXI_REG = 2'd1, AXI_NONE = 2'd2} axi_region_e;

function automatic string axi_resp_name(axi_resp_e r);
  case (r)
    AXI_OKAY:   return "OKAY";
    AXI_EXOKAY: return "EXOKAY";
    AXI_SLVERR: return "SLVERR";
    default:    return "DECERR";
  endcase
endfunction

// pick a string (a ?: on two string literals pads the shorter one in some tools)
function automatic string axi_pick(bit c, string a, string b);
  if (c) return a;
  return b;
endfunction

class axi_seq_item extends uvm_sequence_item;
  `uvm_object_utils(axi_seq_item)

  // ---- the request
  rand axi_kind_e   kind;
  rand axi_region_e region;
  rand bit [15:0]   addr;
  rand bit [3:0]    id;
  rand bit [7:0]    len;              // AxLEN: beats - 1
  rand bit          near_window;      // unmapped, but in the window's own 4 KB page
  bit [31:0]        data[$];          // WDATA per beat; RDATA once a read is done
  bit [3:0]         strb[$];          // WSTRB per beat
  // ---- the response
  axi_resp_e        resp;             // BRESP, or the first RRESP
  axi_resp_e        rresp[$];         // RRESP per beat
  // ---- context
  bit [15:0]        win_base = 16'h1000;   // where the memory window is now
  bit               trace;            // +journey: print this one's trip

  constraint c_burst {
    addr[1:0] == 2'b00;
    len < 8;
    {6'd0, addr[9:0]} + 16'(4 * len) < 16'd1024;     // stays inside 1 KB
  }
  constraint c_region {
    region dist {AXI_MEM := 80, AXI_REG := 8, AXI_NONE := 12};
    region == AXI_MEM  -> addr[15:10] == win_base[15:10];
    region == AXI_REG  -> (addr == 16'h0000 || addr == 16'h000C) && len == 0;   // ID, STATUS
    region == AXI_NONE -> addr[15:8] != 8'h00 && addr[15:10] != win_base[15:10];
    // half the unmapped accesses land just past the window's 1 KB, where a
    // decode that is a bit too wide would answer instead of DECERR
    near_window dist {1'b1 := 1, 1'b0 := 1};
    region == AXI_NONE && near_window -> addr[15:12] == win_base[15:12];
  }

  function new(string name = "axi_seq_item");
    super.new(name);
  endfunction

  // data and strobes: random, three beats in four with every strobe on
  function void post_randomize();
    data.delete(); strb.delete();
    for (int i = 0; i <= len; i++) begin
      data.push_back($urandom);
      strb.push_back($urandom_range(0, 3) == 0 ? 4'($urandom_range(1, 14)) : 4'hF);
    end
  endfunction

  function string convert2string();
    string s = $sformatf("%s 0x%04h, %0d beat%s", axi_pick(kind == AXI_WRITE, "write", "read"),
                         addr, len + 1, axi_pick(len == 0, "", "s"));
    if (kind == AXI_WRITE) begin
      s = {s, ", WSTRB"};
      foreach (strb[i]) s = {s, $sformatf(" %h", strb[i])};
    end
    return s;
  endfunction
endclass

// the test's settings, carried down by uvm_config_db (A3: "the glue")
class axi_cfg extends uvm_object;
  `uvm_object_utils(axi_cfg)
  rand bit [3:0]   base_page;         // "set the slave's base address" -> BASE
  rand bit [1:0]   mode;              // "enable a mode" -> CTRL.MODE
  rand int unsigned max_gap;          // idle cycles the driver may put before a VALID
  int unsigned     n_txns = 300;

  constraint c_cfg {
    base_page inside {[1:15]};
    mode inside {[1:3]};
    max_gap inside {[0:3]};
  }

  function new(string name = "axi_cfg");
    super.new(name);
  endfunction
endclass
