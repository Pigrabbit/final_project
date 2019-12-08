module fc #
 (
      parameter integer C_S00_AXIS_TDATA_WIDTH   = 32,
      parameter integer INPUT_SIZE = 256,
      parameter integer OUTPUT_SIZE = 64,
      parameter integer BIAS_SIZE = OUTPUT_SIZE,
      parameter integer WEIGHT_SIZE = INPUT_SIZE * OUTPUT_SIZE,
      parameter integer MAX_ITER_ACCUMULATION = INPUT_SIZE >> 5
 )
 (   //AXI-STREAM
    input wire                                            clk,
    input wire                                            rstn,
    // S_AXI ports for receiving data
    output wire                                           S_AXIS_TREADY,
    input wire [C_S00_AXIS_TDATA_WIDTH-1 : 0]             S_AXIS_TDATA,  
    input wire [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0]         S_AXIS_TKEEP,  
    input wire                                            S_AXIS_TUSER,  
    input wire                                            S_AXIS_TLAST,  
    input wire                                            S_AXIS_TVALID, 
    // M_AXI ports for sending data
    input wire                                            M_AXIS_TREADY,
    output wire                                           M_AXIS_TUSER,
    output wire [C_S00_AXIS_TDATA_WIDTH-1 : 0]            M_AXIS_TDATA,
    output wire [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0]        M_AXIS_TKEEP,
    output wire                                           M_AXIS_TLAST,
    output wire                                           M_AXIS_TVALID,

     //Control
    input                                                 fc_start,
    output reg [31:0]                                     max_index, // Only for last fully connected layer. It has same functionality with softmax. If output size is 10, max_index indicate index of value which is largest of 10 outputs.
    output reg                                            fc_done,

    // design reference from module_example
    input wire [2:0] COMMAND,
    input wire [20:0] receive_size,
    output reg F_writedone,
    output reg W_writedone,
    output reg B_writedone,
    output reg cal_done
  );

// fc states parameter
localparam STATE_IDLE             = 4'b0000;
localparam STATE_RECEIVE_FEATURE  = 4'b0001;
localparam STATE_RECEIVE_BIAS     = 4'b0010;
localparam STATE_RECEIVE_WEIGHT   = 4'b0011;
localparam STATE_SET_FEATURE      = 4'b0100;
localparam STATE_SET_BIAS         = 4'b0101;
localparam STATE_ACC_32           = 4'b0110;
localparam STATE_PARTIAL_SUM      = 4'b0111;
localparam STATE_ADD_BIAS         = 4'b1000;
localparam STATE_RELU             = 4'b1001;
localparam STATE_DATA_SEND        = 4'b1010;

localparam FEATURE_START_ADDRESS  = 9'b0_0000_0000;   // at most 1568 features in 392 lines, where 4 features per line
localparam BIAS_START_ADDRESS     = 9'b1_1001_0000;  // at most  256   biases in  64 lines, where 4   biases per line


reg                                           m_axis_tuser;
reg [C_S00_AXIS_TDATA_WIDTH-1 : 0]            m_axis_tdata;
reg [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0]        m_axis_tkeep;
reg                                           m_axis_tlast;
reg                                           m_axis_tvalid;
reg                                           s_axis_tready;

