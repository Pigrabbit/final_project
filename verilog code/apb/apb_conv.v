module apb_conv
 
    ( 
    // CPU Interface Input (APB bus interface) 
    input wire          PCLK,       // APB clock 
    input wire          PRESETB,    // APB asynchronous reset (0: reset, 1: normal) 
    input wire [31:0]   PADDR,      // APB address 
    input wire          PSEL,       // APB select 
    input wire          PENABLE,    // APB enable 
    input wire          PWRITE,     // APB write enable 
    input wire [31:0]   PWDATA,     // APB write data 
    input wire [0:0] feature_read_done, 
    input wire [0:0] bias_read_done, 
    input wire [0:0] weight_read_done, 
    input wire [0:0] conv_done, 
    output reg [2:0] command, 
    output reg [8:0] input_len_ex, 
    output reg [8:0] output_len_ex, 
    output reg [8:0] width_ex, 

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
            32'h00000000 : prdata_reg <= {29'd0,command};
            32'h00000004 : prdata_reg <= {23'd0,input_len_ex};
            32'h00000008 : prdata_reg <= {23'd0,output_len_ex};
            32'h0000000c : prdata_reg <= {23'd0,width_ex};
            32'h00000010 : prdata_reg <= {31'd0,feature_read_done};
            32'h00000014 : prdata_reg <= {31'd0,bias_read_done};
            32'h00000018 : prdata_reg <= {31'd0,weight_read_done};
            32'h0000001c : prdata_reg <= {31'd0,conv_done};
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
        command <= 3'h0;
        input_len_ex <= 9'h0;
        output_len_ex <= 9'h0;
        width_ex <= 9'h0;
      end 
      else begin 
        if (PWRITE & state_enable) begin 
          case ({PADDR[31:2], 2'h0}) 
            /*WRITEIN*/
            32'h00000000 : begin
              command <= PWDATA[2:0];
            end
            32'h00000004 : begin
              input_len_ex <= PWDATA[8:0];
            end
            32'h00000008 : begin
              output_len_ex <= PWDATA[8:0];
            end
            32'h0000000c : begin
              width_ex <= PWDATA[8:0];
            end
            default: ; 
          endcase 
        end 
      end 
    end 
 
endmodule 
