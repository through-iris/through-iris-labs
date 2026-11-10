// cdc_bind -- attach the ep24 checkers to the designs. One line per rule per
// crossing; the RTL never knows it is being checked. run.py defines
// NO_SVA_BIND to show what plain simulation sees without them.
`ifndef NO_SVA_BIND

// every multi-bit crossing word must be Gray: the FIFO pointers, the counter
bind async_fifo     gray_chk #(AW+1) u_wptr_chk (.clk(wclk), .rst_n(wrst_n), .wgray(wgray));
bind async_fifo     gray_chk #(AW+1) u_rptr_chk (.clk(rclk), .rst_n(rrst_n), .wgray(rgray));
bind bus_xing       gray_chk #(W)    u_word_chk (.clk(sclk), .rst_n(srst_n), .wgray(gray_s));
bind bus_xing_bad   gray_chk #(W)    u_word_chk (.clk(sclk), .rst_n(srst_n), .wgray(cnt_s));

// handshake data must not move while REQ is up
bind handshake_sync hs_stable_chk #(W) u_stable_chk (.sclk(sclk), .rst_n(srst_n), .req(req), .data(data));

// a pulse crossing to a slower clock must outlast its period (run.py sets
// PULSE_N from the clock ratio of each run)
`ifndef PULSE_N
`define PULSE_N 2
`endif
bind pulse_sync_bad pulse_width_chk #(`PULSE_N) u_width_chk (.fclk(sclk), .rst_n(srst_n), .p(p_s));
`endif
