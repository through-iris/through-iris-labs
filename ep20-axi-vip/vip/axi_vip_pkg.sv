// axi_vip_pkg -- the AXI VIP: everything the env builds, in build order.
`timescale 1ns/1ps
`include "uvm_lite_macros.svh"

package axi_vip_pkg;
  import uvm_lite_pkg::*;

  int unsigned axi_seed = 1;          // +seed, for the [cfg] line
  bit          axi_journey = 0;       // +journey: follow one register write and one write
  bit          axi_trace_reg = 0;     // the adapter tags the traced register access
  bit          axi_trace_next = 0;    // the driver has started a traced item
  string       axi_drv_waiting = "reset";   // what the driver waits on: for a hang message

  `include "axi_seq_item.svh"
  `include "axi_driver.svh"
  `include "axi_monitor.svh"
  `include "axi_agent.svh"
  `include "axi_scoreboard.svh"
  `include "axi_coverage.svh"
  `include "axi_reg_block.svh"
  `include "axi_env.svh"
  `include "axi_vseq.svh"
  // the three breaks: one component each, swapped in through the factory
  `include "broken/axi_env_no_sb.svh"
  `include "broken/axi_reg_adapter_no_strb.svh"
  `include "broken/axi_driver_backoff.svh"
  `include "axi_test.svh"
endpackage
