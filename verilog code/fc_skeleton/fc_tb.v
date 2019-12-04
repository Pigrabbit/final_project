`timescale 1ns/1ps;
module fc_tb;
// 먼저 mac동작만 확인해보자
parameter integer DATA_WIDTH = 32;
parameter integer BYTE_SIZE = 8;
parameter integer INPUT_SIZE = 64;
parameter integer OUTPUT_SIZE = 10;
parameter integer WEIGHT_SIZE = INPUT_SIZE * OUTPUT_SIZE;
parameter integer BIAS_SIZE = OUTPUT_SIZE;
parameter CLK_CYCLE = 5;

integer i;

reg clk;
reg rstn;
// 각 feature, weight, bias에 값 넣어주기
reg [DATA_WIDTH-1:0] feature [0:INPUT_SIZE-1];
reg [DATA_WIDTH-1:0] weight [0:WEIGHT_SIZE-1];
reg [DATA_WIDTH-1:0] bias [0:BIAS_SIZE-1];
wire [DATA_WIDTH-1:0] out_data [0:OUTPUT_SIZE-1];

reg [DATA_WIDTH-1:0] transfer_data;

fc #()
    dut (
        .clk(clk),
        .rstn(rstn)
        .S_AXIS_TDATA(transfer_data)
    );

always #CLK_CYCLE clk = ~clk;

initial begin
    clk = 1'b0;
    rstn = 1'b0;
    repeat(5)
        @(posedge clk)

    for (i = 0; i < INPUT_SIZE; i = i + 1) begin
        feature[i] = 32'b1 + i;
    end

    for (i = 0; i < WEIGHT_SIZE; i = i + 1) begin
        weight[i] = 32'b1 + i;
    end

    for (i = 0; i < BIAS_SIZE; i = i + 1) begin
        bias[i] = 32'b1 + i;
    end

end



endmodule