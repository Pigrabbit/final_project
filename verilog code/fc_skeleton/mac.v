`timescale 1ns/1ps;

module mac #(
    parameter integer A_BITWIDTH = 8,
    parameter integer B_BITWIDTH = A_BITWIDTH,
    parameter integer OUT_BITWIDTH = 19, // need to be changed
    parameter integer C_BITWIDTH = OUT_BITWIDTH - 1
)
(
    input clk,
    input rstn,
    input en,
    input [A_BITWIDTH-1:0] data_a,
    input [B_BITWIDTH-1:0] data_b,
    input [C_BITWIDTH-1:0] data_c,
    output reg done,
    output [OUT_BITWIDTH-1:0] mout
);

localparam
    STATE_IDLE = 2'b00,
    STATE_MULT = 2'b01,
    STATE_ADD =  2'b10,
    STATE_DONE = 2'b11;

reg [1:0] m_state;

reg signed [A_BITWIDTH-1:0] tmp_data_a;
reg signed [B_BITWIDTH-1:0] tmp_data_b;
reg signed [C_BITWIDTH-1:0] tmp_data_c;
reg signed [OUT_BITWIDTH-1:0] mult_result;
reg signed [OUT_BITWIDTH-1:0] add_result;

assign mout = add_result;

// state machine
always @(posedge clk or negedge rstn) begin
    if (!rstn) 
        m_state <= STATE_IDLE;
    else begin
        case(m_state)
            STATE_IDLE: begin
                if(en && !done)
                    m_state <= STATE_MULT;
                else 
                    m_state <= STATE_IDLE;
            end
            STATE_MULT: begin
                m_state <= STATE_ADD;
            end
            STATE_ADD: begin
                m_state <= STATE_DONE;
            end
            STATE_DONE: begin
                m_state <= STATE_IDLE;
            end
            default: ;
        endcase
    end
end

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        tmp_data_a <= {A_BITWIDTH{1'b0}};
        tmp_data_b <= {B_BITWIDTH{1'b0}};
        tmp_data_c <= {C_BITWIDTH{1'b0}}; // need to be changed
        mult_result <= {OUT_BITWIDTH{1'b0}};
        add_result <= {OUT_BITWIDTH{1'b0}};
        done <= 1'b0;
    end 
    else begin
        case(m_state)
            STATE_IDLE: begin
                done <= 1'b0;
                mult_result <= mult_result;
                if (en & !done) begin
                    tmp_data_a <= data_a;
                    tmp_data_b <= data_b;
                    tmp_data_c <= data_c;
                end
            end
            STATE_MULT: begin
                mult_result <= tmp_data_a * tmp_data_b;
            end
            STATE_ADD: begin
                add_result <= mult_result + tmp_data_c; 
            end
            STATE_DONE: begin
                done <= 1'b1;
            end
            default: ;
        endcase
    end   
end

endmodule