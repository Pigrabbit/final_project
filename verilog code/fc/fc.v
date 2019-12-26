module fc #
 (
      parameter integer C_S00_AXIS_TDATA_WIDTH   = 32,
      parameter integer BYTE_SIZE = 8,
      parameter integer MAX_INPUT_SIZE = 1568,
      parameter integer MAX_OUTPUT_SIZE = 256,
      parameter integer MAX_PARTIAL_SUM_BITWIDTH = 26
      // parameter integer INPUT_SIZE = 256,
      // parameter integer OUTPUT_SIZE = 10
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
    output reg [31:0]                                     max_index, // Only for last fully connected layer. It has same functionality with softmax. If output size is 10, max_inde indicate index of value which is largest of 10 outputs.
    output reg                                            fc_done,

    // for debugging
    output reg [15:0]                                     iter,
    output reg [31:0]                                     output_debug,

    // design reference from module_example
    input wire [31:0]   input_size_external,
    input wire [31:0]   output_size_external,
    input wire [2:0]    COMMAND,
    // input wire [20:0]   receive_size,
    output reg F_writedone,
    output reg W_writedone,
    output reg B_writedone,
    output reg cal_done,
    input wire relu
  );


// localparam integer BIAS_SIZE = OUTPUT_SIZE;
// localparam integer WEIGHT_SIZE = INPUT_SIZE * OUTPUT_SIZE;
// localparam integer MAX_ITER_ACCUMULATION = INPUT_SIZE >> 5;
localparam integer ACC_32_OUT_BITWIDTH = 20;
// localparam integer PARTIAL_SUM_BITWIDTH = ACC_32_OUT_BITWIDTH + $clog2(MAX_ITER_ACCUMULATION);
// localparam integer MAC_PARTIAL_SUM_ACC_B_BITWIDTH = PARTIAL_SUM_BITWIDTH - ACC_32_OUT_BITWIDTH + 1;
// localparam integer MAC_BIAS_ADDER_B_BITWIDTH = PARTIAL_SUM_BITWIDTH - BYTE_SIZE + 1;
localparam integer MAC_PARTIAL_SUM_ACC_B_BITWIDTH = 2;
localparam integer MAC_BIAS_ADDER_B_BITWIDTH = 8;

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

reg   [31:0]  input_size;
reg   [31:0]  output_size;
reg   [31:0]  bias_size;
reg   [31:0]  weight_size;
reg   [31:0]  max_iter_accumulation;
reg   [31:0]  acc_32_out_bitwidth;
reg   [31:0]  partial_sum_bitwidth;
reg   [31:0]  mac_partial_sum_acc_b_bitwidth;
reg   [31:0]  mac_bias_adder_b_bitwidth;

reg   [31:0]  input_number_of_line;
reg   [31:0]  output_number_of_line;
reg   [31:0]  bias_number_of_line;

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

// MAC accumulation_32 In/Out
reg           acc_en;
wire          acc_done;
reg   [3:0]   acc_delay;
wire  [19:0]  acc_result;         
reg   [255:0] feature_buffer;
reg   [255:0] weight_buffer;
reg signed  [7:0]   bias_buffer;
reg signed  [7:0]   output_buffer [0:MAX_OUTPUT_SIZE-1]; // define array size as MAX_OUT_SIZE

reg   [3:0]   cal_state;
reg   [7:0]   acc_counter;
reg   [15:0]   feature_counter;    
reg   [7:0]   weight_counter;
reg   [7:0]   bias_counter;
reg   [3:0]   bias_pointer;   
reg   [15:0]   out_counter;
reg   [7:0]   partial_sum_counter;
// reg   [15:0]   iter;

// partial sum buffer
reg signed [19:0]  tmp_partial_sum [0:48]; // INPUT:256 --> [0:7], INPUT:1024 --> [0:31], INPUT: 1568 --> [0:48]

