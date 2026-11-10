// axi_slave -- the design under test: a small AXI4 slave with four registers
// and a 1 KB memory window that the registers place and switch on.
//
//   0x0000  ID      RO  0x4158_4931 ("AXI1")
//   0x0004  CTRL    RW  [0] EN: the memory window answers (else SLVERR)
//                       [9:8] MODE: wait states before BVALID and the first RVALID
//   0x0008  BASE    RW  [15:12] PAGE: the window sits at PAGE * 4 KB (reset 0x1000)
//   0x000C  STATUS  RO  0x0000_0001 (ready)
//   BASE .. BASE+0x3FF  memory, 256 words, zero after reset
//
// Anything else answers DECERR. A write to ID or STATUS answers SLVERR and
// changes nothing. Writes honour WSTRB byte by byte (ep04). One transaction
// at a time, INCR bursts of 1-8 beats; a burst is decoded on its first
// address and the sequences never let one leave its region.
//
// `busy` is a test hook: a cycle in which the slave is busy elsewhere, so it
// drops every READY. tb_top drives it at random. It never touches a VALID.
`timescale 1ns/1ps
module axi_slave (
  input  logic        aclk,
  input  logic        aresetn,
  input  logic        busy,
  // write address
  input  logic [3:0]  awid,
  input  logic [15:0] awaddr,
  input  logic [7:0]  awlen,
  input  logic [2:0]  awsize,
  input  logic [1:0]  awburst,
  input  logic        awvalid,
  output logic        awready,
  // write data
  input  logic [31:0] wdata,
  input  logic [3:0]  wstrb,
  input  logic        wlast,
  input  logic        wvalid,
  output logic        wready,
  // write response
  output logic [3:0]  bid,
  output logic [1:0]  bresp,
  output logic        bvalid,
  input  logic        bready,
  // read address
  input  logic [3:0]  arid,
  input  logic [15:0] araddr,
  input  logic [7:0]  arlen,
  input  logic [2:0]  arsize,
  input  logic [1:0]  arburst,
  input  logic        arvalid,
  output logic        arready,
  // read data
  output logic [3:0]  rid,
  output logic [31:0] rdata,
  output logic [1:0]  rresp,
  output logic        rlast,
  output logic        rvalid,
  input  logic        rready
);
  localparam logic [1:0]  OKAY = 2'b00, SLVERR = 2'b10, DECERR = 2'b11;
  localparam logic [31:0] ID_VALUE = 32'h4158_4931, STATUS_VALUE = 32'h0000_0001;
  localparam logic [31:0] CTRL_MASK = 32'h0000_0301, BASE_MASK = 32'h0000_F000;

  logic [31:0] ctrl, base;
  logic [31:0] mem [256];
  wire         en   = ctrl[0];
  wire  [1:0]  mode = ctrl[9:8];

  typedef enum logic [1:0] {IDLE, WDATA, WRESP, RDATA} state_t;
  state_t      state;
  logic [15:0] addr;          // address of the current beat
  logic [7:0]  len, beat;     // AxLEN of the burst, and the beat we're on
  logic [3:0]  id;
  logic [1:0]  resp;          // decided once, on the burst's first address
  logic [1:0]  wait_cnt;

  function automatic logic [1:0] decode(input logic [15:0] a, input logic is_write);
    if (a[15:8] == 8'h00)
      case (a[7:0])
        8'h00, 8'h0C: return is_write ? SLVERR : OKAY;   // ID, STATUS: read-only
        8'h04, 8'h08: return OKAY;                       // CTRL, BASE
        default:      return DECERR;
      endcase
    if (a[15:10] == {base[15:12], 2'b00}) return en ? OKAY : SLVERR;
    return DECERR;
  endfunction

  function automatic logic [31:0] read_word(input logic [15:0] a);
    if (a[15:8] == 8'h00)
      case (a[7:0])
        8'h00:   return ID_VALUE;
        8'h04:   return ctrl;
        8'h08:   return base;
        8'h0C:   return STATUS_VALUE;
        default: return '0;
      endcase
    return mem[a[9:2]];
  endfunction

  // only the strobed bytes change
  function automatic logic [31:0] merge(input logic [31:0] old, input logic [31:0] d, input logic [3:0] s);
    for (int b = 0; b < 4; b++)
      if (s[b]) old[8*b +: 8] = d[8*b +: 8];
    return old;
  endfunction

  // READY: only when idle (or taking data), and never while busy
  assign awready = (state == IDLE) && !busy;
  assign arready = (state == IDLE) && !awvalid && !busy;     // a waiting write goes first
  assign wready  = (state == WDATA) && !busy;

  // VALID: once up, held until the master takes it
  assign bvalid = (state == WRESP) && (wait_cnt == 0);
  assign bid    = id;
  assign bresp  = resp;
  assign rvalid = (state == RDATA) && (wait_cnt == 0);
  assign rid    = id;
  assign rresp  = resp;
  assign rlast  = (beat == len);
  assign rdata  = (resp == OKAY) ? read_word(addr) : '0;

  always_ff @(posedge aclk or negedge aresetn)
    if (!aresetn) begin
      state <= IDLE; ctrl <= '0; base <= 32'h0000_1000;
      addr <= '0; len <= '0; beat <= '0; id <= '0; resp <= OKAY; wait_cnt <= '0;
      for (int i = 0; i < 256; i++) mem[i] <= '0;
    end else
      case (state)
        IDLE:
          if (awvalid && awready) begin
            addr <= awaddr; len <= awlen; beat <= '0; id <= awid;
            resp <= decode(awaddr, 1'b1);
            state <= WDATA;
          end else if (arvalid && arready) begin
            addr <= araddr; len <= arlen; beat <= '0; id <= arid;
            resp <= decode(araddr, 1'b0);
            wait_cnt <= mode;
            state <= RDATA;
          end
        WDATA:
          if (wvalid && wready) begin
            if (resp == OKAY) begin
              if (addr[15:8] == 8'h00) begin
                if (addr[7:0] == 8'h04) ctrl <= merge(ctrl, wdata, wstrb) & CTRL_MASK;
                if (addr[7:0] == 8'h08) base <= merge(base, wdata, wstrb) & BASE_MASK;
              end else
                mem[addr[9:2]] <= merge(mem[addr[9:2]], wdata, wstrb);
            end
            addr <= addr + 16'd4;
            beat <= beat + 8'd1;
            if (beat == len) begin
              wait_cnt <= mode;
              state <= WRESP;
            end
          end
        WRESP:
          if (wait_cnt != 0) wait_cnt <= wait_cnt - 2'd1;
          else if (bready) state <= IDLE;
        RDATA:
          if (wait_cnt != 0) wait_cnt <= wait_cnt - 2'd1;
          else if (rready) begin
            addr <= addr + 16'd4;
            beat <= beat + 8'd1;
            if (beat == len) state <= IDLE;
          end
        default: state <= IDLE;
      endcase
endmodule
