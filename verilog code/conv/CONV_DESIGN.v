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
  input wire [2:0]                                      command, // 0: IDLE 1 : read feature 2: read bias 3: read weight & calculate  !!!!!!!!!!!!!!!!!!!! NO command 4.
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
  reg [2:0] RECEIVE_STATE;
  `define STATE_IDLE      3'b000
  `define RECEIVE_FEATURE 3'b001
  `define RECEIVE_BIAS    3'b010
  `define RECEIVE_WEIGHT  3'b011

  reg [8:0] input_len; 
  reg [8:0] output_len;
  reg [8:0] width;
    always @(posedge clk or negedge rstn) begin
      if(!rstn) begin
        RECEIVE_STATE <=  0;
      end
      else begin
        RECEIVE_STATE <=  command;
        input_len     <=  input_len_ex;
        output_len    <=  output_len_ex;
        width         <=  width_ex;
      end
    end

  /************************************************************/
  /*feature BRAM module*/ /*MAXSIZE=32*16*16 // 13-2=11 */  /*width-height-length*/  
  reg [11:0]          feature_bram_addr;
  reg [31:0]          feature_bram_din;
  wire [31:0]         feature_bram_dout;
  reg                 feature_bram_en;
  reg                 feature_bram_we;        
    feature_bram feature_bram_32x2048(
      .addra(feature_bram_addr),
      .clka (clk),
      .dina (feature_bram_din),
      .douta(feature_bram_dout),
      .ena  (feature_bram_en),
      .wea  (feature_bram_we)
    );


  /************************************************************/
  /*bias BRAM module*/  /*MAXSIZE = 256 // 8-2=6*/
  reg [6:0]           bias_bram_addr;
  reg [31:0]          bias_bram_din;
  wire [31:0]         bias_bram_dout;
  reg                 bias_bram_en;
  reg                 bias_bram_we;        
    bias_bram bias_bram_32x64(
      .addra(bias_bram_addr),
      .clka (clk),
      .dina (bias_bram_din),
      .douta(bias_bram_dout),
      .ena  (bias_bram_en),
      .wea  (bias_bram_we)
    );

  /************************************************************/
  /*weight BRAM module*/  /*MAXSIZXE  = 256*3*3 = 2304 // 8+8+4-2=18*/  /*(out-channel, in-channel, rows, cols)*/
  reg [18:0]          weight_bram_addr;
  reg [31:0]          weight_bram_din;
  wire [31:0]         weight_bram_dout;
  reg                 weight_bram_en;
  reg                 weight_bram_we;        
    weight_bram weight_bram_32x256x9( 
      .addra(weight_bram_addr),
      .clka (clk),
      .dina (weight_bram_din),
      .douta(weight_bram_dout),
      .ena  (weight_bram_en),
      .wea  (weight_bram_we)
    );

  /************************************************************/
  /*    AXI_stream Slave interface : receiving data
  *
  *   Receive_feature and receive_bias - forward receive buffer and receive count.
  *   Receive_weight : 
  *     To reuse BRAM, our granulity of receiving weight is 4 x filter size.(i.e. 4 x 3x3 x input_len )
  *     When we receive one granulity of weight, set partial_receive_done_gen flag.
  *     Then BRAM_controller module will do CONV calculation using partial weight.
  *
  *     After finishing partial calculation, BRAM_controller will send resume_receive_weight flag 
  *     
  *     This procedure will be iterate until the last weight input
  */

  /*Signals to BRAM_controller*/
  reg [C_S00_AXIS_TDATA_WIDTH-1 : 0]  receive_buf; //31:0 , 4 of 8-bit datas
  reg [15:0] receive_cnt;//receive_buf get first data when it rises to 1
  reg data_received;
  reg last_data_received;

  reg partial_receive_done;

  /*signal from BRAM_controller*/
  reg resume_receive_weight;  

  /*internal reg*/
  reg [6:0] prd_cnt; //==l_div4_cnt.  partial receive done counter.   
  reg feature_read_done_internal;
  reg bias_read_done_internal;
  reg weight_read_done_internal;
  reg partial_receive_done_gen;
  reg partial_receive_done_delay;

    always @(posedge clk or negedge rstn) begin
      if(!rstn) begin
        partial_receive_done        <=  0;
        partial_receive_done_delay  <=  0;
      end
      else if (RECEIVE_STATE==`STATE_IDLE  || resume_receive_weight)begin
        partial_receive_done        <=  0;
        partial_receive_done_delay  <=  0;
      end
      else begin
        partial_receive_done_delay  <=  partial_receive_done_gen;
        partial_receive_done        <=  partial_receive_done_delay;
      end
    end



    /*receiving S_AXIS_TDATA*/
    always @(posedge clk or negedge rstn) begin
      if(!rstn) begin
        s_axis_tready               <=  0;

        receive_buf                 <=  0;
        receive_cnt                 <=  0;
        data_received               <=  0;
        last_data_received          <=  0;

        feature_read_done_internal  <=  0;
        bias_read_done_internal     <=  0;
        weight_read_done_internal   <=  0;
        
        partial_receive_done_gen    <=  0;
        prd_cnt                     <=  0;
      end
      else if (RECEIVE_STATE ==`STATE_IDLE) begin
        s_axis_tready               <=  0;

        receive_buf                 <=  0;
        receive_cnt                 <=  0;
        data_received               <=  0;
        last_data_received          <=  0;

        feature_read_done_internal  <=  0;
        bias_read_done_internal     <=  0;
        weight_read_done_internal   <=  0;
        
        partial_receive_done_gen    <=  0;
        prd_cnt                     <=  0;
      end
      else begin
        case (RECEIVE_STATE)
                    
          `RECEIVE_FEATURE : begin
            /*Before receiving last data*/
            if( !last_data_received && !feature_read_done_internal ) begin
              feature_read_done_internal <=  0;
              s_axis_tready     <=  1;
              
              /*Valid data : save input to buffer*/
              if(s_axis_tready  & S_AXIS_TVALID)  begin
                receive_buf   <=  S_AXIS_TDATA;
                receive_cnt   <=  receive_cnt + 1; 
                data_received <=  1;

if(receive_cnt < 9*64);
$display("image ",receive_cnt, " ", S_AXIS_TDATA);

                /*Sensing last data*/
                if(S_AXIS_TLAST) begin
                  last_data_received  <=  1;
                end
                else begin
                  last_data_received  <=  0;
                end
              end
              /*invalid data */
              else begin
                receive_buf   <=  0;
                receive_cnt   <=  receive_cnt;
                data_received <=  0;
                last_data_received  <= 0;
              end

            end
            /*When we received all features*/          
            else begin
              // init all signals, set feature_read_done_internal flag
              feature_read_done_internal   <=  1;  
              s_axis_tready       <=  0;
              receive_buf         <=  0;  
              receive_cnt         <=  0;
              last_data_received  <=  0;
              data_received       <=  0;
            end                       
          end


          `RECEIVE_BIAS : begin
            /*Before receiving last data*/
            if( !last_data_received && !bias_read_done_internal ) begin
              bias_read_done_internal  <=  0;
              s_axis_tready            <=  1;
              
              /*Valid data : save input to buffer*/
              if(s_axis_tready  & S_AXIS_TVALID)  begin
                receive_buf   <=  S_AXIS_TDATA;
                receive_cnt   <=  receive_cnt + 1; 
                data_received <=  1;

                /*Sensing last data*/
                if(S_AXIS_TLAST) begin
                  last_data_received  <=  1;
                end
                else begin
                  last_data_received  <=  0;
                end
              end
              /*invalid data */
              else begin
                receive_buf   <=  0;
                receive_cnt   <=  receive_cnt;
                data_received <=  0;
                last_data_received  <= 0;
              end

            end
            /*When we received all features*/          
            else begin
              // init all signals, set bias_read_done_internal flag
              bias_read_done_internal      <=  1;  
              s_axis_tready                <=  0;
              receive_buf                  <=  0;  
              receive_cnt                  <=  0;
              last_data_received           <=  0;
              data_received                <=  0;
            end                                  
          end


          `RECEIVE_WEIGHT : begin
            /*Before receiving last data*/
            /*Sensing partial last data*/
                //partial last data : 3x3 * input len * 4
            if( !last_data_received && bias_read_done & !partial_receive_done_gen  ) begin
                if( receive_cnt == (9* input_len)-1 && S_AXIS_TVALID && s_axis_tready) begin
                    partial_receive_done_gen  <=  1;
                    prd_cnt               <=  prd_cnt + 1;
                    s_axis_tready         <=  0;
                end
                else begin
                    partial_receive_done_gen   <=  0;
                    prd_cnt                    <=  prd_cnt;
                    s_axis_tready              <=  1;
                end
                weight_read_done_internal      <=  0;
              
              /*Valid data : save input to buffer*/
              if(s_axis_tready  & S_AXIS_TVALID)  begin
                receive_buf   <=  S_AXIS_TDATA;
                receive_cnt   <=  receive_cnt + 1; 
                data_received <=  1;

if(receive_cnt < 9*64);
$display("weight ",receive_cnt, " ", S_AXIS_TDATA);



                /*Sensing last data*/
                // if we get TLAST signal while receiving last partial weight sets. This is for reusing BRAM
                if( S_AXIS_TLAST & ( (prd_cnt + 1)  ==  (output_len >> 2) ) ) begin
                  last_data_received  <=  1;
                end
                else begin
                  last_data_received  <=  0;
                end
              end
              /*invalid data */
              else begin
                receive_buf           <=  0;
                receive_cnt           <=  receive_cnt;
                data_received         <=  0;
                partial_receive_done_gen  <=  0;
                prd_cnt               <=  prd_cnt;                
                last_data_received    <=  0;
              end

            end 
            else if(partial_receive_done_gen)begin

              if(resume_receive_weight && partial_receive_done) begin
                partial_receive_done_gen  <=  0;
              end 
              else begin
                partial_receive_done_gen  <=  1;
              end
              weight_read_done_internal    <=  0;  
              s_axis_tready                <=  0;
              data_received                <=  0;              
              receive_buf                  <=  0;  
              receive_cnt                  <=  0;
              prd_cnt                      <=  prd_cnt;
              last_data_received           <=  0;            
            end
            /*When we received all features*/          
            else if(last_data_received)begin
              // init all signals, set weight_read_done flag
              weight_read_done_internal    <=  1;  
              s_axis_tready                <=  0;
              data_received                <=  0;              
              receive_buf                  <=  0;  
              receive_cnt                  <=  0;
              partial_receive_done_gen     <=  0;
              prd_cnt                      <=  0;
              last_data_received           <=  0;                            
            end
            /*Never come here*/            
            else begin
              $display("Control flow error detected in RECEIVING_WEIGHT");
              $stop;
            end            
          end
        endcase
      end
    end

    /*wait for few cycles before sending read_done signals to outside */
    always @(posedge clk or negedge rstn) begin
      if(!rstn) begin
        feature_read_done <=  0;
        bias_read_done    <=  0;
        weight_read_done  <=  0;
      end
      else if (RECEIVE_STATE == ` STATE_IDLE) begin
        feature_read_done <=  0;
        weight_read_done  <=  0;
      end
      else begin
        if(feature_read_done_internal && !feature_read_done) begin
          feature_read_done   <=  1;
        end
        else if(bias_read_done_internal && !bias_read_done) begin
          bias_read_done    <=  1;
        end
        if(weight_read_done_internal && !weight_read_done) begin
          weight_read_done    <=  1;
        end               
      end
    end


  /**************************************************************************************/
  /*              BRAM controller
  *
  *     This is main control logic.
  *     1. Get input from AXIS_SLAVE interface and save it to BRAM.
  *     2. When partial receive done flag is on, we should do partial computation using weight of 4 x filters
  *         -Generate Control signals for Feature, Bias, weight BRAM 
  *         -Generate Control signals for input_feature_buffer, Kernel_weight_buffer, MAC_controller
  *
  *         *Psuedo Code: 
  *         *  for filter in 4 filters
  *         *    read bias and save it to OUTPUT_FEATURE_MAP
  *         *    for (images in input_length)
  *         *      
  *         *      update KERNEL_WEIGHT_BUFFER
  *         *      for (heights in width/2)
  *         *        save 4 width of feature to Input_feature_Buffer
  *         *  
  *         *        operate MAC_controller
  *         *          FB0 |  * * *    
  *         *          FB1 |  * * *  - - - >    * * *    
  *         *          FB2 |  * * *             * * *  - - - > 
  *         *          FB3 |                    * * *             
  *         *        accumulate MAC output to OUTPUT_FEATURE_MAP
  *         *  
  *         *    pass OUTPUT_FEATURE_MAP through RELU and send to AXIS_MASTER interface
  *         *  set CONV_DONE flag
  *         
  *     
  *
  *     3. set resume_receive_weight flag after
  */

  /*Signal from AXIS_SLAVE interface*/
    //  reg [C_S00_AXIS_TDATA_WIDTH-1 : 0]  receive_buf; //31:0 , 4 of 8-bit datas
    //  reg [15:0] receive_cnt;//receive_buf get first data when it rises to 1
    //  reg data_received;
    //  reg last_data_received;
    //  reg partial_receive_done_gen;
  /*signal to   AXIS_SLAVE interface*/
    //  reg resume_receive_weight;  

  /*Signals to    Input_feature_Buffer*/
  reg [15:0]  IFB_FB5_INDEX;  // index of filling FB5 buffer. (index from delayed bram address.) Look Input feature buffer logic for more info of FB5.
  reg FEATURE_BRAM_DOUT_VALID; //validity of BRAM DOUT.
  reg IFB_SHIFTING_CONDITION;
  reg IFB_END_OF_ONE_IMAGE; // read last input feature of one image
  reg IFB_RESET;

  /*Signals from  Input_feature_Buffer*/  
  reg IFB_FB5_FILL_DONE;


  /*Signals to    Kernel_weight_Buffer*/
  reg [3:0] KWB_INDEX;
  reg [2:0] KWB_START_POINT; // Starting index of kernel weight from first weight bram dout
  reg KWB_WEIGHT_BRAM_VALID;


  /*Signals from  Kernel_weight_Buffer*/  
  // nothing

  /*Signals to    Output_feature_map  */
  reg OFM_BIAS_VALID; //bias valid signal.
  //reg [2:0]prd_filter_cnt;

  /*Signals from  Output_feature_map  */ 
  // nothing   

  /*Signals to MAC_Controller*/
  reg MAC_START;
  /*Signals from MAC_Controller*/
  reg MAC_DONE;
  reg MAC_IDLE;
  reg [5:0] MAC_out_row;
  reg [5:0] MAC_out_col;  

  /*Signals to AXIS_MASTER*/
  reg SEND_ONE_IMAGE_START;
  /*Signals from AXIS_MASTER*/
  reg SEND_ONE_IMAGE_DONE;
  /*Internal registers */

  /*Send state*/
  reg SENDING;
  /********** partial receive done feauture counters 
  * prd_filter_cnt      : indicates which filter we are working with;
  * prd_feature_image_cnt : 0 ~ input_len - 1         : indicates which input feature we are working with
  * prd_feature_height_cnt : 0 ~ width / 2 + alpha      :height_cnt * 2 == Which height does FB5 should get. 
  * prd_ref_cnt : 0 ~ width /2 + alpha :  Purpose of this counter is to make BRAM TIMING easier. it works as reference clock while filling FB5.
  * prd_ref_cnt2 : 0 ~ 5 + alpha :  it works as reference clock while filling Kernel width buffer.
  */
  reg [2:0]prd_filter_cnt;
  reg [9:0]prd_feature_image_cnt;  
  reg [9:0]prd_feature_height_cnt;
  reg [15:0]prd_ref_cnt;
  reg [4:0]prd_ref_cnt2;

  reg [7:0] resume_receive_weight_cnt; // this counter * 4 == how many filters does we finished. 

  reg [15:0]Feature_BRAM_out_addr_temp;


    /*bram_controller main*/
    always @(posedge clk or negedge rstn) begin
      if(!rstn) begin
        resume_receive_weight         <=  0;
        resume_receive_weight_cnt     <=  0;

        feature_bram_addr             <=  0;
        feature_bram_din              <=  0;
        feature_bram_en               <=  0;
        feature_bram_we               <=  0;

        bias_bram_addr                <=  0;
        bias_bram_din                 <=  0;
        bias_bram_en                  <=  0;
        bias_bram_we                  <=  0;

        weight_bram_addr              <=  0;
        weight_bram_din               <=  0;
        weight_bram_en                <=  0;
        weight_bram_we                <=  0;

        /*control signals to input feature buffer*/
        IFB_FB5_INDEX                 <=  0;
        FEATURE_BRAM_DOUT_VALID       <=  0;
        IFB_SHIFTING_CONDITION        <=  0;
        IFB_END_OF_ONE_IMAGE          <=  0;   
        IFB_RESET                     <=  0;   

        /*control signals to kernel weight buffer*/
        KWB_INDEX                     <=  0;
        KWB_WEIGHT_BRAM_VALID         <=  0;
        KWB_START_POINT               <=  0;

        /*Signals to    Output_feature_map  */
        OFM_BIAS_VALID                <=  0;

        /*Signals to MAC_Controller*/
        MAC_START                     <=  0;

        /*Signals to AXIS_MASTER*/
        SEND_ONE_IMAGE_START          <=  0;
        SENDING                       <=  0;
        /*internal regs*/
        prd_filter_cnt                <=  0;
        prd_feature_image_cnt         <=  0;
        prd_feature_height_cnt        <=  0;
        prd_ref_cnt                   <=  0;
        prd_ref_cnt2                  <=  0;        

        Feature_BRAM_out_addr_temp    <=  0;         

        /*signal to output */
        conv_done                     <=  0;
      end
      else if (RECEIVE_STATE == `STATE_IDLE) begin
        resume_receive_weight         <=  0;
        resume_receive_weight_cnt     <=  0;

        feature_bram_addr             <=  0;
        feature_bram_din              <=  0;
        feature_bram_en               <=  0;
        feature_bram_we               <=  0;

        bias_bram_addr                <=  0;
        bias_bram_din                 <=  0;
        bias_bram_en                  <=  0;
        bias_bram_we                  <=  0;

        weight_bram_addr              <=  0;
        weight_bram_din               <=  0;
        weight_bram_en                <=  0;
        weight_bram_we                <=  0;

        /*control signals to input feature buffer*/
        IFB_FB5_INDEX                 <=  0;
        FEATURE_BRAM_DOUT_VALID       <=  0;
        IFB_SHIFTING_CONDITION        <=  0;
        IFB_END_OF_ONE_IMAGE          <=  0;   
        IFB_RESET                     <=  0;   

        /*control signals to kernel weight buffer*/
        KWB_INDEX                     <=  0;
        KWB_WEIGHT_BRAM_VALID         <=  0;
        KWB_START_POINT               <=  0;

        /*Signals to    Output_feature_map  */
        OFM_BIAS_VALID                <=  0;

        /*Signals to MAC_Controller*/
        MAC_START                     <=  0;

        /*Signals to AXIS_MASTER*/
        SEND_ONE_IMAGE_START          <=  0;
        SENDING                       <=  0;
        /*internal regs*/
        prd_filter_cnt                <=  0;
        prd_feature_image_cnt         <=  0;
        prd_feature_height_cnt        <=  0;
        prd_ref_cnt                   <=  0;
        prd_ref_cnt2                  <=  0;        

        Feature_BRAM_out_addr_temp    <=  0;         

        /*signal to output */
        conv_done                     <=  0;
      end
      else begin
        case (RECEIVE_STATE)
                    
          `RECEIVE_FEATURE : begin

            //if receive buffer gets valid data
            if(data_received)begin
              // save it to feature_bram
              feature_bram_addr            <=  receive_cnt-1;
              feature_bram_din             <=  receive_buf;
              feature_bram_en              <=  1;
              feature_bram_we              <=  1;   

              bias_bram_addr               <=  0;
              bias_bram_din                <=  0;
              bias_bram_en                 <=  0;
              bias_bram_we                 <=  0;

              weight_bram_addr             <=  0;
              weight_bram_din              <=  0;
              weight_bram_en               <=  0;
              weight_bram_we               <=  0;                        
            end
            /*IDLE*/
            else begin
              feature_bram_addr            <=  0;
              feature_bram_din             <=  0;
              feature_bram_en              <=  0;
              feature_bram_we              <=  0;    

              bias_bram_addr               <=  0;
              bias_bram_din                <=  0;
              bias_bram_en                 <=  0;
              bias_bram_we                 <=  0;

              weight_bram_addr             <=  0;
              weight_bram_din              <=  0;
              weight_bram_en               <=  0;
              weight_bram_we               <=  0;                      
            end
          end


          `RECEIVE_BIAS : begin
            //if receive buffer gets valid data
            if(data_received)begin
              // save it to bias_bram
              feature_bram_addr            <=  0;
              feature_bram_din             <=  0;
              feature_bram_en              <=  0;
              feature_bram_we              <=  0;

              bias_bram_addr               <=  receive_cnt-1;
              bias_bram_din                <=  receive_buf;
              bias_bram_en                 <=  1;
              bias_bram_we                 <=  1;   

              weight_bram_addr             <=  0;
              weight_bram_din              <=  0;
              weight_bram_en               <=  0;
              weight_bram_we               <=  0;                        
            end
            /*IDLE*/
            else begin
              feature_bram_addr            <=  0;
              feature_bram_din             <=  0;
              feature_bram_en              <=  0;
              feature_bram_we              <=  0;    

              bias_bram_addr               <=  0;
              bias_bram_din                <=  0;
              bias_bram_en                 <=  0;
              bias_bram_we                 <=  0;

              weight_bram_addr             <=  0;
              weight_bram_din              <=  0;
              weight_bram_en               <=  0;
              weight_bram_we               <=  0;                      
            end
                                  
          end


          `RECEIVE_WEIGHT : begin
            //if receive buffer gets valid data from AXIS_SLAVE interface
            if(data_received)begin
              // save it to feature_bram
              feature_bram_addr            <=  0;
              feature_bram_din             <=  0;
              feature_bram_en              <=  0;
              feature_bram_we              <=  0;

              bias_bram_addr               <=  0; 
              bias_bram_din                <=  0; 
              bias_bram_en                 <=  0; 
              bias_bram_we                 <=  0; 

              weight_bram_addr             <=  receive_cnt-1;
              weight_bram_din              <=  receive_buf;
              weight_bram_en               <=  1;
              weight_bram_we               <=  1;               
            end


            //***************************if partial receive done********************************************
            else if(partial_receive_done) begin
              // read proper datas from bram
              /*************************************************************/
              /*Partial receive done feature counters**/
              //if we finished working with one filter result : image_cnt == input_len-1 && alpha
              if(SEND_ONE_IMAGE_DONE)begin
                //change filter count
                if(prd_filter_cnt <  3) begin
                  prd_filter_cnt  <=  prd_filter_cnt + 1;                  
                end
                //if it was last filter of partial received weight
                else begin
                  //resume weight receiving while  ! last 4 filters
                  if(resume_receive_weight_cnt  <  output_len / 4 - 1) begin
                    resume_receive_weight     <=  1;
                    resume_receive_weight_cnt <=  resume_receive_weight_cnt + 1;                    
                    conv_done <=  0;
                  end
                  // if it was last 4 filter weight
                  else begin
                    conv_done <=  1;
                    resume_receive_weight     <=  0;
                    resume_receive_weight_cnt <=  resume_receive_weight_cnt;
                  end

                  //reset filter count
                  prd_filter_cnt  <=  0;
                end
              end            

              //if we finished working with one image
              if(MAC_DONE && (prd_feature_height_cnt  ==  width/2 +1))begin
                //change imange count
                if(prd_feature_image_cnt  < input_len -1  )begin
                  prd_feature_image_cnt <=  prd_feature_image_cnt  + 1; 
                end
                //if it was las image of one filter
                else begin
                  // reset image counter
                  prd_feature_image_cnt <=  0;
                end
              end 

              //shifting condition
              if( (IFB_FB5_FILL_DONE && MAC_IDLE) || MAC_DONE )begin
                //change height counter
                if(prd_feature_height_cnt  <= (width >> 1) )begin
                  prd_feature_height_cnt <=  prd_feature_height_cnt  + 1; 
                end
                //if it was last height of one filter
                else begin
                  // reset height counter
                  prd_feature_height_cnt <=  0;
                end 
              end

              // weight read reference counter init condition == FB shifting condition && Not End of image condition
              if( (( (IFB_FB5_FILL_DONE && MAC_IDLE) || MAC_DONE) && ( prd_feature_height_cnt <= (width >> 1 ) + 1)) || SENDING ) begin
                prd_ref_cnt <=  0;
              end
              // stop condition : larger enough then width/2-1
              else if(prd_ref_cnt > ( (width >> 1) + 10) ) begin
                prd_ref_cnt <=  prd_ref_cnt;
              end
              else begin
                prd_ref_cnt <=  prd_ref_cnt + 1;
              end

              // refresh KWB condition : when we finished one image. It can be also used for bias
              if( (( (IFB_FB5_FILL_DONE && MAC_IDLE) || MAC_DONE) && ( prd_feature_height_cnt <= (width >> 1 ) + 1)) || SENDING ) begin
                prd_ref_cnt2 <=  0;
              end
              // stop condition : cnt2 is much bigger then 3x3
              else if(prd_ref_cnt2  >15) begin
                prd_ref_cnt2 <=  prd_ref_cnt2;
              end
              else begin
                prd_ref_cnt2 <=  prd_ref_cnt2 + 1;
              end

              /**************************************************************************?
              /*Communicate with MAC_controller*/
              // calculation start 
              //shifgint condition && (height_cnt is 1 ~ width /2 )
              if( ( (IFB_FB5_FILL_DONE && MAC_IDLE) || MAC_DONE ) && (prd_feature_height_cnt > 0 && prd_feature_height_cnt <= (width >> 1) ) ) begin
                MAC_START <=  1;
              end
              else begin
                MAC_START <=  0;
              end

              /**************************************************************************?
              /*Communicate with output_feature_map*/
              // control signals for setting initial bias

              if(prd_ref_cnt2==0) begin
                //// feature_bram start address : (filter cnt * 3x3 * input_len + image_cnt * 3x3 )  / 4
                bias_bram_addr            <=  resume_receive_weight_cnt ;
                bias_bram_din             <=  0;
                bias_bram_en              <=  1;
                bias_bram_we              <=  0;     
              end

              if( (prd_ref_cnt2 == 2) && (MAC_out_row ==  0) && (MAC_out_col  ==  0) && (prd_feature_image_cnt  ==  0)  && !SENDING ) begin
                OFM_BIAS_VALID        <=  1;
              end
              else begin
                OFM_BIAS_VALID        <=  0;
              end



              /************************************************************************************************/
              /*   Communication with Input_feature_buffer     */
                                     
              //1. feature bram control
              /*initial bram input*/
              if(prd_ref_cnt==0 || IFB_END_OF_ONE_IMAGE) begin
                feature_bram_din             <=  0;
                feature_bram_en              <=  1;
                feature_bram_we              <=  0;     
              end
              /*change bram read address*/
              //when reference clock > 0 , reference clock < (double_width / 4)
              //get feature_bram[0]  -> feature_bram[width / 2 -1] : which fulls  FB5 below       
              else if( (prd_ref_cnt > 0) & (prd_ref_cnt < (width >> 1)+1)) begin
                if(feature_bram_addr  ==  (input_len  * width * width /4)-1)
                  feature_bram_addr          <=  0;
                else 
                  feature_bram_addr            <=  feature_bram_addr  + 1;
                feature_bram_din             <=  0;
                feature_bram_en              <=  1;
                feature_bram_we              <=  0;                   
              end
              // last data of FB5 : stop increasing feature bram address
              else if(prd_ref_cnt > (width >> 1) || SENDING) begin
                feature_bram_addr            <=  feature_bram_addr;
                feature_bram_din             <=  0;
                feature_bram_en              <=  1;
                feature_bram_we              <=  0;                
              end

              //2. generate control signals
              
              Feature_BRAM_out_addr_temp  <=  feature_bram_addr ;
              IFB_FB5_INDEX               <=  Feature_BRAM_out_addr_temp %  (width >> 1) ;
              
              //when DOUT of feature bram is valid : cnt== 3 ~ width/2 + 2 . So turn on at 2, turn off at width/2 + 2 
              if( (prd_ref_cnt > 1) & (prd_ref_cnt < (width >> 1) +2 ) ) begin
                FEATURE_BRAM_DOUT_VALID <=  1;
              end
              else begin
                FEATURE_BRAM_DOUT_VALID <=  0;
              end

              //FB shifting condition : When MAC-4 width calculation done && reading FB5 done
              if( (IFB_FB5_FILL_DONE && MAC_IDLE) || MAC_DONE )begin
                IFB_SHIFTING_CONDITION  <=  1;                
              end
              else begin
                IFB_SHIFTING_CONDITION  <=  0;
              end

              // When we are filling FB5 end of image <= FB shifting condition && height_cnt is  width/2 -1
              if( ( (IFB_FB5_FILL_DONE && MAC_IDLE) || MAC_DONE) && ( prd_feature_height_cnt == (width >> 1 ) - 1) ||((prd_feature_height_cnt  ==  width/2 +1) && (prd_ref_cnt  ==  (width >> 1)+4)) )begin
                IFB_END_OF_ONE_IMAGE  <=  !IFB_END_OF_ONE_IMAGE;                
              end
              else begin
                IFB_END_OF_ONE_IMAGE  <=  IFB_END_OF_ONE_IMAGE;
              end              
              
              //if we finished working with one image 
              if(SEND_ONE_IMAGE_DONE) begin
                IFB_RESET <=  1;
              end 
              else begin
                IFB_RESET <=  0;
              end
              
              
              MAC_out_row==0 && MAC_out_col==0&&MAC_OUT_VALID
$display("mac_output : ",MAC_OUTPUT);

prd_filter_cnt
$display("---------   ",prd_feature_image_cnt ,"    -------------------------------");
$display("filter_num : ",prd_filter_cnt, "height : ",prd_feature_height_cnt );
$display(" col ",kernel_col," row ",kernel_row);
$display("    F              W         ");
$display(" 0 : ",FB0 [kernel_col+0]," ", KWB[0]);
$display(" 1 : ",FB0 [kernel_col+1]," ", KWB[1]);
$display(" 2 : ",FB0 [kernel_col+2]," ", KWB[2]);
$display(" 3 : ",FB1 [kernel_col+0]," ", KWB[3]);
$display(" 4 : ",FB1 [kernel_col+1]," ", KWB[4]);
$display(" 5 : ",FB1 [kernel_col+2]," ", KWB[5]);
$display(" 6 : ",FB2 [kernel_col+0]," ", KWB[6]);
$display(" 7 : ",FB2 [kernel_col+1]," ", KWB[7]);
$display(" 8 : ",FB2 [kernel_col+2]," ", KWB[8]);
$display(" bias : ",OFM[kernel_row][kernel_col]," sum : ",FB0 [kernel_col+0]*KWB[0]+FB0 [kernel_col+1]*KWB[1]+FB0 [kernel_col+2]*KWB[2]+FB1 [kernel_col+0]*KWB[3]+FB1 [kernel_col+1]*KWB[4]+FB1 [kernel_col+2]*KWB[5]+FB2 [kernel_col+0]*KWB[6]+FB2 [kernel_col+1]*KWB[7]+FB2 [kernel_col+2]*KWB[8]);
$display("output value : ",{OFM[kernel_row][kernel_col][31],OFM[kernel_row][kernel_col][12:6]}   );
$display("next bias : ",OFM[kernel_row][kernel_col]+FB0 [kernel_col+0]*KWB[0]+FB0 [kernel_col+1]*KWB[1]+FB0 [kernel_col+2]*KWB[2]+FB1 [kernel_col+0]*KWB[3]+FB1 [kernel_col+1]*KWB[4]+FB1 [kernel_col+2]*KWB[5]+FB2 [kernel_col+0]*KWB[6]+FB2 [kernel_col+1]*KWB[7]+FB2 [kernel_col+2]*KWB[8]);




$display("weight_bram input" );





              /************************************************************************************************/
              /*   Communication with Kernel weight buffer     */              

              //1. weight bram control
              /*initial bram input*/
              if(prd_ref_cnt2==0 && (prd_feature_height_cnt==0) ) begin
                //// feature_bram start address : (filter cnt * 3x3 * input_len + image_cnt * 3x3 )  / 4
                weight_bram_addr            <=  ((prd_filter_cnt * input_len + prd_feature_image_cnt) * 9) >> 2 ;
                weight_bram_din             <=  0;
                weight_bram_en              <=  1;
                weight_bram_we              <=  0;     
              end
              /*change bram read address*/
              //when reference clock > 0 , reference clock < 3x3
              //get feature_bram[0]  -> feature_bram[2] : 
              else if( ((KWB_START_POINT==0 && prd_ref_cnt2==1) || (prd_ref_cnt2 > 0)) & (prd_ref_cnt2 < 3 ) ) begin
                weight_bram_addr            <=  weight_bram_addr  + 1;
                weight_bram_din             <=  0;
                weight_bram_en              <=  1;
                weight_bram_we              <=  0;                   
              end
              // last data of FB5 : stop increasing feature bram address
              else if(prd_ref_cnt >= 3 ) begin
                weight_bram_addr            <=  weight_bram_addr;
                weight_bram_din             <=  0;
                weight_bram_en              <=  1;
                weight_bram_we              <=  0;                
              end

              //2. generate control signals

              // KWB_INDEX : 0 ~ 8  . index of Kernel weight buffer. 
              if( prd_ref_cnt2 > 2 & prd_ref_cnt2 < 3 + 2 ) begin
                KWB_INDEX <=  KWB_INDEX + 1;
              end
              else begin
                KWB_INDEX <=  0;
              end

              //when DOUT of weight bram is valid : cnt== 3 ~ 9 + 2 . So turn on at 2, turn off at 3 + 2 
              if( (prd_ref_cnt2 >= 2) & (prd_ref_cnt2 < 3 + 2 ) && (prd_feature_height_cnt==0)) begin
                KWB_WEIGHT_BRAM_VALID <=  1;
              end
              else begin
                KWB_WEIGHT_BRAM_VALID <=  0;
              end

              KWB_START_POINT <=  ((prd_filter_cnt * input_len + prd_feature_image_cnt) * 9) % 4;
              /****************************************************************/
              /*Communicate with AXI_STREAM MASTER interface*/
              if ( (MAC_out_row == width - 1) & MAC_DONE && (prd_feature_image_cnt  == input_len - 1))begin
                SEND_ONE_IMAGE_START  <=  1;
                SENDING               <=  1;
              end
              else begin
                SEND_ONE_IMAGE_START  <=  0;
              end
              if(SEND_ONE_IMAGE_DONE)
                SENDING               <=  0;



            end
            /*IDLE : flush all*/
            else begin
            // Here Must be same with reset !!!!!!!!!
              resume_receive_weight         <=  0;
              resume_receive_weight_cnt     <=  resume_receive_weight_cnt;

              feature_bram_addr             <=  0;
              feature_bram_din              <=  0;
              feature_bram_en               <=  0;
              feature_bram_we               <=  0;

              bias_bram_addr                <=  0;
              bias_bram_din                 <=  0;
              bias_bram_en                  <=  0;
              bias_bram_we                  <=  0;

              weight_bram_addr              <=  0;
              weight_bram_din               <=  0;
              weight_bram_en                <=  0;
              weight_bram_we                <=  0;

              /*control signals to input feature buffer*/
              IFB_FB5_INDEX                 <=  0;
              FEATURE_BRAM_DOUT_VALID       <=  0;
              IFB_SHIFTING_CONDITION        <=  0;
              IFB_END_OF_ONE_IMAGE          <=  0;   
              IFB_RESET                     <=  0;   

              /*control signals to kernel weight buffer*/
              KWB_INDEX                     <=  0;
              KWB_WEIGHT_BRAM_VALID         <=  0;
              KWB_START_POINT               <=  0;

              /*Signals to MAC_Controller*/
              MAC_START                     <=  0;
              OFM_BIAS_VALID                <=  0;

              /*Signals to AXIS_MASTER*/
              SEND_ONE_IMAGE_START          <=  0;

              /*internal regs*/
              prd_filter_cnt                <=  0;
              prd_feature_image_cnt         <=  0;
              prd_feature_height_cnt        <=  0;
              prd_ref_cnt                   <=  0;
              prd_ref_cnt2                  <=  0;        

              Feature_BRAM_out_addr_temp    <=  0;         

              /*signal to output */
              conv_done                     <=  0;           
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
  *                      Feature_BRAM   or ZEROS (Bottom padding)                   
  *       
  ***************************************************************/

  /*Signals from BRAM_controller*/
  //  reg [15:0]  IFB_FB5_INDEX; 
  //  reg FEATURE_BRAM_DOUT_VALID; 
  //  reg IFB_SHIFTING_CONDITION;
  //  reg IFB_END_OF_ONE_IMAGE;
  //  reg IFB_RESET;

  /*Signals to BRAM_controller*/  
  //  reg IFB_FB5_FILL_DONE;
   

  /*DATA to MAC */
  parameter MAX_WIDTH=32;
  reg [7:0] FB0 [MAX_WIDTH+1:0];    // 33:0
  reg [7:0] FB1 [MAX_WIDTH+1:0];
  reg [7:0] FB2 [MAX_WIDTH+1:0];
  reg [7:0] FB3 [MAX_WIDTH+1:0];

  /*Internal registers */  
  reg [7:0] FB4 [MAX_WIDTH-1:0];
  reg [7:0] FB5 [2*MAX_WIDTH-1:0];   
     

  /*FB0~4 : Shifting logics */
    genvar j;
    generate 
      for (j=0 ; j<=MAX_WIDTH+1 ; j=j+1) begin : FB_blocks
       always @(posedge clk or negedge rstn) begin
          if (!rstn) begin
            FB0[j]  <=  0;
            FB1[j]  <=  0;
            FB2[j]  <=  0;
            FB3[j]  <=  0;
            FB4[j]  <=  0;
          end
          else if (RECEIVE_STATE == `STATE_IDLE) begin
            FB0[j]  <=  0;
            FB1[j]  <=  0;
            FB2[j]  <=  0;
            FB3[j]  <=  0;
            FB4[j]  <=  0;
          end
          //Before starting new image, fill all with zero-padding
          else begin 
            if(IFB_RESET)begin
              FB0[j]  <=  0;
              FB1[j]  <=  0;
              FB2[j]  <=  0;
              FB3[j]  <=  0;
              FB4[j]  <=  0;          
            end        
            //when shifting condition
            else if(IFB_SHIFTING_CONDITION) begin
              FB0[j]  <=  FB2[j];
              FB1[j]  <=  FB3[j];        
              /*j==0, j>width : alwyas 0 (padding)*/
              if( (j != 0) && (j <= width) ) begin
                FB2[j]  <=  FB4[j];        
                FB3[j]  <=  FB5[j-1];
                FB4[j]  <=  FB5[j+width-1];
              end
if(prd_feature_height_cnt==o or prd_feature_height_cnt == 1 or prd_feature_height_cnt ==1) begin
  $display ("@@@@@@@@@@@@@@@@@@   FB   height = %h      @@@@@@", prd_feature_height_cnt);

  $display("FB0 %h %h %h %h // %h %h %h %h", FB0[0],FB0[1],FB0[2],FB0[3],FB0[4],FB0[5],FB0[6],FB0[7],FB0[8]);
  $display("FB0 %h %h %h %h // %h %h %h %h", FB1[0],FB1[1],FB1[2],FB1[3],FB1[4],FB1[5],FB1[6],FB1[7],FB1[8]);
  $display("FB0 %h %h %h %h // %h %h %h %h", FB2[0],FB2[1],FB2[2],FB2[3],FB2[4],FB2[5],FB2[6],FB2[7],FB2[8]);
  $display("FB0 %h %h %h %h // %h %h %h %h", FB3[0],FB3[1],FB3[2],FB3[3],FB3[4],FB3[5],FB3[6],FB3[7],FB3[8]);
  $display("");
end





            end
          end
        end
      end 
    endgenerate

  /*FB5 : get features from feature_bram */
    // get double width per once
    genvar k;
    generate 
      for (k=0; k<2*MAX_WIDTH; k=k+1) begin : FB5_blocks
        always @(posedge clk or negedge rstn) begin
          if(!rstn) begin
            FB5[k]  <=  0;
          end
          else if (RECEIVE_STATE == `STATE_IDLE) begin
            FB5[k]  <=  0;
          end
          else begin
            /*when end of image,  put bottom padding*/
            if(IFB_END_OF_ONE_IMAGE) begin 
              FB5[k]  <=  0;
            end
            // when k matches with index of delayed BRAM addres and BRAM output is valid
            else if( ( (k/4) == IFB_FB5_INDEX ) & FEATURE_BRAM_DOUT_VALID ) begin
              FB5[k]  <=  feature_bram_dout[(k%4)*8+7-:8]; // k%4 = 0: [7:0] 1: [15:8] ...3: [31:24]
            end          
          end
        end
      end 
    endgenerate
    
    /*send IFB_FB5_FILL_DONE signal to BRAM_controller*/
    always @(posedge clk or negedge rstn) begin
      if(!rstn) begin
        IFB_FB5_FILL_DONE <=  0;
      end
      else if (RECEIVE_STATE == `STATE_IDLE)begin
        IFB_FB5_FILL_DONE <=  0;
      end
      else begin
        //FB5 fill done condition      
        if((FEATURE_BRAM_DOUT_VALID || IFB_END_OF_ONE_IMAGE) && (IFB_FB5_INDEX == (width >> 1) - 2 )) begin
          IFB_FB5_FILL_DONE <=  1;
        end
        else begin
          IFB_FB5_FILL_DONE <=  0;
        end
      end
    end

  /*************************************************************************
  *      KERNEL WEIGHT BUFFER
  *  hold 3x3 kernel weights
  *   
  *   KWB[i][j] contains ith kernel's jth weight
  *   Use KWB as weight input for MAC
  *
  ***************************************************************/
  /*Signals from    BRAM_controller*/
    //  reg [7:0] KWB_INDEX;
    //  reg KWB_WEIGHT_BRAM_VALID;
    //  reg[2:0] KWB_START_POINT
  reg signed [7:0] KWB[8:0];

    always @(posedge clk or negedge rstn) begin
      if(!rstn) begin
        KWB[0] <=  0;      
        KWB[1] <=  0;
        KWB[2] <=  0;
        KWB[3] <=  0;
        KWB[4] <=  0;
        KWB[5] <=  0;
        KWB[6] <=  0;
        KWB[7] <=  0;
        KWB[8] <=  0;  
      end
      else if (RECEIVE_STATE == `STATE_IDLE) begin
        KWB[0] <=  0;      
        KWB[1] <=  0;
        KWB[2] <=  0;
        KWB[3] <=  0;
        KWB[4] <=  0;
        KWB[5] <=  0;
        KWB[6] <=  0;
        KWB[7] <=  0;
        KWB[8] <=  0; 
      end
      else begin
        if(KWB_WEIGHT_BRAM_VALID) begin
          case (KWB_START_POINT)
if(prd_filter_cnt==0) begin
$display("_*_*_*_*_*_*_kwb start point : ",KWB_START_POINT, "index" ,KWB_INDEX ,"bram output : %h",weight_bram_dout);
end



            0: begin
              case (KWB_INDEX)
                0: begin
                  KWB[0] <=  weight_bram_dout[7:0];
                  KWB[1] <=  weight_bram_dout[15:8];
                  KWB[2] <=  weight_bram_dout[23:16];
                  KWB[3] <=  weight_bram_dout[31:24];
                end
                1: begin
                  KWB[4] <=  weight_bram_dout[7:0];
                  KWB[5] <=  weight_bram_dout[15:8];
                  KWB[6] <=  weight_bram_dout[23:16];
                  KWB[7] <=  weight_bram_dout[31:24];
                end
                2: begin
                  KWB[8] <=  weight_bram_dout[7:0];
                end
                default: begin
                /*Never come here*/            
                  $display("Control flow error detected in KWB_INDEX");
                  $stop;  
                end
              endcase              
            end
            1: begin
              case (KWB_INDEX)
                0: begin
                  KWB[0] <=  weight_bram_dout[15:8];
                  KWB[1] <=  weight_bram_dout[23:16];
                  KWB[2] <=  weight_bram_dout[31:24];
                end
                1: begin
                  KWB[3] <=  weight_bram_dout[7:0];
                  KWB[4] <=  weight_bram_dout[15:8];
                  KWB[5] <=  weight_bram_dout[23:16];
                  KWB[6] <=  weight_bram_dout[31:24];
                end
                2: begin
                  KWB[7] <=  weight_bram_dout[7:0];
                  KWB[8] <=  weight_bram_dout[15:8];
                end
                default: begin
                /*Never come here*/            
                  $display("Control flow error detected in KWB_INDEX");
                  $stop;  
                end
              endcase              
            end            
            2: begin
              case (KWB_INDEX)
                0: begin
                  KWB[0] <=  weight_bram_dout[23:16];
                  KWB[1] <=  weight_bram_dout[31:24];
                end
                1: begin
                  KWB[2] <=  weight_bram_dout[7:0];
                  KWB[3] <=  weight_bram_dout[15:8];
                  KWB[4] <=  weight_bram_dout[23:16];
                  KWB[5] <=  weight_bram_dout[31:24];
                end
                2: begin
                  KWB[6] <=  weight_bram_dout[7:0];
                  KWB[7] <=  weight_bram_dout[15:8];
                  KWB[8] <=  weight_bram_dout[23:16];
                end
                default: begin
                /*Never come here*/            
                  $display("Control flow error detected in KWB_INDEX");
                  $stop;  
                end
              endcase              
            end
            3: begin
              case (KWB_INDEX)
                0: begin
                  KWB[0] <=  weight_bram_dout[31:24];
                end
                1: begin
                  KWB[1] <=  weight_bram_dout[7:0];
                  KWB[2] <=  weight_bram_dout[15:8];
                  KWB[3] <=  weight_bram_dout[23:16];
                  KWB[4] <=  weight_bram_dout[31:24];
                end
                2: begin
                  KWB[5] <=  weight_bram_dout[7:0];
                  KWB[6] <=  weight_bram_dout[15:8];
                  KWB[7] <=  weight_bram_dout[23:16];
                  KWB[8] <=  weight_bram_dout[31:24];
                end
                default: begin
                /*Never come here*/            
                  $display("Control flow error detected in KWB_INDEX");
                  $stop;  
                end
              endcase              
            end
            default: begin
            /*Never come here*/            
              $display("Control flow error detected in KWB_START_POINT");
              $stop;  
            end
          endcase

        end
      end      
    end


  /*******************************************************************/
  /*MAC controller
  *   MAC controller moves kernel : 
  *   FB0 |  * * *    
  *   FB1 |  * * *  - - - >    * * *    
  *   FB2 |  * * *             * * *  - - - > 
  *   FB3 |                    * * *            
  */
    //  /*Signals to MAC_Controller*/
    //  reg MAC_START;
    //  /*Signals from MAC_Controller*/
    //  reg MAC_DONE;
    //  reg MAC_IDLE;
        /*signals from AXI_STREAM MASTER interface*/
    //  reg SEND_ONE_IMAGE_DONE;

  /*Signals to output_feature_map*/
  reg MAC_OUT_VALID;

  /*position of kernel*/
  reg [5:0] kernel_row;
  reg [5:0] kernel_col;
  wire MAC_INPUT_ROW = kernel_row [0];
  /*position of  MAC output : MAC delay is 4 !!*/
  //  reg [5:0] MAC_out_row;
  //  reg [5:0] MAC_out_col;

  reg [7:0] MAC_INPUT_FEATURE [8:0];

  reg [9:0] MAC_REF_CNT; // reference counter for easier timing

  reg         MAC_EN;
  reg [31:0]  MAC_bias;
  wire [31:0] MAC_OUTPUT;   
  reg signed [31:0] OFM[MAX_WIDTH-1:0][MAX_WIDTH-1:0];   //OFM [row][col]
  
    /*MAC controller main control block*/
    always @(posedge clk or negedge rstn) begin
      if(!rstn) begin
        MAC_DONE              <=  0;  
        MAC_IDLE              <=  1;

        MAC_OUT_VALID         <=  0;

        kernel_row            <=  0;
        kernel_col            <=  0;
        MAC_out_row           <=  0;
        MAC_out_col           <=  0;

        MAC_INPUT_FEATURE[0]  <=  0;
        MAC_INPUT_FEATURE[1]  <=  0;
        MAC_INPUT_FEATURE[2]  <=  0;
        MAC_INPUT_FEATURE[3]  <=  0;
        MAC_INPUT_FEATURE[4]  <=  0;
        MAC_INPUT_FEATURE[5]  <=  0;
        MAC_INPUT_FEATURE[6]  <=  0;
        MAC_INPUT_FEATURE[7]  <=  0;
        MAC_INPUT_FEATURE[8]  <=  0;

        MAC_REF_CNT           <=  0;
        MAC_EN                <=  0;
        MAC_bias              <=  0;
      end
      else if (RECEIVE_STATE == `STATE_IDLE)begin
        MAC_DONE              <=  0;  
        MAC_IDLE              <=  1;

        MAC_OUT_VALID         <=  0;

        kernel_row            <=  0;
        kernel_col            <=  0;
        MAC_out_row           <=  0;
        MAC_out_col           <=  0;

        MAC_INPUT_FEATURE[0]  <=  0;
        MAC_INPUT_FEATURE[1]  <=  0;
        MAC_INPUT_FEATURE[2]  <=  0;
        MAC_INPUT_FEATURE[3]  <=  0;
        MAC_INPUT_FEATURE[4]  <=  0;
        MAC_INPUT_FEATURE[5]  <=  0;
        MAC_INPUT_FEATURE[6]  <=  0;
        MAC_INPUT_FEATURE[7]  <=  0;
        MAC_INPUT_FEATURE[8]  <=  0;

        MAC_REF_CNT           <=  0;
        MAC_EN                <=  0;
        MAC_bias              <=  0;
      end
      else begin
        if( MAC_IDLE  ) begin
          if( MAC_START) begin
            MAC_IDLE  <=  0;
          end
          else begin
            MAC_IDLE  <=  1;
          end
          // refresh row when one image done
          if( SENDING || SEND_ONE_IMAGE_DONE  ) begin
            kernel_row    <=  0;
            MAC_out_row   <=  0;
          end
          // otherwise, remember current row
          else begin
            kernel_row    <=  kernel_row ;
            MAC_out_row   <=  MAC_out_row;            
          end
          // flush rest 
          kernel_col            <=  0;
          MAC_out_col           <=  0;
          MAC_DONE              <=  0;  
          MAC_OUT_VALID         <=  0;
          MAC_INPUT_FEATURE[0]  <=  0;
          MAC_INPUT_FEATURE[1]  <=  0;
          MAC_INPUT_FEATURE[2]  <=  0;
          MAC_INPUT_FEATURE[3]  <=  0;
          MAC_INPUT_FEATURE[4]  <=  0;
          MAC_INPUT_FEATURE[5]  <=  0;
          MAC_INPUT_FEATURE[6]  <=  0;
          MAC_INPUT_FEATURE[7]  <=  0;
          MAC_INPUT_FEATURE[8]  <=  0;

          MAC_REF_CNT           <=  0;
          MAC_EN                <=  0;
          MAC_bias              <=  0;
        end

        /*After we receive MAC_START signal : using MAC*/
        else begin
          MAC_REF_CNT <=  MAC_REF_CNT + 1;

          // kernel_row init condition
          if( SEND_ONE_IMAGE_DONE) begin
            kernel_row  <=  0;
          end
          // kernel_row update condition
          else if ( ( MAC_REF_CNT ==  width - 1 ) || ( MAC_REF_CNT == 2* width - 1) ) begin
            if(kernel_row ==  width - 1)
              kernel_row  <=  0;
            else
              kernel_row  <=  kernel_row  + 1;
          end

          // kernel_col init condition
          if (MAC_REF_CNT == width -1| ( MAC_REF_CNT == 2* width - 1)) begin
            kernel_col      <=  0;
          end
          else begin
            kernel_col  <=  kernel_col + 1;
          end

          // MAC_out_row init condition
          if( SEND_ONE_IMAGE_DONE ) begin
            MAC_out_row  <=  0;
          end
          if( MAC_out_col ==  (width -1)) begin
            if(MAC_out_row  ==  width - 1)
              MAC_out_row <=  0;
            else
              MAC_out_row  <=  MAC_out_row  + 1;
          end
          // MAC_out_row update condition
          /*else if ( ( MAC_REF_CNT ==  width + 4 ) || ( MAC_REF_CNT == 2* width + 4 ) ) begin
            MAC_out_row  <=  MAC_out_row  + 1;
          end*/

          // MAC_out_col init condition
          if (MAC_REF_CNT <= 4 | MAC_REF_CNT == width + 4 | MAC_out_col ==  width-1  ) begin
             // MAC_out_row init condition
            MAC_out_col  <=  0;
          end
          else begin
            MAC_out_col  <=  MAC_out_col + 1;
          end

         
          // assign mac input
          if(MAC_INPUT_ROW == 0 ) begin
            // first row
            MAC_INPUT_FEATURE[0]  <=  FB0[kernel_col+0];
            MAC_INPUT_FEATURE[1]  <=  FB0[kernel_col+1];
            MAC_INPUT_FEATURE[2]  <=  FB0[kernel_col+2];

            MAC_INPUT_FEATURE[3]  <=  FB1[kernel_col+0];
            MAC_INPUT_FEATURE[4]  <=  FB1[kernel_col+1];
            MAC_INPUT_FEATURE[5]  <=  FB1[kernel_col+2];

            MAC_INPUT_FEATURE[6]  <=  FB2[kernel_col+0];
            MAC_INPUT_FEATURE[7]  <=  FB2[kernel_col+1];
            MAC_INPUT_FEATURE[8]  <=  FB2[kernel_col+2];            
          end
          else begin
            // second row
            MAC_INPUT_FEATURE[0]  <=  FB1[kernel_col+0];
            MAC_INPUT_FEATURE[1]  <=  FB1[kernel_col+1];
            MAC_INPUT_FEATURE[2]  <=  FB1[kernel_col+2];

            MAC_INPUT_FEATURE[3]  <=  FB2[kernel_col+0];
            MAC_INPUT_FEATURE[4]  <=  FB2[kernel_col+1];
            MAC_INPUT_FEATURE[5]  <=  FB2[kernel_col+2];
            
            MAC_INPUT_FEATURE[6]  <=  FB3[kernel_col+0];
            MAC_INPUT_FEATURE[7]  <=  FB3[kernel_col+1];
            MAC_INPUT_FEATURE[8]  <=  FB3[kernel_col+2]; 
          end
          MAC_bias                <=  OFM[kernel_row][kernel_col];

          // always enable MAC
          if(1) begin
            MAC_EN  <=  1;            
          end
          else begin
            MAC_EN  <=  0;
          end

          // MAC_out_valid condition
          if(MAC_REF_CNT  >= 4 && MAC_REF_CNT <= width * 2 + 3) begin
            MAC_OUT_VALID  <=  1;            
          end
          else begin
            MAC_OUT_VALID  <=  0;
          end

          // MAC calculation done condition
          if(MAC_REF_CNT  ==  width * 2 + 3 ) begin
            MAC_DONE  <=  1;
          end
          else begin
            MAC_DONE  <=  0;
          end
          // MAC calculation done condition
          if(MAC_REF_CNT  ==  width * 2 + 4) begin
            MAC_IDLE  <=  1;
          end
          else begin
            MAC_IDLE  <=  0;
          end
        end
      end
    end


      /*MAC*/
    mac3x3  conv_mac(
      .clk(clk),
      .en(MAC_EN),
      .rstn(rstn),
      .bias(MAC_bias),
      .w0(KWB[0]),
      .w1(KWB[1]),
      .w2(KWB[2]),
      .w3(KWB[3]),
      .w4(KWB[4]),
      .w5(KWB[5]),
      .w6(KWB[6]),
      .w7(KWB[7]),
      .w8(KWB[8]),
      .f0(MAC_INPUT_FEATURE[0]),
      .f1(MAC_INPUT_FEATURE[1]),
      .f2(MAC_INPUT_FEATURE[2]),
      .f3(MAC_INPUT_FEATURE[3]),
      .f4(MAC_INPUT_FEATURE[4]),
      .f5(MAC_INPUT_FEATURE[5]),
      .f6(MAC_INPUT_FEATURE[6]),
      .f7(MAC_INPUT_FEATURE[7]),
      .f8(MAC_INPUT_FEATURE[8]),
      .mout(MAC_OUTPUT)
    );
  


  /************************************************************/
  /*OUTPUT_FEATURE_MAP
  *     col1 col2
  * row1
  * row2
  *
  */

  /*Signals from BRAM_CONTROLLER*/
    //reg OFM_BIAS_VALID; //bias valid signal.
    //reg [2:0]prd_filter_cnt;

  /*Signals from MAC_controller*/
    //  reg [5:0] MAC_out_row;
    //  reg [5:0] MAC_out_col;
    //  reg update_feature_map;
    //  wire [31:0] MAC_OUTPUT;
    

//reg signed [31:0] OFM[MAX_WIDTH-1:0][MAX_WIDTH-1:0];   //OFM [row][col]
  wire signed [7:0] bias_tmp = bias_bram_dout[prd_filter_cnt*8+7-:8];
  wire signed [31:0] feature_map_bias = {{19{bias_tmp[7]}}, bias_tmp[6:0], 6'b0};

  genvar row;
  genvar col;
  generate 
    for ( row=0 ; row<MAX_WIDTH ; row=row+1 ) begin: row_block
      for (col=0 ; col<MAX_WIDTH ; col=col+1) begin: col_block
        always @(posedge clk or negedge rstn) begin
          if(!rstn) begin
            OFM[row][col]<=0;
          end
          else if(RECEIVE_STATE == `STATE_IDLE) begin
            OFM[row][col]<=0;
          end
          // set bias at start of new image
          else if(OFM_BIAS_VALID) begin
            OFM[row][col]<=feature_map_bias;
          end        
          else begin
            // accumulate MAC output
            if(MAC_OUT_VALID && (MAC_out_row == row) && (MAC_out_col == col)) begin
              OFM[row][col] <= MAC_OUTPUT;
            end
          end
        end
      end
    end 
  endgenerate

  /****************************************************************************/
  /*AXI_stream Master interface : send data*/

  //    /*Signals from BRAM_controller*/
  //    reg SEND_ONE_IMAGE_START;

  //    /*Signals To BRAM_CONTROLLER*/
  //    reg SEND_ONE_IMAGE_DONE;
  reg AXIS_M_IDLE;
  reg [4:0] send_row;
  reg [4:0] send_col;
  reg [8:0]  out_len_count;
  always@(posedge clk or negedge rstn) begin  /////////////
    if(!rstn) begin
      SEND_ONE_IMAGE_DONE <=  0;
      AXIS_M_IDLE         <=  1;    
    end
    else if (RECEIVE_STATE == `STATE_IDLE)begin
      SEND_ONE_IMAGE_DONE <=  0;
      AXIS_M_IDLE         <=  1;  
    end
    else begin
      // idle state
      if (AXIS_M_IDLE) begin
        //go to work state
        if(SEND_ONE_IMAGE_START) begin
          AXIS_M_IDLE <=  0;
        end
        else begin
          AXIS_M_IDLE <=  1;
        end

        // hold out_len_count
        //flush rest 
        SEND_ONE_IMAGE_DONE <=  0;
      end
      // work state
      else begin
        // send one image done condition
        if((send_row  ==  width-1)  &&  (send_col  ==  width-4))  begin
          SEND_ONE_IMAGE_DONE <=  1;
          AXIS_M_IDLE         <=  1;
        end
        else begin
          SEND_ONE_IMAGE_DONE <=  0;
          AXIS_M_IDLE         <=  0;
        end
      end
    end
  end

  always@(posedge clk or negedge rstn) begin  /////////////
    if(!rstn) begin
      send_row      <=  0;
      send_col      <=  0;
      m_axis_tvalid <=  0;
      m_axis_tdata  <=  0;
      out_len_count <=  0;
      m_axis_tlast  <=  0;
    end
    else if(RECEIVE_STATE == `STATE_IDLE) begin
      send_row      <=  0;
      send_col      <=  0;
      m_axis_tvalid <=  0;
      m_axis_tdata  <=  0;
      out_len_count <=  0;
      m_axis_tlast  <=  0;
    end
    else if(!SENDING) begin
      send_row      <=  0;
      send_col      <=  0;
      m_axis_tvalid <=  0;
      m_axis_tdata  <=  0;
      m_axis_tlast  <=  0;
      out_len_count <=  out_len_count;
    end
    else if(!AXIS_M_IDLE && M_AXIS_TREADY)begin //relu
        m_axis_tdata[7:0]   <=  (OFM[send_row][send_col][31]  ? 0 :  (({18{OFM[send_row][send_col][31]}}   ==  OFM[send_row][send_col][30:13])   ?  {OFM[send_row][send_col][31]   ,OFM[send_row][send_col][12:6]}  :{OFM[send_row][send_col][31]   ,{7{!OFM[send_row][send_col][31]  }}}));
        m_axis_tdata[15:8]  <=  (OFM[send_row][send_col+1][31]? 0 :  (({18{OFM[send_row][send_col+1][31]}} ==  OFM[send_row][send_col+1][30:13]) ?  {OFM[send_row][send_col+1][31] ,OFM[send_row][send_col+1][12:6]}:{OFM[send_row][send_col+1][31] ,{7{!OFM[send_row][send_col+1][31]}}}));
        if(send_col==width-2)begin
          m_axis_tdata[23:16] <=  (OFM[send_row+1][0][31]? 0 :  (({18{OFM[send_row+1][0][31]}} ==  OFM[send_row+1][0][30:13]) ?  {OFM[send_row+1][0][31] ,OFM[send_row+1][0][12:6]}:{OFM[send_row+1][0][31] ,{7{!OFM[send_row+1][0][31]}}}));                                                                                  
          m_axis_tdata[31:24] <=  (OFM[send_row+1][1][31]? 0 :  (({18{OFM[send_row+1][1][31]}} ==  OFM[send_row+1][1][30:13]) ?  {OFM[send_row+1][1][31] ,OFM[send_row+1][1][12:6]}:{OFM[send_row+1][1][31] ,{7{!OFM[send_row+1][1][31]}}}));
        end
        else begin
          m_axis_tdata[23:16] <=  (OFM[send_row][send_col+2][31]? 0 :  (({18{OFM[send_row][send_col+2][31]}} ==  OFM[send_row][send_col+2][30:13]) ?  {OFM[send_row][send_col+2][31] ,OFM[send_row][send_col+2][12:6]}:{OFM[send_row][send_col+2][31] ,{7{!OFM[send_row][send_col+2][31]}}}));                                                                                  
          m_axis_tdata[31:24] <=  (OFM[send_row][send_col+3][31]? 0 :  (({18{OFM[send_row][send_col+3][31]}} ==  OFM[send_row][send_col+3][30:13]) ?  {OFM[send_row][send_col+3][31] ,OFM[send_row][send_col+3][12:6]}:{OFM[send_row][send_col+3][31] ,{7{!OFM[send_row][send_col+3][31]}}}));
        end
        if(!SEND_ONE_IMAGE_DONE)
            m_axis_tvalid <=  1;
        else
          m_axis_tvalid <=  0;
        if((send_row  ==  width-1)  &&  (send_col  ==  width-4) ) begin//when all output data sent
          out_len_count <=  out_len_count+1;
          send_row      <=  0;
          send_col      <=  0;
          if((out_len_count ==  output_len-1))
            m_axis_tlast  <=  1;
        end
        else begin
          if(send_col == width-2)begin// location update
            send_row    <=  send_row  + 1;
            send_col    <=  2;
          end
          else if (send_col == width-4)begin
            send_row    <=  send_row  + 1;
            send_col    <=  0;
          end
          else begin
            send_row    <=  send_row;
            send_col    <=  send_col  + 4;
          end
          m_axis_tlast  <=  0; 
        end
    end
    else begin
      send_row      <=  0;
      send_col      <=  0;
      m_axis_tvalid <=  0;
      m_axis_tdata  <=  0;
      out_len_count <=  out_len_count;
      m_axis_tlast  <=  0;
    end
  end        
endmodule 