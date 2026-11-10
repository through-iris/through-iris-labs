// fifo_props -- the Break 3 checks, bound to the FIFO.
//
// as_not_empty is ep29's assertion: a cycle that pushed and did not pop is
// followed by a non-empty FIFO. On screen it is `push && !pop |=> !empty`;
// here it is the same check in one cycle (see sva/arb2_props.sv for why).
//
// co_full is guard 1 from the episode: cover the deepest state you rely on, and
// make the bound reach it. It counts words with its own 8-bit reference counter,
// so it means "64 words are inside" even when the design's own counter is the
// thing that is broken.
module fifo_props #(parameter int DEPTH = 64) (
  input logic clk, rst,
  input logic s_valid, s_ready, m_valid, m_ready
);
  logic started = 1'b0;                        // reset in the first cycle only
  always_ff @(posedge clk) started <= 1'b1;
  always_comb assume (rst == !started);

  wire push = s_valid && s_ready;
  wire pop  = m_valid && m_ready;

  as_not_empty: assert property (@(posedge clk) disable iff (rst)
                  $past(push && !pop && !rst) -> m_valid);

  logic [7:0] words;                           // reference occupancy
  always_ff @(posedge clk)
    if (rst) words <= '0;
    else     words <= words + 8'(push) - 8'(pop);

  co_full: cover property (@(posedge clk) disable iff (rst) words == DEPTH);
endmodule

bind fifo fifo_props #(.DEPTH(DEPTH)) u_props (.*);
