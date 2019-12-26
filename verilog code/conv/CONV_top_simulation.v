`timescale 1ns / 1ps

module top_simulation
(
    input clk,
    input resetn,
    input [31:0]    i_addr,
    input [31:0]    i_data,
    input init_txn,
    output txn_done,


    // ports for read result //
    input           init_read,
    input [31:0]    r_addr,
    output [31:0]   r_data,
    output          read_done,
    
    /////////////////////// ������ �κ� begin ////////////////////////////
  input   wire  conv_start,
  output  wire  conv_cone,

  output     feature_read_done,
  output     bias_read_done,
  output     weight_read_done,    
  output     conv_done,

  input wire [8:0] in_len_ex,
  input wire [8:0] out_len_ex,
  input wire [5:0] width_ex  
    /////////////////////// ������ �κ� end //////////////////////////////////////
);
    
    // Parameters
    parameter  SYS_CLK_PERIOD = 2.5;        // 400MHz
    parameter  HALF_SYS_CLK_PERIOD = SYS_CLK_PERIOD/2;
    
    
    // vdma_controller
    wire [31:0] controller_M_AXI_ARADDR;
    wire        controller_M_AXI_ARREADY;
    wire        controller_M_AXI_ARVALID;
    wire [31:0] controller_M_AXI_AWADDR;
    wire        controller_M_AXI_AWREADY;
    wire        controller_M_AXI_AWVALID;
    wire        controller_M_AXI_BREADY;
    wire [1:0]  controller_M_AXI_BRESP;
    wire        controller_M_AXI_BVALID;
    wire [31:0] controller_M_AXI_RDATA;
    wire        controller_M_AXI_RREADY;
    wire [1:0]  controller_M_AXI_RRESP;
    wire        controller_M_AXI_RVALID;
    wire [31:0] controller_M_AXI_WDATA;
    wire        controller_M_AXI_WREADY;
    wire        controller_M_AXI_WVALID;
    
    
    // vdma
    wire [31:0] M_AXI_MM2S_ARADDR;
    wire [1:0]  M_AXI_MM2S_ARBURST;
    wire [3:0]  M_AXI_MM2S_ARCACHE;
    wire [7:0]  M_AXI_MM2S_ARLEN;
    wire [2:0]  M_AXI_MM2S_ARPROT;
    wire        M_AXI_MM2S_ARREADY;
    wire [2:0]  M_AXI_MM2S_ARSIZE;
    wire        M_AXI_MM2S_ARVALID;
    wire [63:0] M_AXI_MM2S_RDATA;
    wire        M_AXI_MM2S_RLAST;
    wire        M_AXI_MM2S_RREADY;
    wire [1:0]  M_AXI_MM2S_RRESP;
    wire        M_AXI_MM2S_RVALID;
    wire [31:0] M_AXI_S2MM_AWADDR;
    wire [1:0]  M_AXI_S2MM_AWBURST;
    wire [3:0]  M_AXI_S2MM_AWCACHE;
    wire [7:0]  M_AXI_S2MM_AWLEN;
    wire [2:0]  M_AXI_S2MM_AWPROT;
    wire        M_AXI_S2MM_AWREADY;
    wire [2:0]  M_AXI_S2MM_AWSIZE;
    wire        M_AXI_S2MM_AWVALID;
    wire        M_AXI_S2MM_BREADY;
    wire [1:0]  M_AXI_S2MM_BRESP;
    wire        M_AXI_S2MM_BVALID;
    wire [63:0] M_AXI_S2MM_WDATA;
    wire        M_AXI_S2MM_WLAST;
    wire        M_AXI_S2MM_WREADY;
    wire [7:0]  M_AXI_S2MM_WSTRB;
    wire        M_AXI_S2MM_WVALID;
    
    
    // axi_m_interface
    //    wire [27:0] input_address;
    wire [31:0] write_data;
    //    wire [31:0] read_data;
    //    wire  INIT_AXI_READ;
    wire        INIT_AXI_WRITE;
    wire        WRITE_DONE;
    //    wire  READ_DONE;
    wire        M_AXI_ACLK;
    wire        M_AXI_ARESETN;
    wire [31:0] M_AXI_AWADDR;
    wire [2:0]  M_AXI_AWPROT;
    wire        M_AXI_AWVALID;
    wire        M_AXI_AWREADY;
    wire [31:0] M_AXI_WDATA;
    wire [3:0]  M_AXI_WSTRB;
    wire        M_AXI_WVALID;
    wire        M_AXI_WREADY;
    wire [1:0]  M_AXI_BRESP;
    wire        M_AXI_BVALID;
    wire        M_AXI_BREADY;
    wire [31:0] M_AXI_ARADDR;
    wire [2:0]  M_AXI_ARPROT;
    wire        M_AXI_ARVALID;
    wire        M_AXI_ARREADY;
    wire [31:0] M_AXI_RDATA;
    wire [1:0]  M_AXI_RRESP;
    wire        M_AXI_RVALID;
    wire        M_AXI_RREADY;
    wire        M_AXI_WLAST;
    wire        M_AXI_RLAST;
    
    
    // sram
    // write address channel
    wire [3:0]  s_axi_awid;
    wire [31:0] s_axi_awaddr;
    wire [7:0]  s_axi_awlen;
    wire [2:0]  s_axi_awsize;
    wire [1:0]  s_axi_awburst;
    wire [0:0]  s_axi_awlock;
    wire [3:0]  s_axi_awcache ;
    wire [2:0]  s_axi_awprot;
    wire [3:0]  s_axi_awqos;
    wire        s_axi_awvalid;
    wire        s_axi_awready;          
    // write data channel
    wire [31:0] s_axi_wdata;            
    wire [3:0]  s_axi_wstrb;            
    wire        s_axi_wlast;
    wire        s_axi_wvalid;
    wire        s_axi_wready;          
    // write response channel
    wire [3:0]  s_axi_bid;              
    wire [1:0]  s_axi_bresp;           
    wire        s_axi_bvalid;          
    wire        s_axi_bready;
    // read address channel
    wire [3:0]  s_axi_arid;
    wire [31:0] s_axi_araddr;
    wire [7:0]  s_axi_arlen;
    wire [2:0]  s_axi_arsize;
    wire [1:0]  s_axi_arburst;
    wire [0:0]  s_axi_arlock;
    wire [3:0]  s_axi_arcache;
    wire [2:0]  s_axi_arprot;
    wire [3:0]  s_axi_arqos;
    wire        s_axi_arvalid;
    wire        s_axi_arready;            
    // read data channel
    wire [3:0]  s_axi_rid;             
    wire [31:0] s_axi_rdata;           
    wire [1:0]  s_axi_rresp;            
    wire        s_axi_rlast;            
    wire        s_axi_rvalid;            
    wire        s_axi_rready;

    
    // module_example
    // ports of AXI-Stream Slave Interface
    wire        S_AXIS_TREADY;
    wire [31:0] S_AXIS_TDATA;
    wire [3:0]  S_AXIS_TKEEP;
    wire        S_AXIS_TUSER;
    wire        S_AXIS_TLAST;
    wire        S_AXIS_TVALID;
    // Ports of AXI-Stream Master Interface
    wire        M_AXIS_TREADY;
    wire        M_AXIS_TUSER;
    wire [31:0] M_AXIS_TDATA;
    wire [3:0]  M_AXIS_TKEEP;
    wire        M_AXIS_TLAST;
    wire        M_AXIS_TVALID;



   //-----------------------
   //**** Instantiation ****
   //-----------------------
    
    //** interconnect **//
    axi_interconnect_0 u_axi_interconnect_0
        (.INTERCONNECT_ACLK(clk),
        .INTERCONNECT_ARESETN(resetn),   
                
        // vdma 
        .S00_AXI_ARESET_OUT_N(),
        .S00_AXI_ACLK(clk),                 
        .S00_AXI_AWID(),
        .S00_AXI_AWADDR(M_AXI_S2MM_AWADDR),
        .S00_AXI_AWLEN(M_AXI_S2MM_AWLEN),
        .S00_AXI_AWSIZE(M_AXI_S2MM_AWSIZE),
        .S00_AXI_AWBURST(M_AXI_S2MM_AWBURST),
        .S00_AXI_AWLOCK(),
        .S00_AXI_AWCACHE(M_AXI_S2MM_AWCACHE),
        .S00_AXI_AWPROT(M_AXI_S2MM_AWPROT),
        .S00_AXI_AWQOS(),
        .S00_AXI_AWVALID(M_AXI_S2MM_AWVALID),
        .S00_AXI_AWREADY(M_AXI_S2MM_AWREADY),
        .S00_AXI_WDATA(M_AXI_S2MM_WDATA),
        .S00_AXI_WSTRB(M_AXI_S2MM_WSTRB),
        .S00_AXI_WLAST(M_AXI_S2MM_WLAST),
        .S00_AXI_WVALID(M_AXI_S2MM_WVALID),
        .S00_AXI_WREADY(M_AXI_S2MM_WREADY),
        .S00_AXI_BID(),
        .S00_AXI_BRESP(M_AXI_S2MM_BRESP),
        .S00_AXI_BVALID(M_AXI_S2MM_BVALID),
        .S00_AXI_BREADY(M_AXI_S2MM_BREADY),
        .S00_AXI_ARID(),
        .S00_AXI_ARADDR(M_AXI_MM2S_ARADDR),
        .S00_AXI_ARLEN(M_AXI_MM2S_ARLEN),
        .S00_AXI_ARSIZE(M_AXI_MM2S_ARSIZE),
        .S00_AXI_ARBURST(M_AXI_MM2S_ARBURST),
        .S00_AXI_ARLOCK(),
        .S00_AXI_ARCACHE(M_AXI_MM2S_ARCACHE),
        .S00_AXI_ARPROT(M_AXI_MM2S_ARPROT),
        .S00_AXI_ARQOS(),
        .S00_AXI_ARVALID(M_AXI_MM2S_ARVALID),
        .S00_AXI_ARREADY(M_AXI_MM2S_ARREADY),
        .S00_AXI_RID(),
        .S00_AXI_RDATA(M_AXI_MM2S_RDATA),
        .S00_AXI_RRESP(M_AXI_MM2S_RRESP),
        .S00_AXI_RLAST(M_AXI_MM2S_RLAST),
        .S00_AXI_RVALID(M_AXI_MM2S_RVALID),
        .S00_AXI_RREADY(M_AXI_MM2S_RREADY),
    
        // axi_m_interface 
        .S01_AXI_ARESET_OUT_N(),
        .S01_AXI_ACLK(clk),                 
        .S01_AXI_AWID(),
        .S01_AXI_AWADDR(M_AXI_AWADDR),
        .S01_AXI_AWLEN(8'b0000_0000),
        .S01_AXI_AWSIZE(3'b010),
        .S01_AXI_AWBURST(2'b01), 
        .S01_AXI_AWLOCK(1'b0),
        .S01_AXI_AWCACHE(4'b0000),
        .S01_AXI_AWPROT(M_AXI_AWPROT),
        .S01_AXI_AWQOS(),
        .S01_AXI_AWVALID(M_AXI_AWVALID),
        .S01_AXI_AWREADY(M_AXI_AWREADY),
        .S01_AXI_WDATA(M_AXI_WDATA),
        .S01_AXI_WSTRB(M_AXI_WSTRB),
        .S01_AXI_WLAST(M_AXI_WLAST),
        .S01_AXI_WVALID(M_AXI_WVALID),
        .S01_AXI_WREADY(M_AXI_WREADY),
        .S01_AXI_BID(),
        .S01_AXI_BRESP(M_AXI_BRESP),
        .S01_AXI_BVALID(M_AXI_BVALID),
        .S01_AXI_BREADY(M_AXI_BREADY),
        .S01_AXI_ARID(),
        .S01_AXI_ARADDR(M_AXI_ARADDR),
        .S01_AXI_ARLEN(8'b0000_0000),
        .S01_AXI_ARSIZE(3'b010),
        .S01_AXI_ARBURST(2'b01),
        .S01_AXI_ARLOCK(1'b0),
        .S01_AXI_ARCACHE(4'b0000),
        .S01_AXI_ARPROT(M_AXI_ARPROT),
        .S01_AXI_ARQOS(4'b0000),
        .S01_AXI_ARVALID(M_AXI_ARVALID),
        .S01_AXI_ARREADY(M_AXI_ARREADY),
        .S01_AXI_RID(),
        .S01_AXI_RDATA(M_AXI_RDATA),
        .S01_AXI_RRESP(M_AXI_RRESP),
        .S01_AXI_RLAST(M_AXI_RLAST),
        .S01_AXI_RVALID(M_AXI_RVALID),
        .S01_AXI_RREADY(M_AXI_RREADY),
        
        // sram    
        .M00_AXI_ARESET_OUT_N(),
        .M00_AXI_ACLK(clk),          
        .M00_AXI_AWID(s_axi_awid),
        .M00_AXI_AWADDR(s_axi_awaddr),
        .M00_AXI_AWLEN(s_axi_awlen),
        .M00_AXI_AWSIZE(s_axi_awsize),
        .M00_AXI_AWBURST(s_axi_awburst),
        .M00_AXI_AWLOCK(s_axi_awlock),
        .M00_AXI_AWCACHE(s_axi_awcache),
        .M00_AXI_AWPROT(s_axi_awprot),
        .M00_AXI_AWQOS(s_axi_awqos),
        .M00_AXI_AWVALID(s_axi_awvalid),
        .M00_AXI_AWREADY(s_axi_awready),
        .M00_AXI_WDATA(s_axi_wdata),
        .M00_AXI_WSTRB(s_axi_wstrb),
        .M00_AXI_WLAST(s_axi_wlast),
        .M00_AXI_WVALID(s_axi_wvalid),
        .M00_AXI_WREADY(s_axi_wready),
        .M00_AXI_BID(s_axi_bid),
        .M00_AXI_BRESP(s_axi_bresp),
        .M00_AXI_BVALID(s_axi_bvalid),
        .M00_AXI_BREADY(s_axi_bready),
        .M00_AXI_ARID(s_axi_arid),
        .M00_AXI_ARADDR(s_axi_araddr),
        .M00_AXI_ARLEN(s_axi_arlen),
        .M00_AXI_ARSIZE(s_axi_arsize),
        .M00_AXI_ARBURST(s_axi_arburst),
        .M00_AXI_ARLOCK(s_axi_arlock),
        .M00_AXI_ARCACHE(s_axi_arcache),
        .M00_AXI_ARPROT(s_axi_arprot),
        .M00_AXI_ARQOS(s_axi_arqos),
        .M00_AXI_ARVALID(s_axi_arvalid),
        .M00_AXI_ARREADY(s_axi_arready),
        .M00_AXI_RID(s_axi_rid),
        .M00_AXI_RDATA(s_axi_rdata),
        .M00_AXI_RRESP(s_axi_rresp),
        .M00_AXI_RLAST(s_axi_rlast),
        .M00_AXI_RVALID(s_axi_rvalid),
        .M00_AXI_RREADY(s_axi_rready));    

    
    //** sram **//
    sram_32x131072 u_sram_32x131072
        (.s_aclk(clk),
        .s_aresetn(resetn),
        
        // AXI4-Full Slave Interface 
        .s_axi_awid(s_axi_awid),            // 4-bit 
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awlen(s_axi_awlen),          // 8-bit
        .s_axi_awsize(s_axi_awsize),        // 3-bit
        .s_axi_awburst(s_axi_awburst),      // 2-bit
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wlast(s_axi_wlast),          // 1-bit
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bid(s_axi_bid),              // 4-bit
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_arid(s_axi_arid),            // 4-bit
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arlen(s_axi_arlen),          // 8-bit
        .s_axi_arsize(s_axi_arsize),        // 3-bit
        .s_axi_arburst(s_axi_arburst),      // 2-bit
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rid(s_axi_rid),              // 4-bit
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rlast(s_axi_rlast),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready));      
        

    //** vdma controller **//
    vdma_controller u_vdma_controller
        (.M_AXI_ACLK(clk),
        .M_AXI_ARESETN(resetn),
        
        // AXI-Lite Master Interface
        .M_AXI_ARADDR(controller_M_AXI_ARADDR),
        .M_AXI_ARREADY(controller_M_AXI_ARREADY),
        .M_AXI_ARVALID(controller_M_AXI_ARVALID),
        .M_AXI_AWADDR(controller_M_AXI_AWADDR),
        .M_AXI_AWREADY(controller_M_AXI_AWREADY),
        .M_AXI_AWVALID(controller_M_AXI_AWVALID),
        .M_AXI_BREADY(controller_M_AXI_BREADY),
        .M_AXI_BRESP(controller_M_AXI_BRESP),
        .M_AXI_BVALID(controller_M_AXI_BVALID),
        .M_AXI_RDATA(controller_M_AXI_RDATA),
        .M_AXI_RREADY(controller_M_AXI_RREADY),
        .M_AXI_RRESP(controller_M_AXI_RRESP),
        .M_AXI_RVALID(controller_M_AXI_RVALID),
        .M_AXI_WDATA(controller_M_AXI_WDATA),
        .M_AXI_WREADY(controller_M_AXI_WREADY),
        .M_AXI_WVALID(controller_M_AXI_WVALID),                     
        .INIT_AXI_TXN(init_txn),        
        .TXN_DONE(txn_done),
        
        // addr & data
        .i_addr(i_addr),
        .i_data(i_data));
        
        
    //** vdma **//
    axi_vdma_0 u_axi_vdma_0
        (.axi_resetn(resetn),                            
        .m_axi_mm2s_aclk(clk),  
        
        // AXI-Lite Slave Interface
        .s_axi_lite_aclk(clk),                          
        .s_axi_lite_araddr(controller_M_AXI_ARADDR[8:0]),
        .s_axi_lite_arready(controller_M_AXI_ARREADY),
        .s_axi_lite_arvalid(controller_M_AXI_ARVALID),
        .s_axi_lite_awaddr(controller_M_AXI_AWADDR[8:0]),
        .s_axi_lite_awready(controller_M_AXI_AWREADY),
        .s_axi_lite_awvalid(controller_M_AXI_AWVALID),
        .s_axi_lite_bready(controller_M_AXI_BREADY),
        .s_axi_lite_bresp(controller_M_AXI_BRESP),
        .s_axi_lite_bvalid(controller_M_AXI_BVALID),
        .s_axi_lite_rdata(controller_M_AXI_RDATA),
        .s_axi_lite_rready(controller_M_AXI_RREADY),
        .s_axi_lite_rresp(controller_M_AXI_RRESP),
        .s_axi_lite_rvalid(controller_M_AXI_RVALID),
        .s_axi_lite_wdata(controller_M_AXI_WDATA),
        .s_axi_lite_wready(controller_M_AXI_WREADY),
        .s_axi_lite_wvalid(controller_M_AXI_WVALID),
        
        // AXI4-Full Master Interface (MM2S)              
        .m_axi_mm2s_araddr(M_AXI_MM2S_ARADDR),
        .m_axi_mm2s_arburst(M_AXI_MM2S_ARBURST),
        .m_axi_mm2s_arcache(M_AXI_MM2S_ARCACHE),
        .m_axi_mm2s_arlen(M_AXI_MM2S_ARLEN),
        .m_axi_mm2s_arprot(M_AXI_MM2S_ARPROT),
        .m_axi_mm2s_arready(M_AXI_MM2S_ARREADY),
        .m_axi_mm2s_arsize(M_AXI_MM2S_ARSIZE),
        .m_axi_mm2s_arvalid(M_AXI_MM2S_ARVALID),
        .m_axi_mm2s_rdata(M_AXI_MM2S_RDATA),
        .m_axi_mm2s_rlast(M_AXI_MM2S_RLAST),
        .m_axi_mm2s_rready(M_AXI_MM2S_RREADY),
        .m_axi_mm2s_rresp(M_AXI_MM2S_RRESP),
        .m_axi_mm2s_rvalid(M_AXI_MM2S_RVALID),
        
        // AXI4-Full Master Interface (S2MM)      
        .m_axi_s2mm_aclk(clk),                            
        .m_axi_s2mm_awaddr(M_AXI_S2MM_AWADDR),
        .m_axi_s2mm_awburst(M_AXI_S2MM_AWBURST),
        .m_axi_s2mm_awcache(M_AXI_S2MM_AWCACHE),
        .m_axi_s2mm_awlen(M_AXI_S2MM_AWLEN),
        .m_axi_s2mm_awprot(M_AXI_S2MM_AWPROT),
        .m_axi_s2mm_awready(M_AXI_S2MM_AWREADY),
        .m_axi_s2mm_awsize(M_AXI_S2MM_AWSIZE),
        .m_axi_s2mm_awvalid(M_AXI_S2MM_AWVALID),
        .m_axi_s2mm_bready(M_AXI_S2MM_BREADY),
        .m_axi_s2mm_bresp(M_AXI_S2MM_BRESP),
        .m_axi_s2mm_bvalid(M_AXI_S2MM_BVALID),
        .m_axi_s2mm_wdata(M_AXI_S2MM_WDATA),
        .m_axi_s2mm_wlast(M_AXI_S2MM_WLAST),
        .m_axi_s2mm_wready(M_AXI_S2MM_WREADY),
        .m_axi_s2mm_wstrb(M_AXI_S2MM_WSTRB),
        .m_axi_s2mm_wvalid(M_AXI_S2MM_WVALID),
        
        // AXI-Stream Master Interface
        .m_axis_mm2s_aclk(clk),                           
        .m_axis_mm2s_tdata(S_AXIS_TDATA),
        .m_axis_mm2s_tlast(S_AXIS_TLAST),
        .m_axis_mm2s_tready(S_AXIS_TREADY),
        .m_axis_mm2s_tvalid(S_AXIS_TVALID),
        
        // AXI-Stream Slave Interface
        .s_axis_s2mm_aclk(clk),                         
        .s_axis_s2mm_tdata(M_AXIS_TDATA),
        .s_axis_s2mm_tkeep(M_AXIS_TKEEP),
        .s_axis_s2mm_tlast(M_AXIS_TLAST),
        .s_axis_s2mm_tready(M_AXIS_TREADY),
        .s_axis_s2mm_tuser(M_AXIS_TUSER),
        .s_axis_s2mm_tvalid(M_AXIS_TVALID));        


   axi_m_interface u_axi_m_interface
        (.WRITE_DONE(WRITE_DONE),
        .READ_DONE(read_done),
        .input_address(r_addr),
        .write_data(write_data),
        .read_data(r_data),
        .INIT_AXI_READ(init_read),
        .INIT_AXI_WRITE(INIT_AXI_WRITE),
        .M_AXI_ACLK(clk),
        .M_AXI_ARESETN(resetn),
        .M_AXI_AWADDR(M_AXI_AWADDR),
        .M_AXI_AWVALID(M_AXI_AWVALID),
        .M_AXI_AWREADY(M_AXI_AWREADY),
        .M_AXI_WDATA(M_AXI_WDATA),
        .M_AXI_WSTRB(M_AXI_WSTRB),
        .M_AXI_WVALID(M_AXI_WVALID),
        .M_AXI_WREADY(M_AXI_WREADY),
        .M_AXI_BRESP(M_AXI_BRESP),
        .M_AXI_BVALID(M_AXI_BVALID),
        .M_AXI_BREADY(M_AXI_BREADY),
        .M_AXI_ARADDR(M_AXI_ARADDR),
        .M_AXI_ARVALID(M_AXI_ARVALID),
        .M_AXI_ARREADY(M_AXI_ARREADY),
        .M_AXI_RDATA(M_AXI_RDATA),
        .M_AXI_RRESP(M_AXI_RRESP),
        .M_AXI_RVALID(M_AXI_RVALID),
        .M_AXI_RREADY(M_AXI_RREADY));        
        
        
    // Ȥ�� ������ �ٲ�ٸ�?? ������ �ٲ��ּ���.        
    conv conv_layer
        (.clk(clk),
        .rstn(resetn),
        
        // Axi-Stream Slave Interface
        .S_AXIS_TREADY(S_AXIS_TREADY),
        .S_AXIS_TDATA(S_AXIS_TDATA),
        .S_AXIS_TKEEP(S_AXIS_TKEEP),
        .S_AXIS_TUSER(S_AXIS_TUSER),
        .S_AXIS_TLAST(S_AXIS_TLAST),
        .S_AXIS_TVALID(S_AXIS_TVALID),
        
        // Axi-Stream Master Interface
        .M_AXIS_TREADY(M_AXIS_TREADY),
        .M_AXIS_TUSER(M_AXIS_TUSER),
        .M_AXIS_TDATA(M_AXIS_TDATA),
        .M_AXIS_TKEEP(M_AXIS_TKEEP),
        .M_AXIS_TLAST(M_AXIS_TLAST),
        .M_AXIS_TVALID(M_AXIS_TVALID),
        
        
        /////////////////////// ������ �κ� begin ////////////////////////////
        .conv_start(conv_start),
        .conv_done(conv_done),
        .feature_read_done(feature_read_done),
        .bias_read_done(bias_read_done),
        .weight_read_done(weight_read_done),    
        .in_len_ex(in_len_ex),
        .out_len_ex(out_len_ex),
        .width_ex(width_ex)  
        /////////////////////// ������ �κ� end //////////////////////////////////////
        );
        
endmodule