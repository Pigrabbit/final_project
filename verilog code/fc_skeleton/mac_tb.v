`timescale 1ns/1ps;

module mac_tb;

parameter CLK_CYCLE = 5;

reg clk;
reg rstn;
reg [7:0] data_a;
reg [7:0] data_b;
reg [7:0] data_c;
reg en;
wire done;
wire mout;

mac #(.A_BITWIDTH(8), .OUTBITWIDTH(16)) 
    dut (
        .clk(clk),
        .rstn(rstn),
        .en(en),
        .data_a(data_a),
        .data_b(data_b),
        .data_c(data_c),
        .done(done),
        .mout(mout)
    );

always #CLK_CYCLE clk = ~clk;

initial begin
    clk = 1'b0;
    rstn = 1'b0;
    repeat(10)
        @(posedge clk);

    rstn = 1'b1;
    en = 1'b1;
    data_a = 8'b10000101;
    data_b = 8'b00010100;
    data_c = 8'd9;

    wait(done);
    $display("The result is: %b", mout);

    repeat(5)
        @(posedge clk);
    $finish;
end

endmodule