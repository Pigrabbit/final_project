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
    output reg                                            fc_done
    
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

endmodule
