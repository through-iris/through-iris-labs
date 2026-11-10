// skid -- a 2-entry stream buffer (an AXI register slice). Final lab, fixed.
//
// The output is a register. When the output is stalled, one more word can be
// parked in the skid register; then s_ready drops until it drains.
module skid (
  input  logic       clk, rst,
  input  logic       s_valid, input  logic [7:0] s_data, output logic s_ready,
  output logic       m_valid, output logic [7:0] m_data, input  logic m_ready
);
  logic       sk_valid;
  logic [7:0] sk_data;

  assign s_ready = !sk_valid;

  always_ff @(posedge clk)
    if (rst) begin
      m_valid <= 1'b0; sk_valid <= 1'b0;
    end else if (!m_valid || m_ready) begin          // the output register is free
      if (sk_valid) begin                             // drain the parked word first
        m_valid <= 1'b1; m_data <= sk_data; sk_valid <= 1'b0;
      end else begin
        m_valid <= s_valid; m_data <= s_data;
      end
    end else if (s_valid && s_ready) begin            // output stalled: park the word
      sk_valid <= 1'b1; sk_data <= s_data;
    end
endmodule
