// arb2, as it was before the fix -- the cold open's arbiter.
//
// Identical to rtl/arb2.sv except for one line: the owner flips whenever the
// other master is waiting, stall or not. Mid-stall, the output's valid/data
// switch to the other master: the AXI VALID rule breaks on the arbiter's output.
// Formal finds it in 3 cycles: reset, both request while the slave stalls, flip.
module arb2 (
  input  logic       clk, rst,
  input  logic       s0_valid, input logic [7:0] s0_data, output logic s0_ready,
  input  logic       s1_valid, input logic [7:0] s1_data, output logic s1_ready,
  output logic       m_valid,  output logic [7:0] m_data,  input  logic m_ready
);
  logic owner;

  assign m_valid  = owner ? s1_valid : s0_valid;
  assign m_data   = owner ? s1_data  : s0_data;
  assign s0_ready = !owner && m_ready;
  assign s1_ready =  owner && m_ready;

  wire other_valid = owner ? s0_valid : s1_valid;

  always_ff @(posedge clk)
    if (rst)                owner <= 1'b0;
    else if (other_valid)   owner <= !owner;   // BUG: flips even while the output is stalled
endmodule
