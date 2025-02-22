module convert_10to5_fifo(
  input  wire rst,   // reset
  input  wire clk,   // clock input
  input  wire clkx2, // 2x clock input
  input  wire [9:0] datain,   // input data for 2:1 serialisation
  output wire [4:0] dataout); // 5-bit data out

  ////////////////////////////////////////////////////
  // Here we instantiate a 16x10 Dual Port RAM
  // and fill first it with data aligned to
  // clk domain
  ////////////////////////////////////////////////////
  wire  [3:0]   wa;       // RAM read address
  reg   [3:0]   wa_d;     // RAM read address
  wire  [3:0]   ra;       // RAM read address
  reg   [3:0]   ra_d;     // RAM read address
  wire  [9:0]  dataint;   // RAM output

  parameter ADDR0  = 4'b0000;
  parameter ADDR1  = 4'b0001;
  parameter ADDR2  = 4'b0010;
  parameter ADDR3  = 4'b0011;
  parameter ADDR4  = 4'b0100;
  parameter ADDR5  = 4'b0101;

  always@(wa) begin
    case (wa)
      ADDR0   : wa_d = ADDR1 ;
      ADDR1   : wa_d = ADDR2 ;
      ADDR2   : wa_d = ADDR3 ;
      ADDR3   : wa_d = ADDR4 ;
      ADDR4   : wa_d = ADDR5 ;
      default : wa_d = ADDR0;
    endcase
  end

  FDC fdc_wa0 (.C(clk),  .D(wa_d[0]), .CLR(rst), .Q(wa[0]));
  FDC fdc_wa1 (.C(clk),  .D(wa_d[1]), .CLR(rst), .Q(wa[1]));
  FDC fdc_wa2 (.C(clk),  .D(wa_d[2]), .CLR(rst), .Q(wa[2]));
  FDC fdc_wa3 (.C(clk),  .D(wa_d[3]), .CLR(rst), .Q(wa[3]));

  //Dual Port fifo to bridge data from clk to clkx2
  DRAM16XN #(.data_width(10))
  fifo_u (
         .DATA_IN(datain),
         .ADDRESS(wa),
         .ADDRESS_DP(ra),
         .WRITE_EN(1'b1),
         .CLK(clk),
         .O_DATA_OUT(),
         .O_DATA_OUT_DP(dataint));

  /////////////////////////////////////////////////////////////////
  // Here starts clk2x domain for fifo read out 
  // FIFO read is set to be once every 2 cycles of clk2x in order
  // to keep up pace with the fifo write speed
  // Also FIFO read reset is delayed a bit in order to avoid
  // underflow.
  /////////////////////////////////////////////////////////////////

  always@(ra) begin
    case (ra)
      ADDR0   : ra_d = ADDR1 ;
      ADDR1   : ra_d = ADDR2 ;
      ADDR2   : ra_d = ADDR3 ;
      ADDR3   : ra_d = ADDR4 ;
      ADDR4   : ra_d = ADDR5 ;
      default : ra_d = ADDR0;
    endcase
  end

  wire rstsync, rstsync_q, rstp;
  (* ASYNC_REG = "TRUE" *) FDP fdp_rst  (.C(clkx2),  .D(rst), .PRE(rst), .Q(rstsync));

  FD fd_rstsync (.C(clkx2),  .D(rstsync), .Q(rstsync_q));
  FD fd_rstp    (.C(clkx2),  .D(rstsync_q), .Q(rstp));

  wire sync;
  FDR sync_gen (.Q (sync), .C (clkx2), .R(rstp), .D(~sync));

  FDRE fdc_ra0 (.C(clkx2),  .D(ra_d[0]), .R(rstp), .CE(sync), .Q(ra[0]));
  FDRE fdc_ra1 (.C(clkx2),  .D(ra_d[1]), .R(rstp), .CE(sync), .Q(ra[1]));
  FDRE fdc_ra2 (.C(clkx2),  .D(ra_d[2]), .R(rstp), .CE(sync), .Q(ra[2]));
  FDRE fdc_ra3 (.C(clkx2),  .D(ra_d[3]), .R(rstp), .CE(sync), .Q(ra[3]));

  wire [9:0] db;

  FDE fd_db0 (.C(clkx2), .D(dataint[0]),   .CE(sync), .Q(db[0]));
  FDE fd_db1 (.C(clkx2), .D(dataint[1]),   .CE(sync), .Q(db[1]));
  FDE fd_db2 (.C(clkx2), .D(dataint[2]),   .CE(sync), .Q(db[2]));
  FDE fd_db3 (.C(clkx2), .D(dataint[3]),   .CE(sync), .Q(db[3]));
  FDE fd_db4 (.C(clkx2), .D(dataint[4]),   .CE(sync), .Q(db[4]));
  FDE fd_db5 (.C(clkx2), .D(dataint[5]),   .CE(sync), .Q(db[5]));
  FDE fd_db6 (.C(clkx2), .D(dataint[6]),   .CE(sync), .Q(db[6]));
  FDE fd_db7 (.C(clkx2), .D(dataint[7]),   .CE(sync), .Q(db[7]));
  FDE fd_db8 (.C(clkx2), .D(dataint[8]),   .CE(sync), .Q(db[8]));
  FDE fd_db9 (.C(clkx2), .D(dataint[9]),   .CE(sync), .Q(db[9]));

  wire [4:0] mux;
  assign mux = (~sync) ? db[4:0] : db[9:5];

  FD fd_out0 (.C(clkx2), .D(mux[0]), .Q(dataout[0]));
  FD fd_out1 (.C(clkx2), .D(mux[1]), .Q(dataout[1]));
  FD fd_out2 (.C(clkx2), .D(mux[2]), .Q(dataout[2]));
  FD fd_out3 (.C(clkx2), .D(mux[3]), .Q(dataout[3]));
  FD fd_out4 (.C(clkx2), .D(mux[4]), .Q(dataout[4]));

endmodule
