// skid_props -- the final lab's formal testbench, bound to the skid buffer.
// Same shape as arb2_props: reset first, the VALID rule assumed on the input and
// asserted on the output, covers for the states that matter -- plus one property
// the arbiter didn't need: nothing gets lost. A reference counter tracks words
// accepted minus words delivered, and it must equal the words the buffer holds.
// (A scoreboard, written as a property. ep10 does it in simulation.)
module skid_props (
  input logic       clk, rst,
  input logic       s_valid, s_ready, m_valid, m_ready, sk_valid,
  input logic [7:0] s_data, m_data
);
  logic started = 1'b0;
  always_ff @(posedge clk) started <= 1'b1;
  always_comb assume (rst == !started);

  am_s: assume property (@(posedge clk) disable iff (rst)
          $past(s_valid && !s_ready && !rst) -> s_valid && $stable(s_data));

  as_m: assert property (@(posedge clk) disable iff (rst)
          $past(m_valid && !m_ready && !rst) -> m_valid && $stable(m_data));

  logic [1:0] held;                              // words accepted - words delivered
  always_ff @(posedge clk)
    if (rst) held <= '0;
    else     held <= held + 2'(s_valid && s_ready) - 2'(m_valid && m_ready);

  as_count: assert property (@(posedge clk) disable iff (rst)
              held == 2'(m_valid) + 2'(sk_valid));

  co_parked:  cover property (@(posedge clk) disable iff (rst) sk_valid);
  co_drain:   cover property (@(posedge clk) disable iff (rst) sk_valid && m_ready && s_valid);
endmodule

bind skid skid_props u_props (.*);
