// tb_handshake -- the REQ/ACK handshake moving random 8-bit words, every
// clock ratio, back-to-back where the source allows it. Each word must
// arrive once, in order, unchanged.
`timescale 1ps/1ps
module tb_handshake;
  `include "tb_common.svh"
  localparam int W = 8, WORDS = 200;

  logic         s_valid = 1'b0, s_ready, d_valid;
  logic [W-1:0] s_data = '0, d_data;
  logic [W-1:0] sent [0:WORDS-1];
  int unsigned  nsent = 0, nrecv = 0, back2back = 0;

  handshake_sync #(W) dut (.sclk, .srst_n, .s_valid, .s_data, .s_ready,
                           .dclk, .drst_n, .d_valid, .d_data);

  initial begin
    wait (srst_n === 1'b1 && drst_n === 1'b1);   // either domain may leave reset first
    while (nsent < WORDS) begin
      @(posedge sclk);
      if (s_valid && s_ready) begin              // accepted this edge
        sent[nsent] = s_data; nsent++;
        s_valid <= 1'b0;
      end
      if ((!s_valid || s_ready) && nsent < WORDS && rnd(0, 3) != 0) begin
        if (s_ready && s_valid) back2back++;
        s_valid <= 1'b1; s_data <= W'(rnd(0, 255));
      end
    end
    s_valid <= 1'b0;
    repeat (src_cycles(16, 8)) @(posedge sclk);
    if (nrecv != WORDS) fail($sformatf("sent %0d words, received %0d", WORDS, nrecv));
    $display("[cov] words %0d, offered on the cycle the previous one was accepted: %0d", nsent, back2back);
    finish_test("handshake");
  end

  always @(posedge dclk) if (drst_n && d_valid) begin
    if (nrecv >= nsent)              fail($sformatf("received word %0d before it was sent", nrecv));
    else if (d_data !== sent[nrecv]) fail($sformatf("word %0d: sent %02h, received %02h", nrecv, sent[nrecv], d_data));
    nrecv++;
  end
endmodule
