// fifo -- a DEPTH-entry stream FIFO with valid/ready on both sides (Break 3).
//
// CW is the width of the occupancy counter. It must count 0..DEPTH, which takes
// $clog2(DEPTH)+1 bits: 7 for 64 entries. The break sets CW to $clog2(DEPTH),
// one bit short -- the classic off-by-one. Then the 64th word wraps count to 0,
// `full` can never be true (a 6-bit count is never 64), and a full FIFO says it
// is empty. The shortest path to that is 64 pushes straight after reset, so the
// first failure is on cycle 65: a bounded proof to depth 20 cannot see it.
module fifo #(
  parameter int DEPTH = 64,
  parameter int AW    = $clog2(DEPTH),       // pointer width (wraps naturally at DEPTH)
  parameter int CW    = $clog2(DEPTH) + 1    // counter width: must reach DEPTH
) (
  input  logic       clk, rst,
  input  logic       s_valid, input  logic [7:0] s_data, output logic s_ready,
  output logic       m_valid, output logic [7:0] m_data, input  logic m_ready
);
  logic [7:0]    mem [DEPTH];
  logic [AW-1:0] wp, rp;
  logic [CW-1:0] count;

  wire full  = (count == DEPTH);
  wire empty = (count == 0);
  assign s_ready = !full;
  assign m_valid = !empty;
  assign m_data  = mem[rp];

  wire push = s_valid && s_ready;
  wire pop  = m_valid && m_ready;

  always_ff @(posedge clk)
    if (rst) begin
      wp <= '0; rp <= '0; count <= '0;
    end else begin
      if (push) begin mem[wp] <= s_data; wp <= wp + 1'b1; end
      if (pop)  rp <= rp + 1'b1;
      count <= count + CW'(push) - CW'(pop);
    end
endmodule
