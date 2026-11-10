// completer -- answers memory reads with completions, split the way PCIe
// allows (ep26, 3:30 "One read, three completions").
//
// Rules it follows, and the testbench checks:
//   - no completion carries more than Max_Payload_Size (mps) bytes
//   - every completion except the last ends on a Read Completion Boundary
//     (rcb), naturally aligned
//   - completions for one request go out in address order; completions for
//     different tags may interleave (here: round-robin over pending reads)
//   - Byte Count = bytes still owed, this completion's included
//   - Lower Address = low 7 bits of the address of its first byte
//
// The split point is the next MPS-aligned address, like many completers.
// `cut` (from the testbench) shortens a completion to `cut` RCB blocks, so
// the regression also sees smaller legal splits. Reads are full DWs (all byte
// enables set); memory is a pattern of the address, so data is checkable.
module completer #(parameter int SLOTS = 4) (
  input  logic        clk, rst_n,
  input  logic [12:0] mps, rcb,               // bytes; mps a multiple of rcb
  // read requests
  input  logic        req_valid,
  output logic        req_ready,
  input  logic [7:0]  req_tag,
  input  logic [31:0] req_addr,               // DW aligned
  input  logic [10:0] req_len_dw,             // 1..1024
  // completions (CplD)
  output logic        cpl_valid,
  input  logic        cpl_ready,
  input  logic [3:0]  cut,                    // 0: as large as mps allows
  output logic [7:0]  cpl_tag,
  output logic [10:0] cpl_len_dw,
  output logic [12:0] cpl_byte_count,
  output logic [6:0]  cpl_lower_addr,
  output logic [31:0] cpl_first_dw, cpl_last_dw
);
  function automatic logic [31:0] mem(input logic [31:0] a);
    mem = {a[15:0], ~a[15:0]} ^ 32'h5EED_0026;
  endfunction

  logic        busy [SLOTS];
  logic [7:0]  tag  [SLOTS];
  logic [31:0] nxt  [SLOTS];                  // next byte address owed
  logic [31:0] fin  [SLOTS];                  // end address (exclusive)
  int          rr;

  always_comb begin
    req_ready = 1'b0;
    for (int i = 0; i < SLOTS; i++) if (!busy[i]) req_ready = 1'b1;
  end

  // choose the slot to answer next, and where this completion ends
  int          pick;
  logic [31:0] stop, a0, lim;
  always_comb begin
    pick = -1;
    for (int k = 0; k < SLOTS; k++)
      if (pick < 0 && busy[(rr + k) % SLOTS]) pick = (rr + k) % SLOTS;
    a0 = (pick >= 0) ? nxt[pick] : 32'd0;
    stop = (pick >= 0) ? fin[pick] : 32'd0;
    lim = (a0 / mps + 1) * mps;                       // next MPS-aligned point
    if (cut != 0 && (a0 / rcb + cut) * rcb < lim) lim = (a0 / rcb + cut) * rcb;
    if (lim < stop) stop = lim;
  end

  assign cpl_valid      = (pick >= 0);
  assign cpl_tag        = (pick >= 0) ? tag[pick] : 8'd0;
  assign cpl_len_dw     = (stop - a0) >> 2;
  assign cpl_byte_count = (pick >= 0) ? fin[pick] - a0 : 13'd0;
  assign cpl_lower_addr = a0[6:0];
  assign cpl_first_dw   = mem(a0);
  assign cpl_last_dw    = mem(stop - 4);

  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) begin
      rr <= 0;
      for (int i = 0; i < SLOTS; i++) busy[i] <= 1'b0;
    end else begin
      if (cpl_valid && cpl_ready) begin
        nxt[pick] <= stop;
        if (stop == fin[pick]) busy[pick] <= 1'b0;
        rr <= (pick + 1) % SLOTS;
      end
      if (req_valid && req_ready) begin : take
        int f;
        f = -1;
        for (int i = 0; i < SLOTS; i++) if (f < 0 && !busy[i]) f = i;
        busy[f] <= 1'b1;
        tag[f]  <= req_tag;
        nxt[f]  <= req_addr;
        fin[f]  <= req_addr + {req_len_dw, 2'b00};
      end
    end
endmodule
