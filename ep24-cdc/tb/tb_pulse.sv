// tb_pulse -- ep24 Break 3: one-cycle events crossing clocks. Every pulse
// the source sends must arrive as exactly one destination pulse. Run it
// fast->slow to lose events through pulse_sync_bad; slow->fast hides the bug.
`timescale 1ps/1ps
module tb_pulse;
  `include "tb_common.svh"
  localparam int PULSES = 40;

  logic spulse = 1'b0, dpulse;
`ifdef BROKEN
  pulse_sync_bad dut (.sclk, .srst_n, .spulse, .dclk, .drst_n, .dpulse);
`else
  pulse_sync     dut (.sclk, .srst_n, .spulse, .dclk, .drst_n, .dpulse);
`endif

  int unsigned gap, got = 0;

  initial begin
    wait (srst_n === 1'b1 && drst_n === 1'b1);   // either domain may leave reset first
    gap = src_cycles(4, 2);                      // toggle sync needs ~3 dst cycles between events
    repeat (PULSES) begin
      repeat (gap + rnd(0, 3)) @(posedge sclk);
      spulse <= 1'b1;
      @(posedge sclk) spulse <= 1'b0;            // one source cycle wide
    end
    repeat (2 * gap) @(posedge sclk);
    if (got != PULSES) fail($sformatf("sent %0d pulses, destination saw %0d -- %0d lost",
                                      PULSES, got, PULSES - got));
    finish_test("pulse");
  end

  always @(posedge dclk) if (drst_n && dpulse) got++;
endmodule
