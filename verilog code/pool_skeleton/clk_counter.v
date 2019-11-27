module clk_counter(
  input clk,
  input rstn,
  input start,
  input done,
  output reg [31:0] clk_counter
);

  ////    Don't modify this part   ////
  
  always @(posedge clk or negedge rstn) begin
      if(!rstn) begin
        clk_counter <= 32'd0;
      end
      else begin
        if(start && !done) begin
          clk_counter <= clk_counter+1;
        end
        else begin
          clk_counter <= clk_counter;
        end
      end
  end
  ////////////////////////////////////
endmodule
