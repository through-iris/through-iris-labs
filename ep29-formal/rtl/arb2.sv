// arb2 -- two masters share one valid/ready stream port (ep29's running example).
//
// The owner's valid/data go straight through to the output, and its ready comes
// straight back. That pass-through is why the arbiter's output can only keep the
// VALID rule if its inputs keep it too (Break 1), and why the owner must not
// change while the output is stalled (the cold open's bug).
//
// Round robin: the owner hands over when the other master is waiting and the
// current offer is not stalled -- i.e. it was accepted, or there wasn't one.
module arb2 (
  input  logic       clk, rst,
  input  logic       s0_valid, input logic [7:0] s0_data, output logic s0_ready,
  input  logic       s1_valid, input logic [7:0] s1_data, output logic s1_ready,
  output logic       m_valid,  output logic [7:0] m_data,  input  logic m_ready
);
  logic owner;                                   // 0 = master 0, 1 = master 1

  assign m_valid  = owner ? s1_valid : s0_valid;
  assign m_data   = owner ? s1_data  : s0_data;
  assign s0_ready = !owner && m_ready;
  assign s1_ready =  owner && m_ready;

  wire other_valid = owner ? s0_valid : s1_valid;
  wire stalled     = m_valid && !m_ready;

  always_ff @(posedge clk)
    if (rst)                              owner <= 1'b0;
    else if (other_valid && !stalled)     owner <= !owner;   // hold the grant during a stall
endmodule