// MAC partial sum accumulator signal
reg                                           partial_sum_acc_en;
reg   [19:0]                                  partial_sum_acc_data_a;
reg   [MAC_PARTIAL_SUM_ACC_B_BITWIDTH-1:0]    partial_sum_acc_data_b;
reg   [MAX_PARTIAL_SUM_BITWIDTH-1:0]          partial_sum_acc_data_c;  // INPUT:256 --> 20-bits 8 numbers are summed up. 20 + log_2(8) = 23
wire  [MAX_PARTIAL_SUM_BITWIDTH-1:0]          partial_sum_acc_out;     // INPUT:1024 --> 20-bits 32 numbers are summed up. 20+ log_2(32) = 25
wire                                          partial_sum_acc_done;

// MAC bias adder signal
reg                                     bias_adder_en;
reg   [7:0]                             bias_adder_data_a;  // BIAS_SIZE
reg   [MAC_BIAS_ADDER_B_BITWIDTH-1:0]   bias_adder_data_b;  // to meet data_c size: data_c_length - data_a_length + 1
reg   [MAX_PARTIAL_SUM_BITWIDTH-1:0]    bias_adder_data_c;   
wire  [MAX_PARTIAL_SUM_BITWIDTH:0]      bias_adder_out;
wire                                    bias_adder_done;

// control signals
reg         feature_set_done;
reg         bias_set_done;
reg         partial_sum_done;
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

accumulation_32 u_accumulation_32 (
  .clk(clk),
  .rstn(rstn),
  .en(acc_en),
  .done(acc_done),
  .feature(feature_buffer),
  .weight(weight_buffer),
  .result(acc_result)
);


// A_BITWIDTH is fixed to 20-bit
// B_BITWIDTH is related to difference between OUT_BITWIDTH and A_BITWIDTH
// OUT_BITWIDTH of u_mac_partial_sum_acc needed to be parameterized
// eg INPUT_SIZE = 256
// A_BITWIDTH = 20, B_BITWIDTH = 4, OUT_BITWIDTH = 24
mac_fc #(.A_BITWIDTH(ACC_32_OUT_BITWIDTH), .B_BITWIDTH(MAC_PARTIAL_SUM_ACC_B_BITWIDTH), .OUT_BITWIDTH(MAX_PARTIAL_SUM_BITWIDTH + 1))
  u_mac_partial_sum_acc (
    .clk(clk),
    .rstn(rstn),
    .en(partial_sum_acc_en),
    .data_a(partial_sum_acc_data_a),
    .data_b(partial_sum_acc_data_b),
    .data_c(partial_sum_acc_data_c),
    .mout(partial_sum_acc_out),
    .done(partial_sum_acc_done)
  );

// A_BITWIDTH is fixed to BIAS_SIZE
// B_BITWIDTH is realted to difference between OUT_BITWIDTH and A_BITWIDTH
// OUT_BITWIDTH is related to MAX_ITER_ACCUMULATION
mac_fc #(.A_BITWIDTH(BYTE_SIZE), .B_BITWIDTH(MAC_BIAS_ADDER_B_BITWIDTH), .OUT_BITWIDTH(MAX_PARTIAL_SUM_BITWIDTH + 1))
  u_mac_bias_adder (
    .clk(clk),
    .rstn(rstn),
    .en(bias_adder_en),
    .data_a(bias_adder_data_a),
    .data_b(bias_adder_data_b),
    .data_c(bias_adder_data_c),
    .mout(bias_adder_out),
    .done(bias_adder_done)
);

