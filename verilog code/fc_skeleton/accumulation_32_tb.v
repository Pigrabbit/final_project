`timescale 1ns/1ps;
module accumulation_32_tb;
reg clk;
reg rstn;
reg en;
wire done;
reg [255:0] feature;
reg [255:0] weight;
wire [19:0] result;

parameter CLK_CYCLE = 5;

accumulation_32 dut (
    .clk(clk),
    .rstn(rstn),
    .en(en),
    .done(done),
    .feature(feature),
    .weight(weight),
    .result(result)
);

always #CLK_CYCLE clk = ~clk;

initial begin
    clk = 1'b0;
    rstn = 1'b0;
    en = 1'b0;

    repeat(5)
        @(posedge clk)

    rstn = 1'b1;

    repeat(5)
        @(posedge clk)

    feature[31:0] = 32'b00010000000011110001110100000000;
    feature[63:32] = 32'b00001101000001100000000000000000;
    feature[95:64] = 32'b00000000000011110000100100011101;
    feature[127:96] = 32'b00000000000000000000000100001101;
    feature[159:128] = 32'b00000001000001000000011000000000;
    feature[191:160] = 32'b00010001000011010001000100000011;
    feature[223:192] = 32'b00010111000111100000000000001101;
    feature[255:224] = 32'b00001111000110110010011000001110;

    weight[31:0] = 32'b00000000000000001111110100000000;
    weight[63:32] = 32'b11111101111111100000000000000000;
    weight[95:64] = 32'b00000001000000000000000100001001;
    weight[127:96] = 32'b00000000000000000000000111111110;
    weight[159:128] = 32'b00000001000000001111110000000000;
    weight[191:160] = 32'b00000000111111111111111100000010;
    weight[223:192] = 32'b11111000111111010000001111111111;
    weight[255:224] = 32'b11111010000000010000011100000010;

    repeat(5)
        @(posedge clk)

    en = 1'b1;

    repeat(40)
        @(posedge clk)

    $display("The result is: %b", result);

    $finish;
end

endmodule