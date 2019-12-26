`timescale 1ns / 1ps

module top_conv #
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

 // For CONV control path
    wire [2:0]    command;
    wire [8:0]    input_len_ex;
    wire [8:0]    output_len_ex;
    wire [8:0]    width_ex;
    wire          feature_read_done;
    wire          bias_read_done;
    wire          weight_read_done;
    wire [31:0]   clk_counter;
    //     wire          conv_start;   // you can use respond of this signal for handshaking
    wire          conv_done;    // you can use respond of this signal for handshaking
    assign PREADY = 1'b1;
    assign PSLVERR = 1'b0;
    
  
  
  
   clk_counter u_clk_counter(
        .clk(CLK),
        .rstn(RESETN),
        .start(conv_start),
        .done(conv_done),
        .clk_counter(clk_counter)
    );

   conv  #
    (    
        .C_S00_AXIS_TDATA_WIDTH(C_S00_AXIS_TDATA_WIDTH) 
   ) u_conv
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
     //    .conv_start(conv_start),
        .command(command),
        .input_len_ex(input_len_ex),
        .output_len_ex(output_len_ex),
        .width_ex(width_ex),
        .feature_read_done(feature_read_done),
        .bias_read_done(bias_read_done),
        .weight_read_done(weight_read_done),
        .conv_done(conv_done)
   );
   
   apb_conv u_apb_conv(
           .PCLK(CLK),
           .PRESETB(RESETN),
           .PADDR({16'd0,PADDR[15:0]}),
           .PSEL(PSEL),
           .PENABLE(PENABLE),
           .PWRITE(PWRITE),
           .PWDATA(PWDATA),
           .command(command),
           .input_len_ex(input_len_ex),
           .output_len_ex(output_len_ex),
           .width_ex(width_ex),
           .feature_read_done(feature_read_done),
           .bias_read_done(bias_read_done),
           .weight_read_done(weight_read_done),
           .conv_done(conv_done),
           .clk_counter(clk_counter),
           .PRDATA(PRDATA)
         );
   
endmodule