// buffering external signals
always @(posedge clk or negedge rstn) begin
  if(!rstn) begin
    input_size <= 32'b0;
    output_size <= 32'b0;
    bias_size <= 32'b0;
    weight_size <= 32'b0;
    max_iter_accumulation <= 32'b0;
    acc_32_out_bitwidth <= 32'b0;
    partial_sum_bitwidth <= 32'b0;
    mac_partial_sum_acc_b_bitwidth <= 32'b0;
    mac_bias_adder_b_bitwidth <= 32'b0;
  end
  else begin
    input_size <= input_size_external;
    output_size <= output_size_external;
    bias_size <= output_size_external;
    weight_size <= input_size_external * output_size_external;
    max_iter_accumulation <= input_size_external >> 5;
    acc_32_out_bitwidth <= 32'd20;
    // partial_sum_bitwidth <= 32'd20 + $clog2(input_size_external >> 5);
    // mac_partial_sum_acc_b_bitwidth <= 32'd20 + $clog2(input_size_external >> 5) - 19;
    // mac_bias_adder_b_bitwidth <= 32'd20 + $clog2(input_size_external >> 5) - 7;
    
    set_input_number_of_line(input_size, input_number_of_line);
    set_output_number_of_line(output_size, output_number_of_line);
    set_bias_number_of_line(bias_size, bias_number_of_line);
    set_partial_sum_bitwidth(input_size_external, partial_sum_bitwidth);
  end
