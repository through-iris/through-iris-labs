// clk_cfg -- the clock-ratio randomization from ep24 (6:56), as shown on
// screen: periods and phase in ps, and either side may be the faster one.
//
// run.py applies these same constraints in Python and passes the result in as
// plusargs, so the testbenches run on simulators without a constraint solver
// (Icarus). In a UVM environment you would randomize this class in the test.
class clk_cfg;   // tb: periods + phase in ps
  rand int unsigned src_ps, dst_ps, skew_ps;
  constraint c { src_ps inside {[1000:20000]};
                 dst_ps inside {[1000:20000]};
                 skew_ps < dst_ps; }
endclass
