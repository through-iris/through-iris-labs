// cdc_sva -- the three CDC rules from ep24 (6:56), as checker modules.
// They are attached with bind (cdc_bind.sv), so no design file is edited to
// check it. The property bodies are the ones on screen in the episode, plus a
// reset guard and a message worth reading (ep22, 7:36).
//
// Concurrent assertions need a simulator with SVA: Verilator 5 here, or any
// commercial simulator. Icarus runs the scoreboards without them.

// Gray pointer: at most one bit per change
module gray_chk #(parameter int W = 4) (
  input logic clk, rst_n,
  input logic [W-1:0] wgray);
  a_gray: assert property (@(posedge clk) disable iff (!rst_n)
    $countones(wgray ^ $past(wgray)) <= 1)
    else $error("CDC: crossing word changed %0d bits at once (%b -> %b); only one may",
                $countones(wgray ^ $past(wgray)), $past(wgray), wgray);
endmodule

// handshake: data frozen while REQ is high
module hs_stable_chk #(parameter int W = 8) (
  input logic sclk, rst_n, req,
  input logic [W-1:0] data);
  a_stable: assert property (@(posedge sclk) disable iff (!rst_n)
    $past(req) && req |-> $stable(data))
    else $error("CDC: handshake data changed (%h -> %h) while REQ was high", $past(data), data);
endmodule

// pulse: N fast cycles span a slow period
module pulse_width_chk #(parameter int N = 2) (
  input logic fclk, rst_n, p);
  a_width: assert property (@(posedge fclk) disable iff (!rst_n) $rose(p) |-> p[*N])
    else $error("CDC: pulse shorter than %0d source cycles; the slower clock can miss it", N);
endmodule
