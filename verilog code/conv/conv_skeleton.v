module conv #(
  parameter integer C_S00_AXIS_TDATA_WIDTH    = 32,
  parameter integer MAXIMUM_FEATURE_SIZE      = 32*16*16, //5+4+4=13
  parameter integer MAXIMUM_BIAS_SIZE         = 256,
  parameter integer MAXIMUM_WEIGHT_SIZE       = 256 * 3*3 *256
)(   //AXI-STREAM
  input wire                                            clk,
  input wire                                            rstn,
  
  output wire                                           S_AXIS_TREADY,
  
  input wire [C_S00_AXIS_TDATA_WIDTH-1 : 0]             S_AXIS_TDATA,
  input wire [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0]         S_AXIS_TKEEP,
  input wire                                            S_AXIS_TUSER,
  input wire                                            S_AXIS_TLAST,
  input wire                                            S_AXIS_TVALID,

  input wire                                            M_AXIS_TREADY,
  
  output wire                                           M_AXIS_TUSER,
  output wire [C_S00_AXIS_TDATA_WIDTH-1 : 0]            M_AXIS_TDATA,
  output wire [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0]        M_AXIS_TKEEP,
  output wire                                           M_AXIS_TLAST,
  output wire                                           M_AXIS_TVALID,
    //Control
  input wire [2:0]                                      command, // 0: IDLE 1 : read feature 2: read bias 3: read weight & calculate 4: relu & transfer
  input wire [8:0]                                      input_len_ex, //channel number
  input wire [8:0]                                      output_len_ex,
  input wire [8:0]                                      width_ex,
  output reg                                            feature_read_done,
  output reg                                            bias_read_done,
  output reg                                            weight_read_done,    
  output reg                                            conv_done
);
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

  /*TODO*/
  /*
  command = 1 
    get S_AXIS_TDATA and save it to feature DRAM
    set feature_read_done signal after writing DRAM
  command = 2 
    get S_AXIS_TDATA and save it to bias DRAM
    set feature_read_done signal after writing DRAM
  command = 3 
    get S_AXIS_TDATA and save it to weight DRAM
    set feature_read_done signal after writing DRAM        
    read weight, bias , feature
    calculate conv result
      make MAC
      compute MAC SIZE
      determine # of MAC
    RELU
    send it to M_AXIS_TDATA
    set conv_done signal after writing DRAM
  */
  /************************************************************/
  /*buffering external signal 'command' */
  reg [2:0] state;
  reg [8:0] input_len; 
  reg [8:0] output_len;
  reg [8:0] width;
  wire reset=!rstn||(state==0);  
    always @(posedge clk or negedge rstn) begin
      if(!rstn) begin
      state <=  0;
      end
      else begin
        state       <=  command;
        input_len   <=  input_len_ex;
        output_len  <=  output_len_ex;
        width       <=  width_ex;
      end
    end

  /************************************************************/
  /*feature BRAM module*/ /*MAXSIZE=32*16*16 // 13-2=11 */  /*width-height-length*/  
  reg [10:0]          feature_addr;
  reg [31:0]          feature_din;
  wire [31:0]         feature_dout;
  reg                 feature_bram_en;
  reg                 feature_we;        
    feature_bram feature_bram_32x2048(
      .addra(feature_addr),
      .clka (clk),
      .dina (feature_din),
      .douta(feature_dout),
      .ena  (feature_bram_en),
      .wea  (feature_we)
    );


  /************************************************************/
  /*bias BRAM module*/  /*MAXSIZE = 256 // 8-2=6*/
  reg [5:0]           bias_addr;
  reg [31:0]          bias_din;
  wire [31:0]         bias_dout;
  reg                 bias_bram_en;
  reg                 bias_we;        
    bias_bram bias_bram_32x64(
      .addra(bias_addr),
      .clka (clk),
      .dina (bias_din),
      .douta(bias_dout),
      .ena  (bias_bram_en),
      .wea  (bias_we)
    );

  /************************************************************/
  /*weight BRAM module*/  /*MAXSIZXE  = 256*3*3 = 2304 // 8+8+4-2=18*/  /*(out-channel, in-channel, rows, cols)*/
  reg [17:0]          weight_addr;
  reg [31:0]          weight_din;
  wire [31:0]         weight_dout;
  reg                 weight_bram_en;
  reg                 weight_we;        
    weight_bram weight_bram_32x256x9( 
      .addra(weight_addr),
      .clka (clk),
      .dina (weight_din),
      .douta(weight_dout),
      .ena  (weight_bram_en),
      .wea  (weight_we)
    );

  /************************************************************/
  /*AXI_stream Slave interface : receiving data*/
  reg [C_S00_AXIS_TDATA_WIDTH-1 : 0]  receive_buf; //31:0 , 4 of 8-bit datas
  reg [15:0] receive_cnt;//receive_buf get first data when it rises to 1
  reg last_data_received;

  /************************************************************/
  /*BRAM control*/
  reg         partial_recieve_done;
  reg [6:0]   l_div_4_count;
  reg         macready;
  reg [1:0]   delay_f;
  reg signed [7:0]  f [8:0];
  reg [15:0]  MAC_addr_f;
  reg [15:0]  MAC_addr_w;
  reg [5:0]   MAC_addr_b;
  reg [1:0]   count_w_line ;
  reg [1:0]   loc_w_line;
  reg [1:0]   loc_b;
  reg [1:0]   feature_pad;
  reg         bram_read_done;
  reg [7:0]   bias_tmp;
  reg signed [7:0]  w [8:0];
  reg MAC_available;

    always @(posedge clk or negedge rstn) begin
      if(reset) begin
        receive_buf             <=  0; 
        receive_cnt             <=  0;
        s_axis_tready           <=  0;
        last_data_received      <=  0;

        feature_addr            <=  0;
        feature_din             <=  0;
        feature_bram_en         <=  0;
        feature_we              <=  0;
        feature_read_done       <=  0;

        bias_addr               <=  0;
        bias_din                <=  0;
        bias_bram_en            <=  0;
        bias_we                 <=  0;
        bias_read_done          <=  0;

        weight_addr             <=  0;
        weight_din              <=  0;
        weight_bram_en          <=  0;
        weight_we               <=  0;
        weight_read_done        <=  0;
        partial_recieve_done    <=  0;
        l_div_4_count           <=  0;

        delay_f                 <=  0;
        loc_w_line              <=  0;
        MAC_addr_f              <=  0;
        MAC_addr_w              <=  0;
        MAC_addr_b              <=  0;
        feature_pad             <=  1;
        loc_b                   <=  0;
        bram_read_done          <=  0;

        conv_done               <=  0;

        w[0]  <=  0;  w[1]  <=  0;  w[2]  <=  0;  w[3]  <=  0;  w[4]  <=  0;  
        w[5]  <=  0;  w[6]  <=  0;  w[7]  <=  0;  w[8]  <=  0;  
      end
      else begin
        case(state)        
          /*receive feature*/
          3'b001: begin
            /*AXI_stream Slave interface : receiving feature*/
            /*Before receiving last data*/
            if( !last_data_received && !feature_read_done ) begin
              s_axis_tready <=  1;
              
              /*save input to buffer*/
              if(s_axis_tready  & S_AXIS_TVALID)  begin
                receive_buf <=  S_AXIS_TDATA;
                receive_cnt <=  receive_cnt + 1;  
              end
              if(S_AXIS_TLAST && !S_AXIS_TVALID)  begin
                  last_data_received <=  1;
              end
              /*put buffered data to BRAM*/
              if(receive_cnt  !=  0)  begin
                feature_addr      <=  receive_cnt-1;
                feature_din       <=  receive_buf;
                feature_bram_en   <=  1;
                feature_we        <=  1;
              end            
            end
            /*When we received all features*/          
            else begin
              // init all signals, set feature_read_done flag
              feature_read_done   <=  1;  
              s_axis_tready       <=  0;
              receive_buf         <=  0;  
              receive_cnt         <=  0;
              last_data_received  <=  0;
              feature_addr        <=  0;
              feature_din         <=  0;
              feature_bram_en     <=  0;
              feature_we          <=  0;                       
            end
          end
          /*receive bias*/
          3'b010: begin
            /*AXI_stream Slave interface : receiving bias*/
            /*Before receiving last data*/
            if( !last_data_received && !bias_read_done ) begin
              s_axis_tready <=  1;
              
              /*save input to buffer*/
              if(s_axis_tready  & S_AXIS_TVALID)  begin
                receive_buf <=  S_AXIS_TDATA;
                receive_cnt <=  receive_cnt + 1;  
              end
              if(S_AXIS_TLAST && !S_AXIS_TVALID)  begin
                  last_data_received <=  1;
              end
              /*put buffered data to BRAM*/
              if(receive_cnt  !=  0)  begin
                bias_addr      <=  receive_cnt-1;
                bias_din       <=  receive_buf;
                bias_bram_en   <=  1;
                bias_we        <=  1;
              end            
            end
            /*When we received all biases*/          
            else begin
              // init all signals, set bias_read_done flag
              bias_read_done      <=  1;  
              s_axis_tready       <=  0;
              receive_buf         <=  0;  
              receive_cnt         <=  0;
              last_data_received  <=  0;
              bias_addr           <=  0;
              bias_din            <=  0;
              bias_bram_en        <=  0;
              bias_we             <=  0;                       
            end
          end

          /*receive weight  & calculate it when partial receive done*/
          3'b011: begin

            /*when partial_receive done : Calculate*/
            // read data from BRAM and put it to MAC
            if(MAC_available &&  partial_recieve_done)begin

              // Turn on BRAMs
              weight_addr       <=  MAC_addr_w;
              weight_bram_en    <=  1;
              feature_addr      <=  MAC_addr_f;
              feature_bram_en   <=  1;
              bias_addr         <=  MAC_addr_b;
              bias_bram_en      <=  1;

              /* Feature BRAM control*/
              if (((MAC_addr_f<<2)==(width  * width - 1) || ((MAC_addr_f<<2) % (width*width)==(3*width) && !MAC_done)))//when pad, rest
                MAC_addr_f  <=  MAC_addr_f  - 1;

              if(((MAC_addr_f<<2)==(width  * width * input_len)-1)) //image read done
                MAC_addr_f  <=  0;
              else
                MAC_addr_f  <=  MAC_addr_f  + 1;


              
              /*Bias BRAM control*/





              /*Weight BRAM control*/




              /*Wait for BRAM Delay*/
              if(delay_f  < 2)begin
                delay_f <=  delay_f + 1;
              end
              /*When BRAM data came out*/
              else begin
                /*When we finished reading partial weights from BRAM */
                if( ( (MAC_addr_w+1) == (9 * width * width  <<  2)) && (MAC_addr_f  ==  0) && (feature_pad  ==  1)) begin
                  partial_recieve_done  <=  0;
                  bram_read_done        <=  0;
                end
                else begin
                  bram_read_done  <=  0;
                end

                if((MAC_addr_f  <<  2)  % (width*width)  < (width))begin
                  if((feature_pad  ==  0)) begin//pad for the edge of image layer
                    feature_pad     <=  1;
                    count_w_line    <=  0;
                    bram_read_done  <=  1;
                    if((MAC_addr_f<<2)==(width  * width * input_len)-1) begin
                      if(loc_b==3)begin//bias move
                        loc_b <=  0;
                        MAC_addr_b  <=  MAC_addr_b+1;
                      end
                      else
                        loc_b <=  loc_b+1;
                    end
                  end
                  else begin
                    bram_read_done <=  0;
                    if(count_w_line==0)begin//put weight.. case
                      if(loc_w_line==0)begin
                        w[0]  <=  weight_dout[7:0];
                        w[1]  <=  weight_dout[15:8];
                        w[2]  <=  weight_dout[23:16];
                        w[3]  <=  weight_dout[31:24];
                      end
                      else if(loc_w_line==1)begin
                        w[0]  <=  weight_dout[15:8];
                        w[1]  <=  weight_dout[23:16];
                        w[2]  <=  weight_dout[31:24];
                      end
                      else if(loc_w_line==2)begin
                        w[0]  <=  weight_dout[23:16];
                        w[1]  <=  weight_dout[31:24];
                      end
                      else  begin
                        w[0]  <=  weight_dout[31:24];
                      end
                      MAC_addr_w    <=  MAC_addr_w+1;
                      count_w_line  <=  count_w_line+1;
                      bias_tmp      <=  {bias_dout[loc_b<<3-1],bias_dout[loc_b<<3-2],bias_dout[loc_b<<3-3],bias_dout[loc_b<<3-4],bias_dout[loc_b<<3-5],bias_dout[loc_b<<3-6],bias_dout[loc_b<<3-7],bias_dout[loc_b<<3-8]};
                    end
                    else if(count_w_line==1)begin
                      if(loc_w_line==0)begin
                        w[4]  <=  weight_dout[7:0];
                        w[5]  <=  weight_dout[15:8];
                        w[6]  <=  weight_dout[23:16];
                        w[7]  <=  weight_dout[31:24];
                      end
                      else if(loc_w_line==1)begin
                        w[3]  <=  weight_dout[7:0];
                        w[4]  <=  weight_dout[15:8];
                        w[5]  <=  weight_dout[23:16];
                        w[6]  <=  weight_dout[31:24];
                      end
                      else if(loc_w_line==2)begin
                        w[2]  <=  weight_dout[7:0];
                        w[3]  <=  weight_dout[15:8];
                        w[4]  <=  weight_dout[23:16];
                        w[5]  <=  weight_dout[31:24];
                      end
                      else  begin
                        w[1]  <=  weight_dout[7:0];
                        w[2]  <=  weight_dout[15:8];
                        w[3]  <=  weight_dout[23:16];
                        w[4]  <=  weight_dout[31:24];
                      end
                      MAC_addr_w    <=  MAC_addr_w+1;
                      count_w_line  <=  count_w_line+1;
                    end
                    else if(count_w_line==2)begin
                      if(loc_w_line==0)begin
                        w[8]  <=  weight_dout[7:0];
                        loc_w_line  <=  1;
                      end
                      else if(loc_w_line==1)begin
                        w[7]  <=  weight_dout[7:0];
                        w[8]  <=  weight_dout[15:8];
                        loc_w_line  <=  2;
                      end
                      else if(loc_w_line==2)begin
                        w[6]  <=  weight_dout[7:0];
                        w[7]  <=  weight_dout[15:8];
                        w[8]  <=  weight_dout[23:16];
                        loc_w_line  <=  3;
                      end
                      else  begin
                        w[5]  <=  weight_dout[7:0];
                        w[6]  <=  weight_dout[15:8];
                        w[7]  <=  weight_dout[23:16];
                        w[8]  <=  weight_dout[31:24];
                        MAC_addr_w  <=  MAC_addr_w+1;
                        loc_w_line  <=  0;
                      end
                    count_w_line  <=  count_w_line+1;
                    end
                  end
                end
                else if((MAC_addr_f <<  2) % (width*width) < 2  * (width))begin//2nd line of the image
                  bram_read_done <=  0;
                end
                else if((MAC_addr_f <<  2) % (width*width) < 3  * (width))begin//3rd line of the image
                  if((MAC_addr_f) % (width)  == 3  * (width >> 2)-1)
                    bram_read_done <=  1;
                  else
                    bram_read_done <=  0;
                end
                else begin   // the rest
                  if((MAC_addr_f  <<  2) % width  == (width-1))
                    bram_read_done <=  1;
                  else
                    bram_read_done <=  0;
                end
              end
            end

            /*AXI_stream Slave interface : receiving weight*/
            /*When before last data and calculating partial result done*/
            else if( !last_data_received & !weight_read_done & !partial_recieve_done ) begin
              
              // Weights are received by granulity of  9*4*input_len (4 filters ) To reuse weight BRAM
              if(receive_cnt >= (9 * input_len) ) begin
                // When we get weights of 4 filters , stop receiving weight and go to calculate           
                s_axis_tready        <=  0;

                /*put last data of 9*4*inputlen to BRAM and turn off BRAM signals*/
                if( receive_cnt == (9* input_len) ) begin
                  weight_addr      <=  receive_cnt  - 1;
                  weight_din       <=  receive_buf;
                  weight_bram_en   <=  1;
                  weight_we        <=  1;
                  receive_cnt      <=  receive_cnt  + 1;
                end
                /*go to calculate*/
                else begin
                  weight_addr           <=  0;  
                  weight_din            <=  0; 
                  weight_bram_en        <=  0; 
                  weight_we             <=  0; 
                  l_div_4_count         <=  l_div_4_count+1;
                  partial_recieve_done  <=  1;
                  receive_cnt           <=  0;
                  receive_buf           <=  0; 
                  /*when we received all datas */
                  if( output_len / 4 == l_div_4_count + 1)  begin
                    last_data_received <=  1;
                  end
                end
              
              end
              /*Otherwise , receive input*/
              else begin
                s_axis_tready <=  1;   
                /*save input to buffer*/
                if(s_axis_tready  & S_AXIS_TVALID)  begin
                  receive_buf <=  S_AXIS_TDATA;
                  receive_cnt <=  receive_cnt + 1;  
                end      

                /*put buffered data to BRAM*/
                if(receive_cnt  !=  0)  begin
                  weight_addr      <=  receive_cnt-1;
                  weight_din       <=  receive_buf;
                  weight_bram_en   <=  1;
                  weight_we        <=  1;
                end  
              end                        
            end
            /*When we received all weights*/          
            else begin
              // init all signals, set weight_read_done flag
              weight_read_done   <=  1;  
              s_axis_tready      <=  0;
              receive_buf        <=  0;  
              receive_cnt        <=  0;
              last_data_received <=  0;
              weight_addr        <=  0;
              weight_din         <=  0;
              weight_bram_en     <=  0;
              weight_we          <=  0;                       
            end
          end           
        endcase
      end 
    end
    
  /************************************************************
  *  Input Feature Buffers : Hold features from BRAM and use them in MAC
  *
  *   FB0~3 : for holding data use in MAC 
  *   FB4,5 : to get new data from BRAM
  *
  *  // [0], [width+1] are paddings, [1~width] are features
  *                                                                               MAC WORKS HERE! 
  *   FB0    [0] [1 : width] [width+1]  FB1 [0] [1 : width] [width+1]      FB0 |  * * *    
  *                /\                               /\                     FB1 |  * * *  - - - >    * * *    
  *                ||                               ||                     FB2 |  * * *             * * *  - - - > 
  *   FB2    [0] [1 : width] [width+1]  FB3 [0] [1 : width] [width+1]      FB3 |                    * * *             
  *                         \                   /  
  *                            \             /     
  *                               \       /
  *                                  \  /
  *                                   /\
  *                                 /    \
  *                               /         \     
  *                             /             \   
  *   FB4                     /               [0 : width-1]
  *                         /                       /\    
  *                       /                         ||   
  *   FB5     [0 : width-1]                  [width : 2*width-1]
  *                              /\         
  *                              ||         
  *                         Feature_BRAM                      
  *       
  *  Generate MAC_START signal
  *  RECIEVE MAC_DONE signal
  */
  parameter MAX_WIDTH=32;
  reg [7:0] FB0 [MAX_WIDTH+1:0];    // 33:0
  reg [7:0] FB1 [MAX_WIDTH+1:0];
  reg [7:0] FB2 [MAX_WIDTH+1:0];
  reg [7:0] FB3 [MAX_WIDTH+1:0];

  reg [7:0] FB4 [MAX_WIDTH-1:0];
  reg [7:0] FB5 [2*MAX_WIDTH-1:0];   
     

  reg shift_flag;
  /*FB0~4 : Shifting logics */
    genvar j;
    generate for(j=0 ; j<=MAX_WIDTH+1 ; j=j+1)
      always @(posedge clk or negedge rstn) begin
        if (reset) begin
          FB0[j]  <=  0;
          FB1[j]  <=  0;
          FB2[j]  <=  0;
          FB3[j]  <=  0;
          FB4[j]  <=  0;
        end
        /*When MAC-4 width calculation done && reading FB5 done*/
        else if(SHIFTING CONDITION) begin dddddddddddddddddddddddddddddddddddddd
          FB0[j]  <=  FB2[j];
          FB1[j]  <=  FB3[j];        
          /*j==0, j>width : alwyas 0 (padding)*/
          if( (j != 0) && (j <= width) ) begin
            FB2[j]  <=  FB4[j-1];        
            FB3[j]  <=  FB5[j-1];
            FB4[j]  <=  FB5[j+width];
          end
        end
      end
    end endgenerate

  /*Delayed address : Same address with BRAM output*/
  reg [15:0]  MAC_addr_f_t;
    // FBOA : 0 ~ width*width*length/4 - 1
  reg [15:0]  Feature_BRAM_out_addr;
    always @(posedge clk or negedge rstn) begin
      if(reset) begin
        MAC_addr_f_t          <= 0;
        Feature_BRAM_out_addr <= 0;
      end
      else begin
        MAC_addr_f_t          <=  MAC_addr_f;
        Feature_BRAM_out_addr <=  MAC_addr_f_t;      
      end
    end

  /*FB5 : get features from feature_bram */
    // get double width per once
    wire [15:0] feature_bram_idx = Feature_BRAM_out_addr % (width >> 1); // (delayed featurebram address)  % (double width /4) : 0 ~ width/2 - 1 
    genvar k;
    generate for(k=0; k<2*MAX_WIDTH; k=k+1) begin
      always @(posedge clk or negedge rstn) begin
        if(reset) begin
          FB5[k]  <=  0;
        end
        else begin
          /*after reading one input feature map, put bottom padding*/
          if(end_of_feature_map) begin ffffffffffffffffffffffffffffffffffffffffffff
            FB5[k]  <=  0;
          end
          /*normal input feature map read*/
          else if( (k/4) == feature_bram_idx) begin
            FB5[k]  <=  feature_dout[(k%4)*8+7-:8];
          end
        end
      end
    end endgenerate
  
  /************************************************************/
  /*MAC*/
  reg        men;
  reg [31:0]  bias_mac;
  wire[31:0] mout;    
  wire       MAC_done;
    mac3x3  cmac(
      .clk(clk),
      .en(men),
      .rstn(rstn),
      .bias(bias_mac),
      .w0(w[0]),
      .w1(w[1]),
      .w2(w[2]),
      .w3(w[3]),
      .w4(w[4]),
      .w5(w[5]),
      .w6(w[6]),
      .w7(w[7]),
      .w8(w[8]),
      .f0(f[0]),
      .f1(f[1]),
      .f2(f[2]),
      .f3(f[3]),
      .f4(f[4]),
      .f5(f[5]),
      .f6(f[6]),
      .f7(f[7]),
      .f8(f[8]),
      .mout(mout),
      .done(MAC_done)
    );
  
  /************************************************************/
  /*Moving kernel : generating Feature map */
              /*    col1 col2
              *row1
              *row2
              */

  reg signed [31:0] feature_map[MAX_WIDTH-1:0][MAX_WIDTH-1:0];   //feature_map [row][col]
  /*position of kernel*/
  reg [5:0] kernel_row;
  reg [5:0] kernel_col;
  /*position of current MAC output*/
  reg [5:0] MAC_out_row;
  reg [5:0] MAC_out_col;
  
  reg update_feature_map;
  reg reset_feature_map;
  reg set_bias_to_feature_map;
  wire[31:0] feature_map_bias;

  genvar row;
  genvar col;
  generate for ( row=0 ; row<MAX_WIDTH ; row=row+1 ) begin
    for(col=0 ; col<MAX_WIDTH ; col=col+1)begin
      always @(posedge clk or negedge rstn) begin
        if(reset) begin
          feature_map[row][col]<=0;
        end
        else if(set_bias_to_feature_map) begin
          feature_map[row][col]<=0;
        end
        else begin
          if(reset_feature_map) begin
            feature_map[row][col] <=  0;
          end
          else if(update_feature_map & (MAC_out_row == row) & (MAC_out_col == col)) begin
            feature_map[row][col] <= mout;
          end
        end
      end
    end
  end endgenerate





  reg signed  [31:0]  feature_map [1023:0]; //intermediate value buffer
  reg [5:0]tmp_row;
  reg [5:0]tmp_col;
  genvar i;
  generate for(i=0;i<1024;i=i+1)begin// saving intermediate values of conv
    always @(posedge clk or negedge rstn) begin
      if(reset) begin
        feature_map[i]<=0;
      end
      //when intermediate value came out from MAC
      if(((MAC_addr_f  <<  2) < (width * width)*(output_len)) && (tmp_row*32 + tmp_col  ==  i))
        feature_map[i]  <=  mout;
      else
        feature_map[i]  <=  feature_map[i];
    end
  end endgenerate



  always @(posedge clk or negedge rstn) begin
      if(reset) begin
        men         <=  0;
        bias_mac    <=  0;
        tmp_row     <=  0;
        tmp_col     <=  0;
        f[0]  <=  0;  f[1]  <=  0;  f[2]  <=  0;  f[3]  <=  0;  f[4]  <=  0;  f[5]  <=  0;  
        f[4]  <=  0;  f[5]  <=  0;  f[6]  <=  0;  f[7]  <=  0;  f[8]  <=  0;
        MAC_available <=  1;
      end
      else if(partial_recieve_done  &&  bram_read_done) begin
        if(MAC_done)begin//update feature_map when mac done
          men <=  0;
          if((MAC_addr_f  <<  2) < (width * width)*(output_len))begin
            if(tmp_col==width-1)begin
              if(tmp_row==width-1)begin
                MAC_available <=  1;
                tmp_col <=  0;
                tmp_row <=  0;
              end
              tmp_col <=  0;
              tmp_row <=  tmp_row+1;
            end
            else begin
              tmp_col <=  0;
              tmp_col <=  tmp_col+1;
              tmp_row <=  tmp_row;
            end
          end
        end
        else begin
          men  <= 1;
          f[0]  <=  feature[tmp_col];
          f[1]  <=  feature[tmp_col+1];
          f[2]  <=  feature[tmp_col+2];
          f[3]  <=  feature[34+tmp_col];
          f[4]  <=  feature[35+tmp_col];
          f[5]  <=  feature[36+tmp_col];
          f[6]  <=  feature[68+tmp_col];
          f[7]  <=  feature[69+tmp_col];
          f[8]  <=  feature[70+tmp_col];
          if((MAC_addr_f  <<  2) < (width * width))
            bias_mac <=  {{19{bias_tmp[7]}}, bias_tmp[6:0], 6'b0};//ssssssssssssssssssx.xxxxxxxxxxxx ??
          else
            bias_mac  <=  feature_map[tmp_row*width + tmp_col];
        end
      end
      else begin
        men         <=  0;
        bias_mac    <=  0;
        tmp_row     <=  0;
        tmp_col     <=  0;
        f[0]  <=  0;  f[1]  <=  0;  f[2]  <=  0;  f[3]  <=  0;  f[4]  <=  0;  f[5]  <=  0;  
        f[4]  <=  0;  f[5]  <=  0;  f[6]  <=  0;  f[7]  <=  0;  f[8]  <=  0;
        MAC_available <=  1;
      end
    end




  /****************************************************************************/
  /*AXI_stream Master interface : send data*/
  /*RELU*/
  reg [9:0]  send_loc;
  reg [8:0]  out_len_count;
  always@(posedge clk or negedge rstn) begin  /////////////
    if(reset) begin
      send_loc      <=  0;
      m_axis_tvalid <=  0;
      m_axis_tdata  <=  0;
      out_len_count <=  0;
      m_axis_tlast  <=  0;
    end
    else if((MAC_addr_f > (width*width)*(input_len-1) || send_loc !=  0) && M_AXIS_TREADY)begin //relu
      m_axis_tdata[7:0]   <=  (({18{feature_map[send_loc][31]}}   ==  feature_map[send_loc][30:13])   ? (feature_map[send_loc][31]  ? 0 :  {feature_map[send_loc][31]   ,feature_map[send_loc][12:6]})  :{feature_map[send_loc][31]   ,{7{!feature_map[send_loc][31]  }}});
      m_axis_tdata[15:8]  <=  (({18{feature_map[send_loc+1][31]}} ==  feature_map[send_loc+1][30:13]) ? (feature_map[send_loc+1][31]? 0 :  {feature_map[send_loc+1][31] ,feature_map[send_loc+1][12:6]}):{feature_map[send_loc+1][31] ,{7{!feature_map[send_loc+1][31]}}});
      m_axis_tdata[23:16] <=  (({18{feature_map[send_loc+2][31]}} ==  feature_map[send_loc+2][30:13]) ? (feature_map[send_loc+2][31]? 0 :  {feature_map[send_loc+2][31] ,feature_map[send_loc+2][12:6]}):{feature_map[send_loc+2][31] ,{7{!feature_map[send_loc+2][31]}}});                                                                                  
      m_axis_tdata[31:24] <=  (({18{feature_map[send_loc+3][31]}} ==  feature_map[send_loc+3][30:13]) ? (feature_map[send_loc+3][31]? 0 :  {feature_map[send_loc+3][31] ,feature_map[send_loc+3][12:6]}):{feature_map[send_loc+3][31] ,{7{!feature_map[send_loc+3][31]}}});
      m_axis_tvalid <=  1;
      
      if((out_len_count ==  output_len-1) && (send_loc[9:5]  ==  width-1)  &&  (send_loc[4:0]  ==  width-4) ) begin//when all output data sent
        m_axis_tlast  <=  1;
        out_len_count <=  out_len_count+1;
        send_loc      <=  0;
        conv_done     <=  1;
      end
      else begin
        if(send_loc[4:0] != width-4)// location update
          send_loc    <=  send_loc  + 4;
        else
          send_loc    <=  {(send_loc[9:5]+1),5'b00000};

        m_axis_tlast  <=  0; 
      end
    end
    else begin
      send_loc      <=  0;
      m_axis_tvalid <=  0;
      m_axis_tdata  <=  0;
      out_len_count <=  0;
      m_axis_tlast  <=  0;
    end
  end        
endmodule