assign S_AXIS_TREADY = s_axis_tready;
assign M_AXIS_TDATA = m_axis_tdata;
assign M_AXIS_TLAST = m_axis_tlast;
assign M_AXIS_TVALID = m_axis_tvalid;
assign M_AXIS_TUSER = 1'b0;
assign M_AXIS_TKEEP = {(C_S00_AXIS_TDATA_WIDTH/8) {1'b1}};   


// BRAM In/Out
reg           bram_en;
reg           bram_we;
reg   [8:0]   bram_addr;
reg   [8:0]   bram_feature_tmp_addr;
reg   [8:0]   bram_bias_tmp_addr;
reg   [31:0]  bram_din;
wire  [31:0]  bram_dout;
reg   [3:0]   bram_state;
reg   [7:0]   bram_delay;

// MAC In/Out
reg           acc_en;
wire          acc_done;
reg   [3:0]   acc_delay;
wire  [19:0]  acc_result;
reg   [255:0] feature_buffer;
reg   [255:0] weight_buffer;
reg   [7:0]   bias_buffer;
reg   [7:0]   output_buffer;

// partial sum buffer
reg   [20:0]  tmp_partial_sum1 [0:MAX_ITER_ACCUMULATION-1];
reg   [21:0]  tmp_partial_sum2 [0:(MAX_ITER_ACCUMULATION >> 1) - 1];
reg   [22:0]  tmp_partial_sum3 [0:(MAX_ITER_ACCUMULATION >> 2) - 1];
reg   [23:0]  tmp_partial_sum4 [0:(MAX_ITER_ACCUMULATION >> 3) - 1];
reg   [24:0]  tmp_output       [0:OUTPUT_SIZE - 1];

reg   [3:0]   cal_state;
reg   [7:0]   acc_counter;
reg   [7:0]   feature_counter;    
reg   [7:0]   weight_counter;
reg   [7:0]   bias_counter;
reg   [3:0]   bias_pointer;   
reg   [7:0]   out_counter;
reg   [7:0]   partial_sum_counter;

// control signals
reg         feature_set_done;
reg         bias_set_done;
reg         partial_sum_done;
reg         relu_done;
reg         feature_weight_ready;
reg         acc_32_done;
reg         add_bias_done;


sram_32x512 u_sram_32x512(
    .addra(bram_addr),
    .clka(clk),
    .dina(bram_din),
    .douta(bram_dout),
    .ena(bram_en),
    .wea(bram_we)
);

// generate 써서 하자.
accumulation_32 u_accumulation_32 (
    .clk(clk),
    .rstn(rstn),
    .en(acc_en),
    .done(acc_done),
    .feature(feature_buffer),
    .weight(weight_buffer),
    .result(acc_result)
  );


// Bram operation
always @(posedge clk or negedge rstn) begin
  if(!rstn) begin
    s_axis_tready <= 1'b0;
    m_axis_tuser <= 1'b0;
    m_axis_tdata <= {32{1'b0}};
    m_axis_tkeep <= {4{1'b0}};
    m_axis_tlast <= 1'b0; 
    m_axis_tvalid <= 1'b0;

    bram_state <= STATE_IDLE;
    bram_en <= 1'b0;
    bram_we <= 1'b0;
    bram_addr <= {9{1'b1}};
    bram_feature_tmp_addr <= FEATURE_START_ADDRESS;
    bram_bias_tmp_addr <= BIAS_START_ADDRESS;
    bram_din <= {32{1'b0}};
    bram_delay <= {8{1'b0}};

    F_writedone <= 1'b0;
    B_writedone <= 1'b0;
    W_writedone <= 1'b0;
    feature_set_done <= 1'b0;
    bias_set_done <= 1'b0;
    feature_weight_ready <= 1'b0;
    
    weight_counter <= {8{1'b0}};
    feature_counter <= {8{1'b0}};
    bias_counter <= {8{1'b0}};
    bias_pointer <= {3{1'b0}};
    feature_buffer <= {255{1'b0}};
    weight_buffer <= {255{1'b0}};
    bias_buffer <= {8{1'b0}};
  end
  else begin
    case(bram_state)
      STATE_IDLE: begin
        if(fc_start) begin
          s_axis_tready <= 1'b1;
          bram_state <= STATE_RECEIVE_FEATURE;
        end
        else begin
          bram_state <= STATE_IDLE;
        end
      end

      // receives features from VDMA or testbench
      // and write them on BRAM from FEATURE_START_ADDRESS
      // 4 features are written on each address(each line)
      // eg) W0: addr_data[7:0], W1: addr_data[15:8], W2: addr_data[23:16], W3: addr_data[31:24] 
      // in total, (INPUT_SIZE/4) of lines are needed
      STATE_RECEIVE_FEATURE: begin
        if(F_writedone) begin
          bram_en <= 1'b0;
          bram_we <= 1'b0;
          bram_addr <= {9{1'b1}};
          bram_din <= {32{1'b0}};
          s_axis_tready <= 1'b0;
          if(COMMAND == 3'b010) begin
            bram_state <= STATE_RECEIVE_BIAS;
          end
        end
        else begin
          s_axis_tready <= 1'b1;
          bram_en <= 1'b1;
          bram_we <= 1'b1;
          bram_din <= S_AXIS_TDATA;
          if(feature_counter == 0) begin
            bram_addr <= FEATURE_START_ADDRESS;  
            feature_counter <= feature_counter + 9'b1;
          end
          else if (S_AXIS_TLAST && feature_counter >= (INPUT_SIZE >> 2)) begin
            feature_counter <= 8'b0;
            F_writedone <= 1'b1;
          end
          else begin
            feature_counter <= feature_counter + 8'b1;
            bram_addr <= bram_addr + 9'b1;
          end
        end
      end
    
      // receives biases from VDMA or testbench
      // and write them on BRAM from BIAS_START_ADDRESS
      // 4 biases are written on each address(each line)
      // eg) B0: addr_data[7:0], B1: addr_data[15:8], B2: addr_data[23:16], B3: addr_data[31:24]
      // in total, (BIAS_SIZE/4) of lines are needed
      STATE_RECEIVE_BIAS: begin
        if(B_writedone) begin
          bram_en <= 1'b0;
          bram_we <= 1'b0;
          bram_addr <= {9{1'b1}};
          bram_din <= {32{1'b0}};
          s_axis_tready <= 1'b0;
          if (COMMAND == 3'b100) begin
            bram_state <= STATE_RECEIVE_WEIGHT;
          end
        end
        else begin
          F_writedone <= 1'b0;
          s_axis_tready <= 1'b1;
          bram_en <= 1'b1;
          bram_we <= 1'b1;
          bram_din <= S_AXIS_TDATA;
          if (bias_counter == 0) begin
            bram_addr <= BIAS_START_ADDRESS;
            bias_counter <= bias_counter + 8'b1;  
          end
          else if(S_AXIS_TLAST && bias_counter >= (BIAS_SIZE >> 2)) begin
            bias_counter <= {4{1'b0}};
            B_writedone <= 1'b1;
          end
          else begin
            bias_counter <= bias_counter + 8'b1;
            bram_addr <= bram_addr + 9'b1;
          end
        end
      end

      // receives 32 weights from VDMA or testbench
      // and write them on register weight_buffer
      // these weights are going to be calculated in [accumulation_32] module
      // each cycle it reads 4 weights (32 bit per cycle)
      // as result, 8 counter cycle is needed to read them all
      STATE_RECEIVE_WEIGHT: begin
        if(W_writedone) begin
          s_axis_tready <= 1'b0;
          weight_counter <= 8'b0;
          bram_state <= STATE_SET_FEATURE;
        end
        else begin
          B_writedone <= 1'b0;
          feature_weight_ready <= 1'b0;
          s_axis_tready <= 1'b1;
          if (weight_counter >= 8'd8) begin 
            W_writedone <= 1'b1;
          end
          else begin
            weight_buffer <= weight_buffer >> 32;
            weight_buffer[255-:32] <= S_AXIS_TDATA;
            weight_counter <= weight_counter + 8'b1;
          end
        end
      end

      // reads features from BRAM
      // and sets features on register feature_buffer
      // these features are going to be calculated in [accumulation_32] module
      // BRAM read operation needs delay
      // when setting feature is done, 
      // state changes to RECEIVE_WEIGHT, if summing up to MAX_ITER_ACC(INPUT_SIZE/32) is not done
      // state changes to SET_BIAS, if it is done
      STATE_SET_FEATURE: begin
        if(feature_set_done) begin
          bram_en <= 1'b0;
          bram_we <= 1'b0;
          feature_weight_ready <= 1'b1;
          bram_feature_tmp_addr <= bram_addr;
          if (acc_done && acc_counter >= 8'd6) begin
            // calculating partial sum is done
            feature_set_done <= 1'b0;
            bram_state <= STATE_SET_BIAS;  
          end
          else if (acc_done) begin
            // calculating partial sum
            feature_set_done <= 1'b0;
            bram_state <= STATE_RECEIVE_WEIGHT;  
          end
          else begin
            bram_state <= STATE_SET_FEATURE;
          end
        end
        else begin
          // bram read features operation
          case(bram_delay)
            8'd0: begin
              W_writedone <= 1'b0;
              bram_en <= 1'b1;
              bram_we <= 1'b0;
              bram_addr <= bram_feature_tmp_addr;
              bram_delay <= bram_delay + 8'b1;
            end

            8'd1: bram_delay <= bram_delay + 8'b1;

            8'd2: begin
              feature_buffer[31:0] <= bram_dout;
              bram_addr <= bram_addr + 9'b1;
              bram_delay <= bram_delay + 8'b1;
            end

            8'd3: bram_delay <= bram_delay + 4'b1;

            8'd4: begin
              feature_buffer[63:32] <= bram_dout;
              bram_addr <= bram_addr + 9'b1;
              bram_delay <= bram_delay + 8'b1;
            end

            8'd5: bram_delay <= bram_delay + 8'b1;

            8'd6: begin
              feature_buffer[95:64] <= bram_dout;
              bram_addr <= bram_addr + 9'b1;
              bram_delay <= bram_delay + 8'b1;
            end

            8'd7: bram_delay <= bram_delay + 8'b1;

            8'd8: begin
              feature_buffer[127:96] <= bram_dout;
              bram_addr <= bram_addr + 9'b1;
              bram_delay <= bram_delay + 8'b1;
            end

            8'd9: bram_delay <= bram_delay + 8'b1;

            8'd10: begin
              feature_buffer[159:128] <= bram_dout;
              bram_addr <= bram_addr + 9'b1;
              bram_delay <= bram_delay + 8'b1;
            end

            8'd11: bram_delay <= bram_delay + 8'b1;

            8'd12: begin
              feature_buffer[191:160] <= bram_dout;
              bram_addr <= bram_addr + 9'b1;
              bram_delay <= bram_delay + 8'b1;
            end

            8'd13: bram_delay <= bram_delay + 8'b1;

            8'd14: begin
              feature_buffer[223:192] <= bram_dout;
              bram_addr <= bram_addr + 9'b1;
              bram_delay <= bram_delay + 8'b1;
            end

            8'd15: bram_delay <= bram_delay + 8'b1;

            8'd16: begin
              feature_buffer[255:224] <= bram_dout;
              bram_addr <= bram_addr + 9'b1;
              feature_set_done <= 1'b1;
              bram_delay <= 8'b0;
            end
          endcase
        end
      end

      // reads biases from BRAM
      // and sets biases on register bram_buffer
      // since 1 bias value is needed for  1 partial sum: [W0 * I0 + ... + W(INPUTSIZE-1)*I(INPUT_SIZE-1)]
      // it is able to use 1 line of bias(4 biases) for 4 cycle while using bias_pointer
      STATE_SET_BIAS: begin
        if(bias_set_done) begin
          bram_en <= 1'b0;
          bram_we <= 1'b0;
          bram_bias_tmp_addr <= bram_addr;
          bias_set_done <= 1'b0;
          if (bias_counter >= BIAS_SIZE) begin
            // last bias is set
            bram_state <= STATE_IDLE;
          end
          else begin
            bram_state <= STATE_RECEIVE_WEIGHT;
          end
        end
        else begin
          case(bram_delay)
            8'd0: begin
              bram_en <= 1'b1;
              bram_we <= 1'b0;
              bram_addr <= bram_bias_tmp_addr;
              bram_delay <= bram_delay + 8'b1;
            end

            8'd1: bram_delay <= bram_delay + 8'b1;

            8'd2: begin
              // single bias is needed for one output
              bias_buffer <= bram_dout[(8 * (bias_pointer + 1) - 1)-:8];
              bram_delay <= bram_delay + 8'b1;
            end

            8'd3: begin
              bram_delay <= 8'b0;
              bias_set_done <= 1'b1;
              if (bias_pointer == 4'd3) begin
                bias_pointer <= 4'b0000;
                bram_addr <= bram_addr + 9'b1;
              end
              else begin
                bias_pointer <= bias_pointer + 4'b1;
              end
            end
          endcase
        end
      end
    endcase
  end
end

// Calculate operation
always @(posedge clk or negedge rstn) begin
  if (!rstn) begin
    cal_state <= STATE_IDLE;
    acc_en <= 1'b0;
    acc_counter <= {8{1'b0}};
    acc_32_done <= 1'b0;
    acc_delay <= 4'b0;
    partial_sum_counter <= {8{1'b0}};
    partial_sum_done <= 1'b0;
    add_bias_done <= 1'b0;
    relu_done <= 1'b0;
    cal_done <= 1'b0;
    output_buffer <= {8{1'b0}};
    out_counter <= {8{1'b0}};

    tmp_partial_sum1[0] <= {20{1'b0}};
    tmp_partial_sum1[1] <= {20{1'b0}};
    tmp_partial_sum1[2] <= {20{1'b0}};
    tmp_partial_sum1[3] <= {20{1'b0}};
    tmp_partial_sum1[4] <= {20{1'b0}};
    tmp_partial_sum1[5] <= {20{1'b0}};
    tmp_partial_sum1[6] <= {20{1'b0}};
    tmp_partial_sum1[7] <= {20{1'b0}};

    tmp_partial_sum2[0] <= {21{1'b0}};
    tmp_partial_sum2[1] <= {21{1'b0}};
    tmp_partial_sum2[2] <= {21{1'b0}};
    tmp_partial_sum2[3] <= {21{1'b0}};

    tmp_partial_sum3[0] <= {22{1'b0}};
    tmp_partial_sum3[1] <= {22{1'b0}};

    tmp_partial_sum4[0] <= {23{1'b0}};
  end
  else begin
    case(cal_state)
      STATE_IDLE: begin
        if(feature_weight_ready) begin
          cal_state <= STATE_ACC_32;
        end
        else begin
          cal_state <= STATE_IDLE;
        end
      end

      // accumulates products of 32 features and 32 weights
      // with accumulation_32 module
      // needs to iterate [MAX_ITER_ACCUMULATION] times
      // to get each partial sum [W0 * I0 +...+  W31*I31], ... , [...+ W(INPUTSIZE-1)*I(INPUT_SIZE-1)]
      STATE_ACC_32: begin
        if (acc_32_done) begin
          acc_en <= 1'b0;
          acc_counter <= 8'b0;
          cal_state <= STATE_PARTIAL_SUM;
        end
        else begin
          if (acc_done) begin
            acc_en <= 1'b0;
            tmp_partial_sum1[acc_counter] <= acc_result;
            if (acc_counter >= MAX_ITER_ACCUMULATION - 1) begin
              acc_32_done <= 1'b1;
            end
            else begin
              if (acc_delay == 4'b0) begin
                acc_delay <= acc_delay + 4'b1;
              end
              else if(acc_delay == 4'b1) begin
                acc_counter <= acc_counter + 8'b1;
                acc_delay <= 4'b0;
              end
            end
          end
          else begin
            acc_en <= 1'b1;  
          end
        end
      end

      // sums up every result from accumulation_32 module
      // to get [W0 * I0 + ... + W(INPUTSIZE-1)*I(INPUT_SIZE-1)]
      STATE_PARTIAL_SUM: begin
        if (partial_sum_done) begin
          partial_sum_counter <= 8'b0;  
          cal_state <= STATE_ADD_BIAS;
        end
        else begin
          acc_32_done <= 1'b0;
          if (partial_sum_counter == 0) begin
          // refactoring is needed to parameterize
            tmp_partial_sum2[0] <= tmp_partial_sum1[0] + tmp_partial_sum1[1];
            tmp_partial_sum2[1] <= tmp_partial_sum1[2] + tmp_partial_sum1[3];
            tmp_partial_sum2[2] <= tmp_partial_sum1[4] + tmp_partial_sum1[5];
            tmp_partial_sum2[3] <= tmp_partial_sum1[6] + tmp_partial_sum1[7];
            partial_sum_counter <= partial_sum_counter + 8'b1;
          end
          else if (partial_sum_counter == 8'd1) begin
            tmp_partial_sum3[0] <= tmp_partial_sum2[0] + tmp_partial_sum2[1];
            tmp_partial_sum3[1] <= tmp_partial_sum2[2] + tmp_partial_sum2[3];
            partial_sum_counter <= partial_sum_counter + 8'b1;
          end
          else if (partial_sum_counter == 8'd2) begin
            tmp_partial_sum4[0] <= tmp_partial_sum3[0] + tmp_partial_sum3[1];
            partial_sum_done <= 1'b1;
          end
        end
      end

      // adds up bias to partial sum and quantize
      // qunatization steps
      // 1. check overflow
      // 2. check sign, whether it is posivie or negative
      // 3. take sign bit and [12:6] bits.
      STATE_ADD_BIAS: begin
        if(add_bias_done) begin
          add_bias_done <= 1'b0;
          output_buffer <= {8{1'b0}};
          cal_state <= STATE_IDLE;
          if (out_counter >= OUTPUT_SIZE) begin
            cal_done <= 1'b1;
          end
        end
        else begin
        // refactoring is needed for quantization
          partial_sum_done <= 1'b0;
          tmp_output[out_counter] <= tmp_partial_sum4[0] + bias_buffer;
          if (tmp_output[out_counter][23:12] == {12{1'b1}} || tmp_output[out_counter][23:12] == {12{1'b0}})  begin
            output_buffer[7] <= tmp_output[out_counter][24];
            output_buffer[6:0] <= tmp_output[out_counter][12:6];
            out_counter <= out_counter + 8'b1;
            add_bias_done <= 1'b1;
          end
          else if (tmp_output[out_counter][24] == 1'b1) begin
            // negative Overflow
            output_buffer <= 8'b1000_0000;
            out_counter <= out_counter + 8'b1;
            add_bias_done <= 1'b1;
          end
          else begin
            // positive Overflow
            output_buffer <= 8'b0111_1111;
            out_counter <= out_counter + 8'b1;
            add_bias_done <= 1'b1;
          end         
        end
      end

    endcase
  end
end
endmodule
