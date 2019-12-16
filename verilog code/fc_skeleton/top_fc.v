`timescale 1ns / 1ps


module top_fc #
(
    parameter integer C_S00_AXIS_TDATA_WIDTH   = 32,
    parameter integer INPUT_SIZE = 256,
    parameter integer OUTPUT_SIZE = 64
)
(
    input wire                                        CLK,
    input wire                                        RESETN,
   /// For AXIS protocol

    output wire                                       S_AXIS_TREADY,
    input wire [C_S00_AXIS_TDATA_WIDTH-1 : 0]         S_AXIS_TDATA,
    input wire [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0]     S_AXIS_TKEEP,
    input wire                                        S_AXIS_TUSER,
    input wire                                        S_AXIS_TLAST,
    input wire                                        S_AXIS_TVALID,
    input wire                                        M_AXIS_TREADY,
    output wire                                       M_AXIS_TUSER,
    output wire [C_S00_AXIS_TDATA_WIDTH-1 : 0]        M_AXIS_TDATA,
    output wire [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0]    M_AXIS_TKEEP,
    output wire                                       M_AXIS_TLAST,
    output wire                                       M_AXIS_TVALID,


 /// For APB protocol
    input wire [31:0]                                 PADDR,
    input wire                                        PENABLE,
    input wire                                        PSEL,
    input wire                                        PWRITE,
    input wire [31:0]                                 PWDATA,
    output wire [31:0]                                PRDATA,
    output wire                                       PREADY,
    output wire                                       PSLVERR,

/// design reference from module_example
    input wire [2:0] COMMAND,
    input wire [20:0] receive_size,
    output wire F_writedone,
    output wire W_writedone,
    output wire B_writedone,
    output wire cal_done,
    input wire fc_start,
    output wire fc_done,
    output reg start_response,
    input wire done_response,
    input wire relu
    );

 // For FC control path
    wire          fc_start;
    wire          fc_done;
    wire [31:0]   clk_counter;
    wire [31:0]   max_index;
    assign PREADY = 1'b1;
    assign PSLVERR = 1'b0;

clk_counter u_clk_counter(
        .clk(CLK),
        .rstn(RESETN),
        .start(fc_start),
        .done(fc_done),
        .clk_counter(clk_counter)
    );

// apb_fc u_apb_fc(
//         .PCLK(CLK),
//         .PRESETB(RESETN),
//         .PADDR({16'd0,PADDR[15:0]}),
//         .PSEL(PSEL),
//         .PENABLE(PENABLE),
//         .PWRITE(PWRITE),
//         .PWDATA(PWDATA),
//         .fc_start(fc_start),
//         .fc_done(fc_done),
//         .clk_counter(clk_counter),
//         .max_index(max_index),
//         .PRDATA(PRDATA)
//       );

fc #(.INPUT_SIZE(INPUT_SIZE), .OUTPUT_SIZE(OUTPUT_SIZE))
    u_fc(
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
        .fc_start(fc_start),
        .max_index(max_index),
        .fc_done(fc_done),
        /// reference from module_example
        .COMMAND(COMMAND),
        .receive_size(receive_size),
        .F_writedone(F_writedone),
        .W_writedone(W_writedone),
        .B_writedone(B_writedone),
        .cal_done(cal_done),
        .relu(relu)
      );


endmodule
