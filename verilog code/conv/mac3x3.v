/*************
* mac3x3.v
* piplined multiply&adder
* this module generate results 4 posedge clk after en signal
*************/

//!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!WRONG !!!!!!!!!!!!!!!!!
module mac3x3 
(
  input wire          clk,
  input wire          en,
  input wire          rstn,
  input wire [31:0]   bias,
  input wire [7:0]    w0,
  input wire [7:0]    w1,
  input wire [7:0]    w2,
  input wire [7:0]    w3,
  input wire [7:0]    w4,
  input wire [7:0]    w5,
  input wire [7:0]    w6,
  input wire [7:0]    w7,
  input wire [7:0]    w8,

  input wire [7:0]    f0,
  input wire [7:0]    f1,
  input wire [7:0]    f2,
  input wire [7:0]    f3,
  input wire [7:0]    f4,
  input wire [7:0]    f5,
  input wire [7:0]    f6,
  input wire [7:0]    f7,
  input wire [7:0]    f8,

  output wire[31:0]   mout
);

reg signed  [7:0]   input_1   [8:0];
reg signed  [7:0]   input_2   [8:0];
reg signed  [15:0]  temp_reg  [8:0];
reg signed  [31:0]  temp_reg2      ;
reg signed  [31:0]  temp_reg3      ;
reg signed  [31:0]  temp_reg4      ;
reg signed  [31:0]  temp_reg5      ;
reg signed  [31:0]  bias_buf_1     ;
reg signed  [31:0]  bias_buf_2     ;
reg signed  [31:0]  bias_buf_3     ;


assign mout = temp_reg3;

/*buffering inputs*/
always @( posedge clk or negedge rstn) begin
  if(!rstn  ||  !en) begin
    input_1[0] <=  0;
    input_1[1] <=  0;    
    input_1[2] <=  0;
    input_1[3] <=  0;
    input_1[4] <=  0;
    input_1[5] <=  0;
    input_1[6] <=  0;                    
    input_1[7] <=  0;
    input_1[8] <=  0;  

    input_2[0] <=  0;
    input_2[1] <=  0;    
    input_2[2] <=  0;
    input_2[3] <=  0;
    input_2[4] <=  0;
    input_2[5] <=  0;
    input_2[6] <=  0;                    
    input_2[7] <=  0;
    input_2[8] <=  0;

    bias_buf_1 <=  0;
  end
  else begin
    input_1[0] <=  w0;
    input_1[1] <=  w1;    
    input_1[2] <=  w2;
    input_1[3] <=  w3;
    input_1[4] <=  w4;
    input_1[5] <=  w5;
    input_1[6] <=  w6;                    
    input_1[7] <=  w7;
    input_1[8] <=  w8;  

    input_2[0] <=  f0;
    input_2[1] <=  f1;    
    input_2[2] <=  f2;
    input_2[3] <=  f3;
    input_2[4] <=  f4;
    input_2[5] <=  f5;
    input_2[6] <=  f6;                    
    input_2[7] <=  f7;
    input_2[8] <=  f8;    

    bias_buf_1 <=  bias;
  end
end

/*multiply stage*/
always @( posedge clk or negedge rstn) begin
  if(!rstn  ||  !en) begin
    temp_reg[0] <=  0;
    temp_reg[1] <=  0;
    temp_reg[2] <=  0;
    temp_reg[3] <=  0;
    temp_reg[4] <=  0;
    temp_reg[5] <=  0;
    temp_reg[6] <=  0;
    temp_reg[7] <=  0;
    temp_reg[8] <=  0;
    bias_buf_2  <=  0;
  end
  else begin
    temp_reg[0] <= input_1[0] * input_2[0];
    temp_reg[1] <= input_1[1] * input_2[1];
    temp_reg[2] <= input_1[2] * input_2[2];
    temp_reg[3] <= input_1[3] * input_2[3];
    temp_reg[4] <= input_1[4] * input_2[4];
    temp_reg[5] <= input_1[5] * input_2[5];
    temp_reg[6] <= input_1[6] * input_2[6];
    temp_reg[7] <= input_1[7] * input_2[7];
    temp_reg[8] <= input_1[8] * input_2[8]; 
    bias_buf_2  <=  bias_buf_1;   
  end
end


always @( posedge clk or negedge rstn) begin
  if(!rstn  ||  !en) begin
    temp_reg2 <=  0;
    temp_reg3 <=  0;
    temp_reg4 <=  0;
    temp_reg5 <=  0;
    bias_buf_3<=  0;
  end
  else begin 
    /*add stage1*/
    temp_reg2 <=  temp_reg[0]+temp_reg[1]+temp_reg[2]+temp_reg[3];
    temp_reg5 <=  temp_reg[4]+temp_reg[5]+temp_reg[6]+temp_reg[7];
    temp_reg4 <=  temp_reg[8];
    bias_buf_3<=  bias_buf_2;
    /*add stage2*/
    temp_reg3 <=  temp_reg2 + temp_reg4 +temp_reg5 + bias_buf_3;                 
  end
end


endmodule