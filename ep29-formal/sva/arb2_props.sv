// arb2_props -- ep29's formal testbench (C1), bound to the arbiter.
//
// What the episode shows on screen is full SVA:
//     m_valid && !m_ready |=> m_valid && $stable(m_data)
// The free flow (Yosys + the yosys-slang front end in the OSS CAD Suite) accepts
// concurrent properties with a clock and `disable iff`, but not sequence
// operators: no |=>, no |->, no ##. So each rule is written as the same check in
// one cycle: "stalled LAST cycle" is $past(...), and `a -> b` is the boolean
// implication. For a property with a one-cycle antecedent this is exactly
// equivalent:   a |=> b   ==   $past(a) -> b   (checked from the 2nd cycle on).
// `&& !rst` inside $past keeps the reset cycle out, as `disable iff` would.
//
//   +define+NO_INPUT_ASSUME   Break 1: drop the environment assumptions
//   +define+OVER_CONSTRAIN    Break 2: add the assumption that says too much
module arb2_props (
  input logic       clk, rst,
  input logic       s0_valid, s0_ready, s1_valid, s1_ready,
  input logic [7:0] s0_data, s1_data,
  input logic       m_valid, m_ready,
  input logic [7:0] m_data
);
  // formal starts from reset: high in the first cycle, low ever after
  // (on screen: `initial assume (rst);` -- yosys-slang can't read a net in `initial`)
  logic started = 1'b0;
  always_ff @(posedge clk) started <= 1'b1;
  always_comb assume (rst == !started);

`ifndef NO_INPUT_ASSUME
  // the environment: each master keeps the VALID rule (ep01)
  am_s0: assume property (@(posedge clk) disable iff (rst)
           $past(s0_valid && !s0_ready && !rst) -> s0_valid && $stable(s0_data));
  am_s1: assume property (@(posedge clk) disable iff (rst)
           $past(s1_valid && !s1_ready && !rst) -> s1_valid && $stable(s1_data));
`endif

`ifdef OVER_CONSTRAIN
  // Break 2: "the masters never request in the same cycle" -- not a promise
  // any real environment makes. It deletes the world the grant bug lives in.
  am_never_both: assume property (@(posedge clk) !(s0_valid && s1_valid));
`endif

  // the guarantee: the same rule on the arbiter's output
  as_m:   assert property (@(posedge clk) disable iff (rst)
            $past(m_valid && !m_ready && !rst) -> m_valid && $stable(m_data));
  as_one: assert property (@(posedge clk) !(s0_ready && s1_ready));

  // covers: is the interesting world still in?
  co_both:  cover property (@(posedge clk) disable iff (rst) s0_valid && s1_valid);
  co_stall: cover property (@(posedge clk) disable iff (rst) m_valid && !m_ready && s1_valid);
  co_flip:  cover property (@(posedge clk) disable iff (rst) $past(s0_ready && !rst) && s1_ready);
endmodule

bind arb2 arb2_props u_props (.*);            // the RTL is never edited
