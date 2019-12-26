module apb_pool
 
    ( 
    // CPU Interface Input (APB bus interface) 
    input wire          PCLK,       // APB clock 
    input wire          PRESETB,    // APB asynchronous reset (0: reset, 1: normal) 
    input wire [31:0]   PADDR,      // APB address 
    input wire          PSEL,       // APB select 
    input wire          PENABLE,    // APB enable 
    input wire          PWRITE,     // APB write enable 
    input wire [31:0]   PWDATA,     // APB write data 
    input wire [0:0] pool_done, 
    input wire [31:0] clk_counter, 
    output reg [0:0] pool_start, 
    output reg [7:0] width, 
    output reg [8:0] length, 
    output reg [7:0] height, 
    output reg [10:0] data_size, 

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
            32'h00000000 : prdata_reg <= {31'd0,pool_start};
            32'h00000004 : prdata_reg <= {31'd0,pool_done};
            32'h00000008 : prdata_reg <= {clk_counter};
            32'h0000000c : prdata_reg <= {24'd0,width};
            32'h00000010 : prdata_reg <= {23'd0,length};
            32'h00000014 : prdata_reg <= {24'd0,height};
            32'h00000018 : prdata_reg <= {21'd0,data_size};
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
        pool_start <= 1'h0;
        width <= 8'h0;
        length <= 9'h0;
        height <= 8'h0;
        data_size <= 11'h0;
      end 
      else begin 
        if (PWRITE & state_enable) begin 
          case ({PADDR[31:2], 2'h0}) 
            /*WRITEIN*/
            32'h00000000 : begin
              pool_start <= PWDATA[0:0];
            end
            32'h0000000c : begin
              width <= PWDATA[7:0];
            end
            32'h00000010 : begin
              length <= PWDATA[8:0];
            end
            32'h00000014 : begin
              height <= PWDATA[7:0];
            end
            32'h00000018 : begin
              data_size <= PWDATA[10:0];
            end
            default: ; 
          endcase 
        end 
      end 
    end 
 
endmodule 
