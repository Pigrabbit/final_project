module fc #
 (
      parameter integer C_S00_AXIS_TDATA_WIDTH   = 32

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
localparam STATE_IDLE = 3'b000;
localparam STATE_READ_FEATURE = 3'b001;
localparam STATE_READ_BIAS = 3'b010;
localparam STATE_READ_WEIGHT = 3'b011;
localparam STATE_ACC = 3'b100;
localparam STATE_DATA_SEND = 3'b101;

// localparam FEATURE_START_ADDRESS = 12'b000_0000_0000; // 64개 64 = 010_00000
// localparam BIAS_START_ADDRESS = 12'b0000_0010_0000;    // 16개
localparam WEIGHT_START_ADDRESS = 12'b0000_0000_0000;  // 256*16개

// BRAM In/Out
reg bram_en;
reg bram_we;
reg [11:0] bram_addr;
reg [31:0] bram_din;
wire [31:0] bram_dout;

// MAC In/Out
reg mac_en [0:31];
reg [7:0] mac_data_a_mul [0:31];
reg [7:0] mac_data_b_mul [0:31];
reg [16:0] mac_data_c_mul;
wire [17:0] mac_result_mul [0:31];
wire mac_done_mul;

reg [31:0]  feature [63:0];
reg [31:0]  bias [15:0];
reg [2:0]   fc_state;
reg [3:0]   bram_counter; // need to be parameterized
reg [15:0]  weight_counter;
reg [7:0]   iter;
reg [1:0]   delay;

reg acc_done;
reg [63:0] feature_buffer;
reg [63:0] weight_buffer;

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

sram_32x4096 u_sram_32x4096(
    .addra(bram_addr),
    .clka(clk),
    .dina(bram_din),
    .douta(bram_dout),
    .ena(bram_en),
    .wea(bram_we)
);

// generate 써서 하자.
mac_fc #(.A_BITWIDTH(8), .OUT_BITWIDTH(18))
  u_mac_fc_mul[0:31] (
    .clk(clk),
    .en(mac_en[0]),
    .rstn(rstn),
    .data_a(mac_data_a_mul[0]), 
    .data_b(mac_data_b_mul[0]),
    .data_c(mac_data_c_mul),
    .mout(mac_result_mul[0]),
    .done(mac_done_mul)
  );

  // Control path
  always @(posedge clk or negedge rstn) begin
    if(!rstn) begin
      fc_state <= STATE_IDLE;
    end
    else begin
      case(fc_state)
        STATE_IDLE: begin
          if (S_AXIS_TVALID && fc_start) begin
            fc_state <= STATE_READ_FEATURE;
          end
          else begin
            fc_state <= STATE_IDLE;
          end
        end

        STATE_READ_FEATURE: begin
          if (F_writedone && COMMAND == 3'b010) begin
            fc_state <= STATE_READ_BIAS;
          end
        end

        STATE_READ_BIAS: begin
          if (B_writedone && COMMAND == 3'b100) begin
            fc_state <= STATE_READ_WEIGHT;
          end
        end

        STATE_READ_WEIGHT: begin
          if (weight_counter == 16'd512) begin // need to be parameterized
            fc_state <= STATE_ACC;
          end
        end

        STATE_ACC: begin
          if (acc_done) begin
            fc_state <= STATE_DATA_SEND;
          end
        end

        STATE_DATA_SEND: begin
          if (fc_done) fc_state <=STATE_IDLE;
          else begin
            
          end
        end
        default: ; 
      endcase
    end
  end

  // Data path
always @(posedge clk or negedge rstn) begin
    if(!rstn) begin
      s_axis_tready <= 1'b0;
      m_axis_tuser <= 1'b0;
      m_axis_tdata <= {32{1'b0}};
      m_axis_tkeep <= {4{1'b0}};
      m_axis_tlast <= 1'b0; 
      m_axis_tvalid <= 1'b0;

      bram_en <= 1'b0;
      bram_we <= 1'b0;
      bram_addr <= 12'b1111_1111_1111;
      bram_din <= {32{1'b0}};

      mac_en[0] <= 1'b0;
      mac_data_a_mul[0] <= {8{1'b0}};
      mac_data_b_mul[0] <= {8{1'b0}};
      mac_data_c_mul <= {17{1'b0}};

      F_writedone <= 1'b0;
      B_writedone <= 1'b0;
      W_writedone <= 1'b0;
      cal_done <= 1'b0;

      bram_counter <= {4{1'b0}};
      weight_counter <= {16{1'b0}};
      iter <= {8{1'b0}};
      delay <= 2'b00;
    end
    else begin
      case(fc_state)
        STATE_IDLE: begin
          if(fc_start) begin
            s_axis_tready <= 1'b1;
          end
        end

        STATE_READ_FEATURE: begin
          if(iter == 8'd64) begin // need to be parameterized
            F_writedone <= 1'b1;
            s_axis_tready <= 1'b0;
            iter <= {8{1'b1}};
          end
          else if (F_writedone != 1'b1) begin
            feature[iter] <= {S_AXIS_TDATA[31:24], S_AXIS_TDATA[23:16], S_AXIS_TDATA[15:8], S_AXIS_TDATA[7:0]};
            iter <= iter + 1'b1;
          end
        end

        STATE_READ_BIAS: begin
          F_writedone <= 1'b0;
          if(iter == 8'd16) begin // need to be parameterized
            B_writedone <= 1'b1;
            s_axis_tready <= 1'b0;
            iter <= {8{1'b0}};  
          end
          else if (B_writedone != 1'b1) begin
            s_axis_tready <= 1'b1;
            bias[iter] <= {S_AXIS_TDATA[31:24], S_AXIS_TDATA[23:16], S_AXIS_TDATA[15:8], S_AXIS_TDATA[7:0]};
            iter <= iter + 1'b1;
          end
        end

        STATE_READ_WEIGHT: begin
          B_writedone <= 1'b0;
          if (W_writedone && weight_counter >= 512) begin
            // weight 256*64 개를 전부 읽어온 단계
            s_axis_tready <= 1'b0;
            bram_en <= 1'b0;
            bram_we <= 1'b0;
            bram_addr <= {12{1'b1}};
            bram_counter <= {4{1'b0}};
            bram_din <= {32{1'b0}};
            W_writedone <= 1'b0;
            delay <= 2'b00;
          end
          else if (W_writedone && weight_counter < 512) begin
            // weight 한 set(32개)를 가져온 상태
            W_writedone <= 1'b0;
            s_axis_tready <= 1'b1;
          end
          else begin
            if (S_AXIS_TVALID) begin
              s_axis_tready <= 1'b1;
              
              bram_en <= 1'b1;
              bram_we <= 1'b1;
              bram_din <= {S_AXIS_TDATA[31:24], S_AXIS_TDATA[23:16], S_AXIS_TDATA[15:8], S_AXIS_TDATA[7:0]};
        
              if (bram_counter == 0 && weight_counter == 0) begin
                bram_addr <= WEIGHT_START_ADDRESS;
                bram_counter <= bram_counter + 4'b1;
              end
              else if (bram_counter == 4'd7) begin
                W_writedone <= 1'b1;
                weight_counter <= weight_counter + 16'b1;
                s_axis_tready <= 1'b0;
                bram_counter <= 4'b0;
                bram_addr <= bram_addr + 12'b1;
              end
              else if (delay == 2'b00) begin
                delay <= delay + 2'b1;
              end
              else begin
                bram_addr <= bram_addr + 12'b1;
                bram_counter <= bram_counter + 4'b1;
              end
            end
            else begin
              bram_en <= 1'b0;
              bram_we <= 1'b0;
              // bram_addr <= {12{1'b1}};
              bram_din <= {32{1'b0}};
            end
          end
        end
        
        STATE_ACC: begin
          bram_en <= 1'b1;
          bram_we <= 1'b0;
          if (iter == 0 && delay == 2'b00) begin
            bram_addr <= 12'b0;  
          end
          feature_buffer[31:0] <= {feature[0][31:24], feature[0][23:16], feature[0][15:8], feature[0][7:0]};
          feature_buffer[63:32] <= {feature[1][31:24], feature[1][23:16], feature[1][15:8], feature[1][7:0]};
          if (delay == 2'b00) begin
            delay <= delay + 2'b1;
          end
          else if (delay == 2'b01) begin
            weight_buffer[31:0] <= {bram_dout[31:24], bram_dout[23:16], bram_dout[15:8], bram_dout[7:0]};
            bram_addr <= bram_addr + 12'b1;
            delay <= delay + 2'b01;
          end
          else if (delay == 2'b10) begin
            delay <= delay + 2'b01;
          end
          else if (delay == 2'b11) begin
            weight_buffer[63:32] <= {bram_dout[31:24], bram_dout[23:16], bram_dout[15:8], bram_dout[7:0]};
            bram_addr <= bram_addr + 12'b1;
            delay <= delay + 2'b01;
            iter <= iter + 1;
            bram_en <= 1'b0;
            acc_done <= 1'b1;
          end
        end

        STATE_DATA_SEND: begin
          
        end
      endcase
    end
  end
endmodule
