/*pooling layer for CIFAR 10*/
module pool #
(
     parameter integer C_S00_AXIS_TDATA_WIDTH   = 32,
     parameter integer MAX_WIDTH        = 32,
     parameter integer MAX_HEIGHT       = 32
)           
(   //AXI-STREAM
  input wire                                      clk,
  input wire                                      rstn,
  output wire                                     S_AXIS_TREADY,
  input wire [C_S00_AXIS_TDATA_WIDTH-1 : 0]       S_AXIS_TDATA,
  input wire [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0]   S_AXIS_TKEEP,
  input wire                                      S_AXIS_TUSER,
  input wire                                      S_AXIS_TLAST,
  input wire                                      S_AXIS_TVALID,

  
  input wire                                      M_AXIS_TREADY,
  output wire                                     M_AXIS_TUSER,
  output wire [C_S00_AXIS_TDATA_WIDTH-1 : 0]      M_AXIS_TDATA,
  output wire [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0]  M_AXIS_TKEEP,
  output wire                                     M_AXIS_TLAST,
  output wire                                     M_AXIS_TVALID,
  
  
   //APB Control signals
  input                                           pool_start_external,  

  input    [7:0]                                  width_external,
  input    [8:0]                                  length_external,
  input    [7:0]                                  height_external,

  output reg                                      pool_done
);
  reg                                           m_axis_tuser;
  reg [C_S00_AXIS_TDATA_WIDTH-1 : 0]            m_axis_tdata;
  reg [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0]        m_axis_tkeep;
  reg                                           m_axis_tlast;
  reg                                           m_axis_tvalid;
  wire                                          s_axis_tready;

  assign S_AXIS_TREADY = s_axis_tready;
  assign M_AXIS_TDATA = m_axis_tdata;
  assign M_AXIS_TLAST = m_axis_tlast;
  assign M_AXIS_TVALID = m_axis_tvalid;
  assign M_AXIS_TUSER = 1'b0;
  assign M_AXIS_TKEEP = {(C_S00_AXIS_TDATA_WIDTH/8) {1'b1}}; 


  /************************************************************/
  /*buffering external signals */
  reg pool_start;
  reg [7:0] width;
  reg [8:0] length;
  reg [7:0] height;
  wire reset=!rstn  | !pool_start | pool_done;  
    always @(posedge clk or negedge rstn) begin
      if(!rstn  | !pool_start_external) begin
      pool_start  <=  0;
      width       <=  0;
      length      <=  0; 
      height      <=  0;
      end
      else begin
          pool_start  <=  pool_start_external;
          width       <=  width_external;
          length      <=  length_external;
          height      <=  height_external;
      end
    end
  /************************************************************/
  /*AXI_stream Slave interface : receiving data*/
  reg [C_S00_AXIS_TDATA_WIDTH-1 : 0]  receive_buf; //31:0 , 4 of 8-bit datas
  reg [10:0] receive_cnt;//when 0, S_AXIS_TDATA has data0~3 
  reg receive_done;
  reg s_axis_tready_reg;
  reg data_received;  // flag that indicates we recieved data this cycle

  assign s_axis_tready=s_axis_tready_reg;
    /*receive data*/
    always @(posedge clk) begin
      if(reset) begin
        receive_buf   <=  0; 
        receive_cnt   <=  0;
        receive_done  <=  0;
        data_received  <=  0;
        s_axis_tready_reg <=  0;
      end
      else begin
        if(pool_start & ! receive_done)begin
          s_axis_tready_reg <=  1;
        end
        /*valid data receive*/      
        if(s_axis_tready  &  S_AXIS_TVALID  & M_AXIS_TREADY) begin  // M_AXIS_TREADY : for preventing buffer overflow below
          receive_buf   <=  S_AXIS_TDATA;
          data_received  <=  1;  
          if(receive_cnt< (width/2-1)) begin           
              receive_cnt <=  receive_cnt+1;
          end
          else begin
              receive_cnt <=  0;
          end
          if(S_AXIS_TLAST)  begin
            receive_done  <=  1;
          end
        end
        /*data not received*/
        else begin
          data_received  <=  0;
        end
      end
    end
  /************************************************************/

  /*buffering double-width of inputs*/
    // Minimum input width is 14, which is not a multiple of 4. 
    // So we should cut the input by double width.
  reg signed [7:0]double_width_buffer[MAX_WIDTH-1:0]; //for signed comparison
  reg [10:0] receive_cnt_dwb; // buffering receive_cnt to use it here
  reg maxout_end;
  reg data_received_dwb;  // buffering data_received to use it here
    always@(posedge clk) begin
        receive_cnt_dwb   <=  receive_cnt;
        data_received_dwb <=  data_received;
    end
      // Do one comparison of maxout before saving it to double_width_buffer. 
      // This can save use of FF(Flip-Flop)
    wire signed [7:0] d0  = receive_buf[7:0];  
    wire signed [7:0] d1  = receive_buf[15:8];
    wire signed [7:0] d2  = receive_buf[23:16];
    wire signed [7:0] d3  = receive_buf[31:24];

    wire signed [7:0] t0  = d0  > d1  ? d0  : d1;
    wire signed [7:0] t1  = d2  > d3  ? d2  : d3;


      /*check if double_width_buffer is full or not*/
    always @(posedge clk) begin
      if(reset)begin
        maxout_end  <=  0;
      end
      else if(  (receive_cnt_dwb ==  width/2-1) & (data_received) ) begin  //when double_width_buffer is full
        maxout_end  <=  1; 
      end
      else begin
        maxout_end  <=  0;
      end
    end
    
      /*fill double_width_buffer*/
    genvar i;
    generate for(i = 0; i < MAX_WIDTH/2; i = i + 1) begin: fill_double_width_buffer
        always @(posedge clk) begin
          if(reset)begin
            double_width_buffer[2*i]   <=  0;
            double_width_buffer[2*i+1] <=  0;
          end
          else begin
            if( (i < width/2) & (receive_cnt_dwb == i) & data_received ) begin
              double_width_buffer[2*i]   <=  t0;
              double_width_buffer[2*i+1] <=  t1;
            end
          end
        end
      end 
    endgenerate

  /************************************************************/

  /*MAXOUT result*/
  wire signed [7:0] MAXOUT  [MAX_WIDTH/2-1  : 0];
    genvar j;
    generate for(j = 0 ; j < MAX_WIDTH/2; j = j + 1) begin: maxout_result
        assign MAXOUT[j]  = (j < (width >> 1)) ? (double_width_buffer[j] > double_width_buffer[j+width/2] ? double_width_buffer[j] : double_width_buffer[j+width/2]) : 0;
      end 
    endgenerate
  /************************************************************/

  /*Buffer 4 of MAXOUT result to MAXOUT_4x*/
  /* Since minimum width of MAXOUT is 7 which is odd, we need 4 of them to use it in M_AXIS_TDATA */
  // maxout_4x[ 0~width/2-1]  , 16~16+width/2-1 , 32~ 32+width/2-1 , 48 ~ 48+width/2-1



  // 0 , MAX_WIDTH/2 , MAX_WIDTH , MAX_WIDTH/2*3
  reg signed [7:0] MAXOUT_4x [MAX_WIDTH*2-1  : 0];
  reg MAXOUT_4x_full;
    reg [1:0] cnt_4; 
    always@(posedge clk) begin
      if(reset) begin
      cnt_4 <=  0;
      MAXOUT_4x_full  <=  0;
      end
      else  if(maxout_end) begin
        cnt_4 <=  cnt_4 + 1;

        if(cnt_4==2'b11)begin
          MAXOUT_4x_full  <=  1;  //signal that init data send
        end
      end
      else begin
        MAXOUT_4x_full  <=  0;
      end
    end



    genvar k;
    generate
    for (k=0 ; k<MAX_WIDTH/2 ; k=k+1) begin
      always @(posedge clk) begin
        if(reset)begin
          cnt_4 <=  0;
          MAXOUT_4x[k]                  <=  0;
          MAXOUT_4x[k+(MAX_WIDTH/2)]    <=  0;
          MAXOUT_4x[k+(MAX_WIDTH)]      <=  0;
          MAXOUT_4x[k+(MAX_WIDTH/2)*3]  <=  0;
        end
        else begin
          if(maxout_end)begin
            case (cnt_4)
              2'b00: MAXOUT_4x[k]                  <=  MAXOUT[k];
              2'b01: MAXOUT_4x[k+(MAX_WIDTH/2)]    <=  MAXOUT[k];
              2'b10: MAXOUT_4x[k+(MAX_WIDTH)]      <=  MAXOUT[k];
              2'b11: MAXOUT_4x[k+(MAX_WIDTH/2)*3]  <=  MAXOUT[k];
            endcase
          end
        end
      end
    end 
    endgenerate

  /************************************************************/
  /*AXI_stream Master interface : send data*/
  reg [7:0] send_counter;   //  counter for sending datas in MAXOUT_4x
  reg [7:0] send_counter2;  //  counter for counting numbers of MAXOUT_4x  
  reg [31:0]send_data;
  reg send_ready;

    // we send width * 2 of datas at once
    // maxout_4x[ 0~width/2-1]  , 16~16+width/2-1 , 32~ 32+width/2-1 , 48 ~ 48+width/2-1
    // send_counter : 0 ~ width/2-1
    // put this data to send_data using send_counter
    always@(*)begin
      if(width[2:0] == 3'b0) begin
        // width/2 is multiple of 4
        if(send_counter < (width >> 3) ) begin
          send_data[7-:8]   <=  MAXOUT_4x[4*send_counter];
          send_data[15-:8]  <=  MAXOUT_4x[4*send_counter+1];
          send_data[23-:8]  <=  MAXOUT_4x[4*send_counter+2];
          send_data[31-:8]  <=  MAXOUT_4x[4*send_counter+3];          
        end
        else if(send_counter < (width >> 2) ) begin
          send_data[7-:8]   <=  MAXOUT_4x[16+4*send_counter-(width >> 1)];
          send_data[15-:8]  <=  MAXOUT_4x[16+4*send_counter-(width >> 1)+1];
          send_data[23-:8]  <=  MAXOUT_4x[16+4*send_counter-(width >> 1)+2];
          send_data[31-:8]  <=  MAXOUT_4x[16+4*send_counter-(width >> 1)+3];            
        end
        else if(send_counter < (width >> 3) * 3) begin
          send_data[7-:8]   <=  MAXOUT_4x[32+4*send_counter-(width)];
          send_data[15-:8]  <=  MAXOUT_4x[32+4*send_counter-(width)+1];
          send_data[23-:8]  <=  MAXOUT_4x[32+4*send_counter-(width)+2];
          send_data[31-:8]  <=  MAXOUT_4x[32+4*send_counter-(width)+3];              
        end
        else begin
          send_data[7-:8]   <=  MAXOUT_4x[48+4*send_counter-(width >> 1)-(width)];
          send_data[15-:8]  <=  MAXOUT_4x[48+4*send_counter-(width >> 1)-(width)+1];
          send_data[23-:8]  <=  MAXOUT_4x[48+4*send_counter-(width >> 1)-(width)+2];
          send_data[31-:8]  <=  MAXOUT_4x[48+4*send_counter-(width >> 1)-(width)+3];              
        end
      end
      else if(width[2:0] == 3'b100)begin
        //width == 4 (mod8)
        //when sec = 0~ width/8-1
        if(send_counter < (width >> 3))begin // sc < 3
          send_data[7-:8]   <=  MAXOUT_4x[4*send_counter];
          send_data[15-:8]  <=  MAXOUT_4x[4*send_counter+1];
          send_data[23-:8]  <=  MAXOUT_4x[4*send_counter+2];
          send_data[31-:8]  <=  MAXOUT_4x[4*send_counter+3];          
        end
        //when sec = width/8
        else if(send_counter == (width >> 3) ) begin // sc ==3
          send_data[7-:8]   <=  MAXOUT_4x[4*send_counter];
          send_data[15-:8]  <=  MAXOUT_4x[4*send_counter+1];
          send_data[23-:8]  <=  MAXOUT_4x[16];
          send_data[31-:8]  <=  MAXOUT_4x[16+1];            
        end
        // sec = width/8 + 1 ~ width / 4 - 1    
        else if(send_counter < (width >> 2) ) begin // sc < 7
          send_data[7-:8]   <=  MAXOUT_4x[16+4*send_counter-(width >> 1)];
          send_data[15-:8]  <=  MAXOUT_4x[16+4*send_counter-(width >> 1)+1];
          send_data[23-:8]  <=  MAXOUT_4x[16+4*send_counter-(width >> 1)+2];
          send_data[31-:8]  <=  MAXOUT_4x[16+4*send_counter-(width >> 1)+3];           
        end
        // when sec = w/4 ~ w/4 + w/8 -1
        else if(send_counter < (width >> 2) + (width >> 3) ) begin // sc < 7 + 3
          send_data[7-:8]   <=  MAXOUT_4x[32+4*send_counter-(width)];
          send_data[15-:8]  <=  MAXOUT_4x[32+4*send_counter-(width)+1];
          send_data[23-:8]  <=  MAXOUT_4x[32+4*send_counter-(width)+2];
          send_data[31-:8]  <=  MAXOUT_4x[32+4*send_counter-(width)+3];          
        end
        // when sec = w/4 + w/8
        else if(send_counter == (width >> 2) + (width >> 3) ) begin  // sc == 7+3
          send_data[7-:8]   <=  MAXOUT_4x[32+4*send_counter-(width)];
          send_data[15-:8]  <=  MAXOUT_4x[32+4*send_counter-(width)+1];
          send_data[23-:8]  <=  MAXOUT_4x[48];
          send_data[31-:8]  <=  MAXOUT_4x[48+1];       
        end
        // when sec = w/4 + w/8 + 1 ~ w/2 -1
        else if(send_counter < (width >> 1) ) begin // sc < 14
          send_data[7-:8]   <=  MAXOUT_4x[48+4*send_counter-(width >> 1)-(width)];
          send_data[15-:8]  <=  MAXOUT_4x[48+4*send_counter-(width >> 1)-(width)+1];
          send_data[23-:8]  <=  MAXOUT_4x[48+4*send_counter-(width >> 1)-(width)+2];
          send_data[31-:8]  <=  MAXOUT_4x[48+4*send_counter-(width >> 1)-(width)+3];           
        end
      end
      else begin
        //when width == 14  , w/2 ===3 (mod4)
        if(send_counter < (width >> 3))begin // 0  sc < 1
          send_data[7-:8]   <=  MAXOUT_4x[4*send_counter];
          send_data[15-:8]  <=  MAXOUT_4x[4*send_counter+1];
          send_data[23-:8]  <=  MAXOUT_4x[4*send_counter+2];
          send_data[31-:8]  <=  MAXOUT_4x[4*send_counter+3];          
        end
        //when sec = width/8
        else if(send_counter == (width >> 3) ) begin // 1 sc == 1
          send_data[7-:8]   <=  MAXOUT_4x[4*send_counter];
          send_data[15-:8]  <=  MAXOUT_4x[4*send_counter+1];
          send_data[23-:8]  <=  MAXOUT_4x[4*send_counter+2];
          send_data[31-:8]  <=  MAXOUT_4x[16];            
        end
        // sec = width/8 + 1 ~ width / 4 - 1    
        else if(send_counter < (width >> 2) ) begin // 2 sc < 3
          send_data[7-:8]   <=  MAXOUT_4x[16+4*send_counter-(width >> 1)];
          send_data[15-:8]  <=  MAXOUT_4x[16+4*send_counter-(width >> 1)+1];
          send_data[23-:8]  <=  MAXOUT_4x[16+4*send_counter-(width >> 1)+2];
          send_data[31-:8]  <=  MAXOUT_4x[16+4*send_counter-(width >> 1)+3];           
        end
        //when sec == w/4
        else if(send_counter == (width >> 2)) begin // 3 sc == 3
          send_data[7-:8]   <=  MAXOUT_4x[16+4*send_counter-(width >> 1)];
          send_data[15-:8]  <=  MAXOUT_4x[16+4*send_counter-(width >> 1)+1];
          send_data[23-:8]  <=  MAXOUT_4x[32];
          send_data[31-:8]  <=  MAXOUT_4x[32+1];             
        end
        // when sec = w/4 + 1 ~ w/4 + w/8 -1
        else if(send_counter < (width >> 2) + (width >> 3) + 1 ) begin // 4 sc < 3 + 1 + 1
          send_data[7-:8]   <=  MAXOUT_4x[32+4*send_counter-(width)];
          send_data[15-:8]  <=  MAXOUT_4x[32+4*send_counter-(width)+1];
          send_data[23-:8]  <=  MAXOUT_4x[32+4*send_counter-(width)+2];
          send_data[31-:8]  <=  MAXOUT_4x[32+4*send_counter-(width)+3];          
        end
        // when sec = w/4 + w/8
        else if(send_counter == (width >> 2) + (width >> 3) + 1) begin // 5  sc == 3 + 1 + 1
          send_data[7-:8]   <=  MAXOUT_4x[32+4*send_counter-(width)];
          send_data[15-:8]  <=  MAXOUT_4x[48];
          send_data[23-:8]  <=  MAXOUT_4x[48+1];
          send_data[31-:8]  <=  MAXOUT_4x[48+2];       
        end
        // when sec = w/4 + w/8 + 1 ~ w/2 -1
        else if(send_counter < (width >> 1) ) begin // 6 sc < 7
          send_data[7-:8]   <=  MAXOUT_4x[48+4*send_counter-(width >> 1)-(width)];
          send_data[15-:8]  <=  MAXOUT_4x[48+4*send_counter-(width >> 1)-(width)+1];
          send_data[23-:8]  <=  MAXOUT_4x[48+4*send_counter-(width >> 1)-(width)+2];
          send_data[31-:8]  <=  MAXOUT_4x[48+4*send_counter-(width >> 1)-(width)+3];           
        end
      end
    end

    always @(posedge clk) begin
      if(reset) begin // reset when reset signal or not in progress
        m_axis_tdata  <=  0;
        m_axis_tlast  <=  0;
        m_axis_tvalid <=  0;
        send_counter  <=  0;
        send_counter2 <=  0;
        send_ready    <=  0;
        pool_done     <=  0;
      end
      else begin
        if(m_axis_tlast)begin
          pool_done <=  1;  
          m_axis_tdata  <=  0;
          m_axis_tlast  <=  0;
          m_axis_tvalid <=  0;
          send_counter  <=  0;
          send_counter2 <=  0;
          send_ready    <=  0;                  
        end      
        else if(MAXOUT_4x_full)  begin
          m_axis_tvalid <=  1;
          m_axis_tdata  <=  send_data;
          send_counter  <=  send_counter+1;  
        end         
        else if(send_counter ==  width/2)  begin  // when sending datas in MAXOUT_4x finished
          send_counter  <=  0;
          m_axis_tvalid <=  0;
          send_counter2 <=  send_counter2 +1;  
        end  
        else if(m_axis_tvalid)begin
          m_axis_tdata  <=  send_data;
          send_counter  <=  send_counter  + 1;    
          if(send_counter2  ==  (((length*height)>>3)-1) &&  send_counter  ==  (width>>1)-1)  //when we send all outputs
            m_axis_tlast  <=  1;          
        end
      end
    end
endmodule