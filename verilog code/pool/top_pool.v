`timescale 1ns / 1ps

module top_pool #
(
     parameter integer C_S00_AXIS_TDATA_WIDTH   = 32  
)
(
    input wire                                            CLK,
    input wire                                            RESETN,
    // AXI-STREAM
    output wire                                           S_AXIS_TREADY,
    input wire [C_S00_AXIS_TDATA_WIDTH-1 : 0]             S_AXIS_TDATA,
    input wire [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0]         S_AXIS_TKEEP,
    input wire                                            S_AXIS_TUSER,
    input wire                                            S_AXIS_TLAST,
    input wire                                            S_AXIS_TVALID,
    input wire                                            M_AXIS_TREADY,
    output wire                                           M_AXIS_TUSER,
    output wire [C_S00_AXIS_TDATA_WIDTH-1 : 0]            M_AXIS_TDATA,
    output wire [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0]        M_AXIS_TKEEP,
    output wire                                           M_AXIS_TLAST,
    output wire                                           M_AXIS_TVALID,
   // APB
    input wire [31:0]  PADDR, // APB address
    input wire         PSEL, // APB select
    input wire         PENABLE, // APB enable
    input wire         PWRITE, // APB write enable
    input wire [31:0]  PWDATA, // APB write data
    output wire        PSLVERR,
    output wire        PREADY,
    output wire [31:0] PRDATA   // APB read data
     );


 // For Pool control path
    wire          pool_start;   // you can use respond of this signal for handshaking
    wire          pool_done;    // you can use respond of this signal for handshaking
    wire   [7:0]  width;
    wire   [8:0]  length;
    wire   [7:0]  height;
    wire   [31:0] clk_counter;

    assign PREADY = 1'b1;
    assign PSLVERR = 1'b0;
    
  
  
  
   clk_counter u_clk_counter(
        .clk(CLK),
        .rstn(RESETN),
        .start(pool_start),
        .done(pool_done),
        .clk_counter(clk_counter)
    );

   pool  #
    (    
        .C_S00_AXIS_TDATA_WIDTH(C_S00_AXIS_TDATA_WIDTH) 
   ) u_pool
   (   //AXI-STREAM
        .clk(CLK),
        .rstn(RESETN),
        .S_AXIS_TREADY(S_AXIS_TREADY),
        .S_AXIS_TDATA(S_AXIS_TDATA),
        .S_AXIS_TKEEP(S_AXIS_TKEEP),
        .S_AXIS_TUSER(S_AXIS_TUSER),
        .S_AXIS_TLAST(S_AXIS_TLAST),
        .S_AXIS_TVALID(S_AXIS_TVALID),
        .M_AXIS_TREADY(M_AXIS_TREADY),
        .M_AXIS_TUSER(M_AXIS_TUSER),
        .M_AXIS_TDATA(M_AXIS_TDATA),
        .M_AXIS_TKEEP(M_AXIS_TKEEP),
        .M_AXIS_TLAST(M_AXIS_TLAST),
        .M_AXIS_TVALID(M_AXIS_TVALID),
        //Control
        .pool_start_external(pool_start),
        .width_external(width),
        .length_external(length),
        .height_external(height),
        .pool_done(pool_done)
   );
  apb_pool u_apb_pool(
           .PCLK(CLK),
           .PRESETB(RESETN),
           .PADDR({16'd0,PADDR[15:0]}),
           .PSEL(PSEL),
           .PENABLE(PENABLE),
           .PWRITE(PWRITE),
           .PWDATA(PWDATA),
           .pool_start(pool_start),
           .pool_done(pool_done),
           .width(width),
           .length(length),
           .height(height),
           .clk_counter(clk_counter),
           .PRDATA(PRDATA)
         );
   
   
endmodule