end

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
    feature_counter <= {16{1'b0}};
    bias_counter <= {8{1'b0}};
    bias_pointer <= {3{1'b0}};
    feature_buffer <= {255{1'b0}};
    weight_buffer <= {255{1'b0}};
    bias_buffer <= {8{1'b0}};
  end
  else begin
    case(bram_state)
      STATE_IDLE: begin
        if(fc_start && S_AXIS_TVALID) begin
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
        else if(!S_AXIS_TVALID) begin
          bram_en <= 1'b0;
          bram_we <= 1'b0;
          if (S_AXIS_TLAST && feature_counter >= input_number_of_line) begin
            feature_counter <= 16'b0;
            F_writedone <= 1'b1;
          end
        end
        else begin
          s_axis_tready <= 1'b1;
          bram_en <= 1'b1;
          bram_we <= 1'b1;
          bram_din <= S_AXIS_TDATA;
          if(feature_counter == 0) begin
            bram_addr <= FEATURE_START_ADDRESS;  
            feature_counter <= feature_counter + 16'b1;
          end
          else if (S_AXIS_TLAST && feature_counter >= input_number_of_line) begin
            feature_counter <= 16'b0;
            F_writedone <= 1'b1;
          end
          else begin
            feature_counter <= feature_counter + 16'b1;
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
        else if(F_writedone) begin
          F_writedone <= 1'b0;
          s_axis_tready <= 1'b1;
        end
        else if(!S_AXIS_TVALID) begin
          bram_en <= 1'b0;
          bram_we <= 1'b0;
          if (S_AXIS_TLAST && bias_counter >= bias_number_of_line) begin
            bias_counter <= 4'b0;
            B_writedone <= 1'b1;
          end
        end
        else begin
          bram_en <= 1'b1;
          bram_we <= 1'b1;
          bram_din <= S_AXIS_TDATA;
          if (bias_counter == 0) begin
            bram_addr <= BIAS_START_ADDRESS;
            bias_counter <= bias_counter + 8'b1;  
          end
          else if(S_AXIS_TLAST && bias_counter >= bias_number_of_line) begin
            bias_counter <= {4{1'b0}};
            B_writedone <= 1'b1;
          end
          else begin
            bram_addr <= bram_addr + 9'b1;
            bias_counter <= bias_counter + 8'b1;
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
          weight_counter <= 8'b0;
          bram_state <= STATE_SET_FEATURE;
        end
        else begin 
          if (weight_counter == 8'd0) begin
            B_writedone <= 1'b0;
            feature_weight_ready <= 1'b0;
            s_axis_tready <= 1'b1;
            weight_counter <= weight_counter + 8'b1;  
          end
          else if (weight_counter > 8'd8) begin 
            W_writedone <= 1'b1;
          end
          else begin
            weight_buffer <= weight_buffer >> 32;
            weight_buffer[255-:32] <= S_AXIS_TDATA;
            if(weight_counter == 8'd8) begin
              s_axis_tready <= 1'b0;  
            end
            weight_counter <= weight_counter + 8'b1;
          end
        end
      end

      // reads features from BRAM
      // and sets features on register feature_buffer
      // these features are going to be calculated in [accumulation_32] module
      // BRAM read operation needs delay
      // when setting feature is done, 
      // state changes to RECEIVE_WEIGHT, if summing up to MAX_ITER_ACCUMULATION(INPUT_SIZE/32) is not done
      // state changes to SET_BIAS, if it is done
      STATE_SET_FEATURE: begin
        if(feature_set_done) begin
          bram_en <= 1'b0;
          bram_we <= 1'b0;
          feature_weight_ready <= 1'b1;
          bram_feature_tmp_addr <= bram_addr;
          if (acc_done && acc_counter >= max_iter_accumulation - 1) begin
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
              if (bram_feature_tmp_addr >= input_number_of_line) begin
                bram_addr <= FEATURE_START_ADDRESS;
              end
              else begin
                bram_addr <= bram_feature_tmp_addr;  
              end
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
          if (out_counter >= output_size) begin
            //bias_counter >= BIAS_SIZE
            // last bias is set
            bram_state <= STATE_IDLE;
          end
          else if (cal_state == STATE_IDLE) begin
            bram_state <= STATE_RECEIVE_WEIGHT;
          end
        end
        else begin
          case(bram_delay)
            8'd0: begin
              feature_weight_ready <= 1'b0;
              bram_en <= 1'b1;
              bram_we <= 1'b0;
              if (bram_bias_tmp_addr >= BIAS_START_ADDRESS + output_number_of_line)  begin
                bram_addr <= BIAS_START_ADDRESS;
              end
              else begin
                bram_addr <= bram_bias_tmp_addr;
              end
              bram_delay <= bram_delay + 8'b1;
            end

            8'd1: bram_delay <= bram_delay + 8'b1;

            8'd2: begin
              // single bias is needed for one output
              bias_buffer <= bram_dout[(8 * (bias_pointer + 1) - 1)-:8];
              bram_delay <= bram_delay + 8'b1;
            end

            8'd3: begin
              if(cal_state == STATE_IDLE || cal_state == STATE_DATA_SEND) begin
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

    for(iter = 0; iter < 16'd256; iter = iter + 1) begin
      output_buffer[iter] <= 8'b0;
    end

    acc_en <= 1'b0;
    acc_counter <= {8{1'b0}};
    acc_32_done <= 1'b0;
    acc_delay <= 4'b0;

    partial_sum_counter <= {8{1'b0}};
    partial_sum_done <= 1'b0;
    add_bias_done <= 1'b0;
    cal_done <= 1'b0;
    fc_done <= 1'b0;
    out_counter <= {16{1'b0}};
    iter <= 16'b0;
    output_debug <= 32'b0;
    max_index <= 32'b0;

    partial_sum_acc_en <= 1'b0;
    partial_sum_acc_data_a <= {ACC_32_OUT_BITWIDTH{1'b0}};
    partial_sum_acc_data_b <= {MAC_PARTIAL_SUM_ACC_B_BITWIDTH{1'b0}};
    partial_sum_acc_data_c <= {MAX_PARTIAL_SUM_BITWIDTH{1'b0}};

    bias_adder_en <= 1'b0;
    bias_adder_data_a <= {8{1'b0}};  // BIAS_SIZE
    bias_adder_data_b <= {MAC_BIAS_ADDER_B_BITWIDTH{1'b0}}; // difference between OUT_BITWIDTH and A_BITWIDTH
    bias_adder_data_c <= {MAX_PARTIAL_SUM_BITWIDTH{1'b0}}; //  OUT_BITWIDTH is related to MAX_ITER_ACCUMULATION
  end
  else begin
    case(cal_state)
      STATE_IDLE: begin
        if(feature_weight_ready && out_counter < output_size) begin
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
            tmp_partial_sum[acc_counter] <= acc_result;
            if (acc_counter >= max_iter_accumulation - 1) begin
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
          else if(feature_weight_ready)begin
            acc_en <= 1'b1;  
          end
        end
      end

      // sums up every result from accumulation_32 module
      // to get [W0 * I0 + ... + W(INPUTSIZE-1)*I(INPUT_SIZE-1)]
      STATE_PARTIAL_SUM: begin
        if (partial_sum_done && partial_sum_counter > max_iter_accumulation) begin
          partial_sum_acc_en <= 1'b0;
          partial_sum_counter <= 8'b0;  
          cal_state <= STATE_ADD_BIAS;
        end
        else begin
          if (partial_sum_counter == 8'd0) begin
            acc_32_done <= 1'b0;
            partial_sum_acc_en <= 1'b1;

            partial_sum_acc_data_a <= tmp_partial_sum[partial_sum_counter];
            partial_sum_acc_data_b <= 2'b01;                               // need to parameterize
            partial_sum_acc_data_c <= {MAX_PARTIAL_SUM_BITWIDTH{1'b0}};

            partial_sum_counter <= partial_sum_counter + 8'b1;
          end
          else if (partial_sum_acc_done) begin
            partial_sum_acc_data_a <= tmp_partial_sum[partial_sum_counter];
            partial_sum_acc_data_b <= 2'b01;                               // need to parameterize
            partial_sum_acc_data_c <= partial_sum_acc_out;

            if (partial_sum_counter == max_iter_accumulation) begin
              partial_sum_done <= 1'b1;
              partial_sum_counter <= partial_sum_counter + 8'b1;
            end
            else begin
              partial_sum_counter <= partial_sum_counter + 8'b1;  
            end
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
          // if output_size = 10
          // set max_index
          if (output_size == 32'd10) begin
            set_max_index(max_index);
          end

          if (out_counter >= output_size) begin
            // out_counter <= {8{1'b0}};
            cal_done <= 1'b1;
            if (COMMAND == 3'b101) begin
              output_debug <= {output_buffer[3], output_buffer[2] ,output_buffer[1], output_buffer[0]};
              add_bias_done <= 1'b0;
              cal_state <= STATE_DATA_SEND;
            end
          end
          else begin
            add_bias_done <= 1'b0;
            cal_state <= STATE_IDLE;
          end
        end
        else begin
        // refactoring is needed for quantization
          partial_sum_done <= 1'b0;
          if (bias_adder_done) begin
            bias_adder_en <= 1'b0;
            if (bias_adder_out[MAX_PARTIAL_SUM_BITWIDTH-1:13] == {MAX_PARTIAL_SUM_BITWIDTH{1'b0}})  begin
            // positive and not OF
              output_buffer[out_counter] <= {bias_adder_out[partial_sum_bitwidth], bias_adder_out[12:6]};  
              out_counter <= out_counter + 16'b1;
              add_bias_done <= 1'b1;
            end
            else if(bias_adder_out[MAX_PARTIAL_SUM_BITWIDTH-1:13] == {(MAX_PARTIAL_SUM_BITWIDTH-13){1'b1}}) begin
            // negative and not OF
              if (relu) begin
                if (bias_adder_out[partial_sum_bitwidth] == 1'b1) begin
                  output_buffer[out_counter] <= {8{1'b0}};
                end
                else begin
                  output_buffer[out_counter] <= {bias_adder_out[partial_sum_bitwidth], bias_adder_out[12:6] + 1'b1};  
                end  
              end
              else begin
                output_buffer[out_counter] <= {bias_adder_out[partial_sum_bitwidth], bias_adder_out[12:6] + 1'b1};  
              end
              out_counter <= out_counter + 16'b1;
              add_bias_done <= 1'b1;
            end
            else if (bias_adder_out[partial_sum_bitwidth] == 1'b1) begin
            // negative and Overflow
              if (relu) begin
                output_buffer[out_counter] <= 8'b0000_0000;
              end
              else begin
                output_buffer[out_counter] <= 8'b1000_0000;
              end
              out_counter <= out_counter + 16'b1;
              add_bias_done <= 1'b1;
            end
            else if(bias_adder_out[partial_sum_bitwidth] == 1'b0) begin
            // positive and Overflow
              output_buffer[out_counter] <= 8'b0111_1111;
              out_counter <= out_counter + 16'b1;
              add_bias_done <= 1'b1;
            end 
            else begin
              output_buffer[out_counter] <= 8'b0000_0000;
              out_counter <= out_counter + 16'b1;
              add_bias_done <= 1'b1;
            end 
          end
          else begin
            bias_adder_en <= 1'b1;
            bias_adder_data_a <= bias_buffer;
            bias_adder_data_b <= 8'b0100_0000; // need to parameterize
            bias_adder_data_c <= partial_sum_acc_out;
          end     
        end
      end
      
      STATE_DATA_SEND: begin
        if (iter >= output_number_of_line) begin
          if (M_AXIS_TLAST)  begin
            // tlast fall
            m_axis_tlast <= 1'b0;
            m_axis_tvalid <= 1'b0;
            m_axis_tdata <= 32'b0;  
          end
          else if (COMMAND == 3'b000) begin
            cal_state <= STATE_IDLE;
            fc_done <= 1'b0;
          end
          else begin
            cal_done <= 1'b0;
          end
        end
        else if (iter == output_number_of_line - 1) begin
          // tlast rise 
          m_axis_tlast <= 1'b1; 
          // fc done rise
          fc_done <= 1'b1;
          m_axis_tdata <= {output_buffer[4*iter + 3], output_buffer[4*iter + 2], output_buffer[4*iter + 1], output_buffer[4*iter]};  
          iter <= iter + 16'b1;
        end
        else if (M_AXIS_TREADY) begin
          m_axis_tvalid <= 1'b1;
          m_axis_tdata <= {output_buffer[4*iter + 3], output_buffer[4*iter + 2], output_buffer[4*iter + 1], output_buffer[4*iter]};  
          iter <= iter + 16'b1;
        end
      end

    endcase
  end
end

  //-----------------------
  //******** Task ********
  //-----------------------

  task set_input_number_of_line (input [31:0] number_of_input, output [31:0] number_of_line);
    begin
      number_of_line = number_of_input >> 2;
    end
  endtask

  task set_output_number_of_line (input [31:0] number_of_output, output [31:0] number_of_line);
    begin
      if (output_size == 32'd10) begin
        number_of_line = (number_of_output >> 2) + 1;
      end
      else begin
        number_of_line = number_of_output >> 2;
      end
    end
  endtask

  task set_bias_number_of_line (input [31:0] number_of_bias, output [31:0] number_of_line);
    begin
      if (number_of_bias == 32'd10) begin
        number_of_line = (number_of_bias >> 2) + 1;
      end
      else begin
        number_of_line = number_of_bias >> 2;
      end
    end
  endtask

  task set_partial_sum_bitwidth (input [31:0] input_size, output [31:0] partial_sum_bitwidth);
    begin
    // possible input size:          1568, 1024, 256, 64
    // possible partial_sum_bitwidth:   26,   25,  23, 21 
      if (input_size > 32'd1024) begin
        partial_sum_bitwidth = 32'd26;
      end
      else if (input_size > 32'd512) begin
        partial_sum_bitwidth = 32'd25;
      end
      else if (input_size > 32'd256) begin
        partial_sum_bitwidth = 32'd24;
      end
      else if (input_size > 32'd128) begin
        partial_sum_bitwidth = 32'd23;
      end
      else if (input_size > 32'd64)  begin
        partial_sum_bitwidth = 32'd22;
      end
      else if (input_size > 32'd32)  begin
        partial_sum_bitwidth = 32'd21;
      end
    end
  endtask

  task set_max_index(output [31:0] max_index);
    begin: sort
      reg [31:0] tmp_max_index;
      reg [3:0]  i;
      tmp_max_index = 32'd0;
      for (i = 1; i < 10; i = i + 1) begin
        if (output_buffer[i] > output_buffer[tmp_max_index]) begin
          tmp_max_index = i;
        end
      end
      max_index = tmp_max_index;
    end
  endtask
  //-------------------------------
  //-------------------------------
endmodule
