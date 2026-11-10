// tb_common.svh -- shared by every testbench: one clock, a reset, a seeded
// random helper, and one place that decides PASS or FAIL.
//
// The lab models PCIe at the transaction and data link layers only, one
// packet per clock. Training, encoding and lanes are the VIP's job (ep26, C1)
// and are not here.

int unsigned seed = 1;
int          rs;                          // random state, mixed from seed
logic clk = 1'b0, rst_n = 1'b0;
int   errors = 0;
longint unsigned cyc = 0;                 // cycles since reset released

initial begin
  void'($value$plusargs("seed=%d", seed));
  rs = seed * 32'h9E37_79B9 ^ 32'h0026_2026;   // small seeds would start correlated
  fork
    forever #5 clk = ~clk;
    begin repeat (4) @(posedge clk); rst_n <= 1'b1; end
  join_none
end

always @(posedge clk) if (rst_n) cyc <= cyc + 1;

function automatic int unsigned rnd(input int unsigned lo, input int unsigned hi);
  rnd = lo + ($unsigned($random(rs)) % (hi - lo + 1));
endfunction

task automatic fail(input string msg);
  errors++;
  if (errors <= 8) $display("[cycle %0d] ERROR %s", cyc, msg);
  if (errors == 8) $display("          (further errors counted, not printed)");
endtask

task automatic finish_test(input string name);
  if (errors == 0) $display("PASS %s", name);
  else             $display("FAIL %s (%0d errors)", name, errors);
  $finish;
endtask
