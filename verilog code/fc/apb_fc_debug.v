module apb_fc_debug
 
    ( 
    // CPU Interface Input (APB bus interface) 
    input wire          PCLK,       // APB clock 
    input wire          PRESETB,    // APB asynchronous reset (0: reset, 1: normal) 
    input wire [31:0]   PADDR,      // APB address 
    input wire          PSEL,       // APB select 
    input wire          PENABLE,    // APB enable 
    input wire          PWRITE,     // APB write enable 
    input wire [31:0]   PWDATA,     // APB write data 
    input wire [0:0] fc_done, 
    input wire [31:0] clk_counter, 
    input wire [15:0] iter, 
    input wire [0:0] F_writedone, 
    input wire [0:0] B_writedone, 
    input wire [0:0] W_writedone, 
    input wire [0:0] cal_done, 
    input wire [0:0] M_AXIS_TVALID, 
    input wire [31:0] output_debug, 
    input wire [0:0] M_AXIS_TLAST, 
    output reg [0:0] fc_start, 
    output reg [31:0] input_size, 
    output reg [31:0] output_size, 
    output reg [2:0] COMMAND, 
    output reg [0:0] relu, 

    // CPU Interface Output (APB bus interface)
    output wire [31:0]  PRDATA 
    ); 

    wire          state_enable;
    wire          state_enable_pre;
    reg [31:0]          prdata_reg;
 
    assign state_enable = PSEL & PENABLE;
    assign state_enable_pre = PSEL & ~PENABLE;
    // READ OUTPUT
    always @(posedge PCLK, negedge PRESETB) begin
      if (PRESETB == 1'b0) begin
        prdata_reg <= 32'h00000000;
      end
      else begin
        if (~PWRITE & state_enable_pre) begin
          case ({PADDR[31:2], 2'h0})
            /*READOUT*/
            32'h00000000 : prdata_reg <= {31'd0,fc_start};
            32'h00000004 : prdata_reg <= {31'd0,fc_done};
            32'h00000008 : prdata_reg <= {clk_counter};
            32'h00000010 : prdata_reg <= {input_size};
            32'h00000014 : prdata_reg <= {output_size};
            32'h00000018 : prdata_reg <= {29'd0,COMMAND};
            32'h0000001c : prdata_reg <= {16'd0,iter};
            32'h00000020 : prdata_reg <= {31'd0,F_writedone};
            32'h00000024 : prdata_reg <= {31'd0,B_writedone};
            32'h00000028 : prdata_reg <= {31'd0,W_writedone};
            32'h0000002c : prdata_reg <= {31'd0,cal_done};
            32'h00000030 : prdata_reg <= {31'd0,relu};
            32'h00000034 : prdata_reg <= {31'd0,M_AXIS_TVALID};
            32'h00000038 : prdata_reg <= {output_debug};
            32'h0000003c : prdata_reg <= {31'd0,M_AXIS_TLAST};
            default: prdata_reg <= 32'h0; 
          endcase 
        end 
        else begin 
          prdata_reg <= 32'h0; 
        end 
      end 
    end 
    assign PRDATA = (~PWRITE & state_enable) ? prdata_reg : 32'h00000000;
    // WRITE ACCESS 
    always @(posedge PCLK, negedge PRESETB) begin 
      if (PRESETB == 1'b0) begin 
        /*WRITERES*/
        fc_start <= 1'h0;
        input_size <= 32'h0;
        output_size <= 32'h0;
        COMMAND <= 3'h0;
        relu <= 1'h0;
      end 
      else begin 
        if (PWRITE & state_enable) begin 
          case ({PADDR[31:2], 2'h0}) 
            /*WRITEIN*/
            32'h00000000 : begin
              fc_start <= PWDATA[0:0];
            end
            32'h00000010 : begin
              input_size <= PWDATA[31:0];
            end
            32'h00000014 : begin
              output_size <= PWDATA[31:0];
            end
            32'h00000018 : begin
              COMMAND <= PWDATA[2:0];
            end
            32'h00000030 : begin
              relu <= PWDATA[0:0];
            end
            default: ; 
          endcase 
        end 
      end 
    end 
 
endmodule 
