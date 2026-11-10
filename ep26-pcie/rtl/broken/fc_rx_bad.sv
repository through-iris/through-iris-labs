// fc_rx_bad -- Break 2, the receiver from the cold open. It is fc_rx.sv with
// one line changed.
//
// fc_rx -- the receive side of posted-write flow control (ep26, 5:05 "Break 2").
//
// It advertises PH posted-header credits and PD posted-data credits (one data
// credit = 16 bytes). Every MWr that arrives occupies one header credit and
// ceil(bytes / 16) data credits until it leaves the receive buffer. Then the
// receiver returns them to the sender (an UpdateFC, here a credit-return
// strobe). A write that hits a BAR lands in memory. A write that misses every
// BAR is discarded as an Unsupported Request -- and its credits go back too.
//
// The buffer drains a fixed RTT cycles after a write arrives, so a credit
// used on cycle t is usable again on cycle t + 4 (the episode's model).
module fc_rx_bad #(parameter int PH = 8, PD = 64, RTT = 4) (
  input  logic        clk, rst_n,
  input  logic        mwr_valid,              // the sender only sends with credit
  input  logic [31:0] mwr_addr,
  input  logic [4:0]  mwr_len_dw,             // 1..16
  input  logic [31:0] mwr_data,               // first DW, for the memory check
  output logic        ret_valid,              // UpdateFC: give back credits
  output logic [2:0]  ret_pd,                 //   one header + ret_pd data credits
  output logic        ur,                     // a write was discarded as UR
  output logic        hit_valid,
  output logic [31:0] hit_addr, hit_data
);
  // BAR0: 64 KB at 0x1000_0000, BAR2: 1 MB at 0x2000_0000
  function automatic logic bar_hit(input logic [31:0] a);
    bar_hit = (a[31:16] == 16'h1000) || (a[31:20] == 12'h200);
  endfunction

  // the receive buffer, as a delay line of RTT - 1 stages
  logic        v   [RTT-1];
  logic [31:0] a   [RTT-1], d [RTT-1];
  logic [4:0]  len [RTT-1];

  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) for (int i = 0; i < RTT - 1; i++) v[i] <= 1'b0;
    else begin
      v[0] <= mwr_valid; a[0] <= mwr_addr; d[0] <= mwr_data; len[0] <= mwr_len_dw;
      for (int i = 1; i < RTT - 1; i++) begin
        v[i] <= v[i-1]; a[i] <= a[i-1]; d[i] <= d[i-1]; len[i] <= len[i-1];
      end
    end

  // the head of the buffer drains this cycle
  wire        out_v = v[RTT-2];
  wire [31:0] out_a = a[RTT-2];
  wire        hit   = out_v && bar_hit(out_a);

  assign hit_valid = hit;
  assign hit_addr  = out_a;
  assign hit_data  = d[RTT-2];
  assign ur        = out_v && !hit;
  assign ret_valid = hit;                     // a discarded write has nothing left to drain
  assign ret_pd    = (len[RTT-2] + 3) >> 2;
endmodule
