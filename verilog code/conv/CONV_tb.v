`timescale 1ns / 1ps


module tb;
     
    // system parameters
    parameter   CLK_PERIOD          = 2.5;              // 400MHz
    parameter   HALF_CLK_PERIODD    = CLK_PERIOD / 2;
    
    // addresses for vdma registers 
    parameter   S2MM_VDMACR_REG_ADDR        = 32'h00000030;
    parameter   S2MM_START_ADDRESS_REG_ADDR = 32'h000000AC;
    parameter   S2MM_FRMDLY_STRIDE_REG_ADDR = 32'h000000A8;
    parameter   S2MM_HSIZE_REG_ADDR         = 32'h000000A4;
    parameter   S2MM_VSIZE_REG_ADDR         = 32'h000000A0;
    
    parameter   MM2S_VDMACR_REG_ADDR        = 32'h00000000;
    parameter   MM2S_START_ADDRESS_REG_ADDR = 32'h0000005C;
    parameter   MM2S_FRMDLY_STRIDE_REG_ADDR = 32'h00000058;
    parameter   MM2S_HSIZE_REG_ADDR         = 32'h00000054;
    parameter   MM2S_VSIZE_REG_ADDR         = 32'h00000050;
    
    /////////////////////// DATASET ////////////////////////////
    parameter IN_LEN=32;
    parameter OUT_LEN=64;
    parameter WID=16;
    
    
    
    parameter   INPUT_SIZE = IN_LEN*WID*WID;
    parameter   OUTPUT_SIZE = WID*WID*OUT_LEN;
    
    // HSIZE*VSIZE ?? ?? ???????? ?? ( 8-bit?? ?? = byte ??) ????. ????????? VSIZE?? 1 ????? HSZIE ?????? ?????? ??? HSIZE?? ? ???? ???????ª? ????.
    // STRIDE SIZE ?? HSIZE?? ????????.
    parameter   FEATURE_BASE_ADDR   = 32'h0000_1000;    // 00000_0000 ?? ????? ? ??¡Æ ??????? ?? ???????. Feature Size, Weight Size, Bias SIze, Output Size?? ??????? ????? ??? ???? ?????????.
    parameter   FEATURE_STRIDE_SIZE = INPUT_SIZE;
    parameter   FEATURE_HSIZE       = INPUT_SIZE;    // 65536 (2?? 16??) ???? ??? ?????. ??? VSIZE?? ?¡???? HSIZE*VSIZE?? INPUT SIZE?? ????? ??????? ????.
    parameter   FEATURE_VSIZE       = 32'd1;
    parameter   WEIGHT_BASE_ADDR    = 32'h0000_2000;    // 00000_0000 ?? ????? ? ??¡Æ ??????? ?? ???????. Feature Size, Weight Size, Bias SIze, Output Size?? ??????? ????? ??? ???? ?????????.
    parameter   WEIGHT_STRIDE_SIZE  = 9*IN_LEN*OUT_LEN/4;
    parameter   WEIGHT_HSIZE        = 9*IN_LEN*OUT_LEN/4;    // 65536 (2?? 16??) ???? ??? ?????. ??? VSIZE?? ?¡???? HSIZE*VSIZE?? INPUT SIZE?? ????? ??????? ????.
    parameter   WEIGHT_VSIZE        = 32'd4;
    parameter   BIAS_BASE_ADDR      = 32'h0001_0000;    // 00000_0000 ?? ????? ? ??¡Æ ??????? ?? ???????. Feature Size, Weight Size, Bias SIze, Output Size?? ??????? ????? ??? ???? ?????????.
    parameter   BIAS_STRIDE_SIZE    = OUT_LEN;   
    parameter   BIAS_HSIZE          = OUT_LEN;
    parameter   BIAS_VSIZE          = 32'd1;    
    parameter   RESULT_BASE_ADDR    = 32'h0001_2000;    // Feature Size, Weight Size, Bias SIze, Output Size?? ??????? ????? ??? ???? ?????????.
    parameter   RESULT_STRIDE_SIZE  = OUTPUT_SIZE;    
    parameter   RESULT_HSIZE        = OUTPUT_SIZE;    // 65536 (2?? 16??) ???? ??? ?????. ??? VSIZE?? ?¡???? HSIZE*VSIZE?? INPUT SIZE?? ????? ??????? ????.   
    parameter   RESULT_VSIZE        = 32'd1; 
    /////////////////////// ?????? ???? end //////////////////////////////////////
    
    
    localparam integer  OP_SIZE         = 4;
    localparam integer  ADDR_SIZE       = 28;
    localparam integer  DATA_SIZE       = 32;
    
    /////////////////////// ?????? ???? begin ////////////////////////////
    localparam integer  FEATURE_SIZE    = FEATURE_HSIZE*FEATURE_VSIZE/4;                 // txt ??????? ?? line?? 32 bit?? ?? line ?? ????. ?????? ???? HSZIE*VSIZE ?? 1/4 ?? ???????.
    localparam integer  WEIGHT_SIZE     = WEIGHT_HSIZE*WEIGHT_VSIZE/4;                
    localparam integer  BIAS_SIZE       = BIAS_HSIZE*BIAS_VSIZE/4;                   
    localparam integer  RESULT_SIZE     = RESULT_HSIZE*RESULT_VSIZE/4;                   
    /////////////////////// ?????? ???? end //////////////////////////////////////
    
    // FC, CONV?? ????? a,b,c ?? ?? ????? ????????? POOL?? weight?? bias?? ??????? b,c?? ??? ???????.
    // bram write 
    reg [31:0]          data_a_32bit [0:FEATURE_SIZE-1];        // data_a
    reg [31:0]          data_b_32bit [0:WEIGHT_SIZE-1];         // data_b
    reg [31:0]          data_c_32bit [0:BIAS_SIZE-1];           // data_c  
    
    
    /////////////////////// ?????? ???? begin //////////////////////////// 
    // module_example
    reg [2:0]     COMMAND;
    reg [8:0]     input_len;
    reg [8:0]     output_len;
    reg [8:0]     width;
    wire           F_writedone;
    wire           B_writedone;
    wire           W_writedone;
    wire           conv_done;
    /////////////////////// ?????? ???? end //////////////////////////////////////
    
    // system
    reg         clk;
    reg         resetn;
    
    // vdma_control
    reg         init_txn;
    reg [31:0]  addr;
    reg [31:0]  data;
    wire        txn_done;
    
    // axi_m_interface (for read)
    reg         init_read;
    reg [31:0]  r_addr;
    wire [31:0] r_data;
    wire        read_done;  
    
    // For result check
    integer     file;
    reg [31:0]  result_32bit;                           // output result
    reg [31:0]  result_expected_32bit[0:RESULT_SIZE-1]; // expected result
    reg [27:0]  addr_test;
    
    integer    i;
    reg [128 * 8:0] input_file_name;
    
    reg         compare_flag;


    //----------------------
    // ******* Clock *******
    //----------------------
    
    initial clk = 1'b1;
    always #HALF_CLK_PERIODD clk = ~clk;
    
    
    
    //-----------------------
    //****** Main test ******
    //-----------------------
    
    initial begin
        resetn = 1'b0;
        init_txn = 1'b0;
        init_read = 1'b0;
        result_32bit = 0;
        compare_flag = 1'b1;
        
        /////////////////////// ?????? ???? begin ////////////////////////////
        // ??????? port???? ????
        COMMAND = 3'b000;
        /////////////////////// ?????? ???? end //////////////////////////////////////
        
        repeat (100)
          @(posedge clk);      
          
        resetn = 1'b1;   
        
        
        //** writing data to BRAM **//     
        repeat (500)
          @(posedge clk);
        $display("- Force write starts -");
        
        
        ////////////////////////////////////////////////////////////   INPUT FILES   ///////////////////////////////////////////////////////////
        /////////////////////// ?????? ???? begin ////////////////////////////
        //////////////////////DATASET///////////////////////////////////////
        // input data file
        input_file_name = "input_32bits_2s.txt";
        check_file(input_file_name);
        $readmemb(input_file_name, data_a_32bit);
        // weight file
        input_file_name = "conv1_weight_32bits_2s.txt";
        check_file(input_file_name);
        $readmemb(input_file_name, data_b_32bit);
        // bias file
        input_file_name = "conv1_bias_32bits_2s.txt";
        check_file(input_file_name);
        $readmemb(input_file_name, data_c_32bit);
        /////////////////////// ?????? ???? end //////////////////////////////////////
                 
        // writing fc_relu_input.txt
        for (i = 0; i < FEATURE_SIZE; i = i + 1) begin
            force tb.u_top_simulation.u_sram_32x131072.inst.axi_mem_module.blk_mem_gen_v8_4_1_inst.ADDRA = (FEATURE_BASE_ADDR + i*4)/4; 
            force tb.u_top_simulation.u_sram_32x131072.inst.axi_mem_module.blk_mem_gen_v8_4_1_inst.ENA = 1'b1;
            force tb.u_top_simulation.u_sram_32x131072.inst.axi_mem_module.blk_mem_gen_v8_4_1_inst.WEA = 4'b1111;
            @(posedge tb.u_top_simulation.u_sram_32x131072.inst.axi_mem_module.blk_mem_gen_v8_4_1_inst.CLKA);
            force tb.u_top_simulation.u_sram_32x131072.inst.axi_mem_module.blk_mem_gen_v8_4_1_inst.DINA = {data_a_32bit[i][7:0],data_a_32bit[i][15:8],data_a_32bit[i][23:16],data_a_32bit[i][31:24]};   // UART version - big to little
                                                             
            @(posedge tb.u_top_simulation.u_sram_32x131072.inst.axi_mem_module.blk_mem_gen_v8_4_1_inst.CLKA);
        end 
          $display("feature done");
        // writing fc_relu_weight.txt  
        for (i = 0; i < WEIGHT_SIZE; i = i + 1) begin            
            force tb.u_top_simulation.u_sram_32x131072.inst.axi_mem_module.blk_mem_gen_v8_4_1_inst.ADDRA = (WEIGHT_BASE_ADDR + i*4)/4; 
            force tb.u_top_simulation.u_sram_32x131072.inst.axi_mem_module.blk_mem_gen_v8_4_1_inst.ENA = 1'b1;
            force tb.u_top_simulation.u_sram_32x131072.inst.axi_mem_module.blk_mem_gen_v8_4_1_inst.WEA = 4'b1111;
            @(posedge tb.u_top_simulation.u_sram_32x131072.inst.axi_mem_module.blk_mem_gen_v8_4_1_inst.CLKA); 
            force tb.u_top_simulation.u_sram_32x131072.inst.axi_mem_module.blk_mem_gen_v8_4_1_inst.DINA = {data_b_32bit[i][7:0],data_b_32bit[i][15:8],data_b_32bit[i][23:16],data_b_32bit[i][31:24]};   // UART version - big to little                                                  
    
            @(posedge tb.u_top_simulation.u_sram_32x131072.inst.axi_mem_module.blk_mem_gen_v8_4_1_inst.CLKA);
        end                     
         $display("weight done");

        // writing fc_relu_bias.txt  
        for (i = 0; i < BIAS_SIZE; i = i + 1) begin
             force tb.u_top_simulation.u_sram_32x131072.inst.axi_mem_module.blk_mem_gen_v8_4_1_inst.ADDRA = (BIAS_BASE_ADDR + i*4)/4;
             force tb.u_top_simulation.u_sram_32x131072.inst.axi_mem_module.blk_mem_gen_v8_4_1_inst.ENA = 1'b1;
             force tb.u_top_simulation.u_sram_32x131072.inst.axi_mem_module.blk_mem_gen_v8_4_1_inst.WEA = 4'b1111;
             @(posedge tb.u_top_simulation.u_sram_32x131072.inst.axi_mem_module.blk_mem_gen_v8_4_1_inst.CLKA);
             force tb.u_top_simulation.u_sram_32x131072.inst.axi_mem_module.blk_mem_gen_v8_4_1_inst.DINA = {data_c_32bit[i][7:0],data_c_32bit[i][15:8],data_c_32bit[i][23:16],data_c_32bit[i][31:24]};  // UART version - big to little
                                                                 
             @(posedge tb.u_top_simulation.u_sram_32x131072.inst.axi_mem_module.blk_mem_gen_v8_4_1_inst.CLKA);
        end
          $display("bias done");

        release tb.u_top_simulation.u_sram_32x131072.inst.axi_mem_module.blk_mem_gen_v8_4_1_inst.ADDRA;
        release tb.u_top_simulation.u_sram_32x131072.inst.axi_mem_module.blk_mem_gen_v8_4_1_inst.ENA;
        release tb.u_top_simulation.u_sram_32x131072.inst.axi_mem_module.blk_mem_gen_v8_4_1_inst.WEA;
        release tb.u_top_simulation.u_sram_32x131072.inst.axi_mem_module.blk_mem_gen_v8_4_1_inst.DINA;
        @(posedge tb.u_top_simulation.u_sram_32x131072.inst.axi_mem_module.blk_mem_gen_v8_4_1_inst.CLKA);
        
        $display("- Force write is done -\n\n");
        
        

        ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////  
        ////////////////////////////////////////////////////////   VDMA control starts   ///////////////////////////////////////////////////////  

  
        /////////////////////// ?????? ???? begin ////////////////////////////
        // ?? ?????? ??????? ????? ?????? VDMA?? ??? signal???? ??? ?????? ????.
        
        $display("- VDMA control starts -\n");
        # CLK_PERIOD;
        
        // VDMA?? ??????? ????? ??? ????? ??????. VDMA?? input data?? ??????? ????? ???????? ??? ???? ????????. ?? ?? ?????? ?????? ??? ???????.
        // S2MM //
        // write result (from FC to memory)
        write_data(S2MM_VDMACR_REG_ADDR, 32'h00010091);                 // control
        write_data(S2MM_START_ADDRESS_REG_ADDR, RESULT_BASE_ADDR);      // start address
        write_data(S2MM_FRMDLY_STRIDE_REG_ADDR, RESULT_STRIDE_SIZE);    // stride
        write_data(S2MM_HSIZE_REG_ADDR, RESULT_HSIZE);                  // hsize (= line size) (Bytes)
        write_data(S2MM_VSIZE_REG_ADDR, RESULT_VSIZE);                  // the number of lines
        $display("VDMA is ready to receive result from CONV\n");
    
    
    
    
        // MM2S //
        // feature read (from memory to FC) 
        $display("VDMA transmits feature to CONV");
        write_data(MM2S_VDMACR_REG_ADDR, 32'h00010091);                 // control
        write_data(MM2S_START_ADDRESS_REG_ADDR, FEATURE_BASE_ADDR);     // start address
        write_data(MM2S_FRMDLY_STRIDE_REG_ADDR, FEATURE_STRIDE_SIZE);   // stride
        write_data(MM2S_HSIZE_REG_ADDR, FEATURE_HSIZE);                 // hsize (= line size) (Bytes)
        write_data(MM2S_VSIZE_REG_ADDR, FEATURE_VSIZE);                 // the number of lines 


        repeat(100)
            @(posedge clk);

            
        // sending control signals to FC
        COMMAND = 3'b001;				
				input_len		= IN_LEN;
				output_len	     = OUT_LEN;
				width  			= WID;


        repeat(2)
            @(posedge clk);
            
        $display("CONV starts to read feature");
        wait(F_writedone);
        $display("CONV finishes to read feature\n");
        
        
        repeat(100)                                                     //** Please do not remove this. **//
            @(posedge clk);                                             //** VDMA needs enough time interval between transmissions of the same direction. (this case: MM2S & MM2S) **//

        
        // MM2S //
        // bias read (from memory to FC) 
        $display("VDMA transmits bias to CONV");
        write_data(MM2S_VDMACR_REG_ADDR, 32'h00010091);                 // control     
        write_data(MM2S_START_ADDRESS_REG_ADDR, BIAS_BASE_ADDR);        // start address 
        write_data(MM2S_FRMDLY_STRIDE_REG_ADDR, BIAS_STRIDE_SIZE);      // stride 
        write_data(MM2S_HSIZE_REG_ADDR, BIAS_HSIZE);                    // hsize (= line size) (Bytes) 
        write_data(MM2S_VSIZE_REG_ADDR, BIAS_VSIZE);                    // the number of lines 
        
        
        repeat(100)
            @(posedge clk);
            
        
        // sending control signals to FC
        COMMAND = 3'b010;
        
        $display("CONV starts to read bias");     
        wait(B_writedone);
        $display("CONV finishes to read bias\n");
        
        
        repeat(100)                                                     //** Please do not remove this. **//
            @(posedge clk);                                             //** VDMA needs enough time interval between transmissions of the same direction. (this case: MM2S & MM2S) **//
        
        
        // MM2S //
        // weight read (from memory to FC) 
        $display("VDMA transmits weight to CONV");
        write_data(MM2S_VDMACR_REG_ADDR, 32'h00010091);                 // control     
        write_data(MM2S_START_ADDRESS_REG_ADDR, WEIGHT_BASE_ADDR);      // start address
        write_data(MM2S_FRMDLY_STRIDE_REG_ADDR, WEIGHT_STRIDE_SIZE);    // stride
        write_data(MM2S_HSIZE_REG_ADDR, WEIGHT_HSIZE);                  // hsize (= line size) (Bytes)
        write_data(MM2S_VSIZE_REG_ADDR, WEIGHT_VSIZE);                  // the number of lines


        repeat(100)
            @(posedge clk);   
            
            
        // sending control signals to FC
        COMMAND = 3'b011;

        $display("CONV starts to read weight");      
        $display("CONV finishes to read weight\n");
        
                
        repeat(100)
            @(posedge clk);                 
    
    
        // sending control signals to FC
        //COMMAND = 3'b100;     
           
        $display("CONV starts to write result");            
        wait(conv_done);
        $display("CONV finishes to write result\n\n");        
        
        
        repeat(100)
            @(posedge clk);  
        // sending control signals to FC              
        COMMAND = 3'b000;  
             
        write_data(MM2S_VDMACR_REG_ADDR, 32'h00010094);             // vdma reset to flush vdma


        repeat(100)
            @(posedge clk);   
  
        /////////////////////// ?????? ???? end //////////////////////////////////////
        
        ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////  
        //////////////////////////////////////////////////////  VDMA control is finished  //////////////////////////////////////////////////////
        ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////  
    
    
    
        // comparing results
        $display("- Comparing result starts -\n");
        
        
        ////////////////////////////////////////////////////////////   RESULT FILE   ///////////////////////////////////////////////////////////
        /////////////////////// ?????? ???? begin ////////////////////////////
        ////////////////////////////DATASET///////////////////////////////////
        import_result_nowrite("conv1_relu_out_32bits_2s.txt");     
        ////////////////////// ?????? ???? end //////////////////////////////////////
        
        addr_test = RESULT_BASE_ADDR;
        
        for (i = 0; i < RESULT_SIZE; i = i + 1) begin
            read_data (addr_test+i*4, result_32bit);
            
            $display("Index: %d", i);
            
            if (result_32bit != {result_expected_32bit[i][7:0], result_expected_32bit[i][15:8], result_expected_32bit[i][23:16],result_expected_32bit[i][31:24]}) begin
                $display("\nResult is different!");
                $display("Expected value: %h", {result_expected_32bit[i][7:0], result_expected_32bit[i][15:8], result_expected_32bit[i][23:16],result_expected_32bit[i][31:24]});
                $display("Output value: %h\n", result_32bit);
                
                compare_flag = 1'b0;
            end
        end
        
        if (compare_flag) begin
            $display("\nResult is correct!\n");
        end
        
        $display("- Comparing result is done!! -\n");
        $finish;
    end
    
    
    
    //-----------------------
    //******** Task ********
    //-----------------------
    
    task write_data (input [31:0] i_addr, input [31:0] i_data);
        begin   
            addr = i_addr;
            data = i_data;
            
            init_txn = 1'b1;
            
            # CLK_PERIOD 
            init_txn = 1'b0;
            
            wait(txn_done);
             # CLK_PERIOD;
        end
    endtask
    
    
    task read_data (input [31:0] i_addr, output reg [31:0] o_data);
        begin
            r_addr = i_addr;
            
            init_read = 1'b1;
         
            # CLK_PERIOD 
            init_read = 1'b0;
            
            wait(read_done);
            # CLK_PERIOD;      
             
            o_data = r_data;      
        end
    endtask

    task import_result_nowrite(input [128 * 8:0] file_name);
        begin
            file = 0;  
            file = $fopen(file_name,"rb");
            
            if (!file) begin
                $display("read: Open Error!\n");
                $finish;
            end
            
            $display("input file : %s\n", file_name);
            
            $readmemb(file_name, result_expected_32bit);
            
            $display("import result(no write) is done. \n");
            
            $fclose(file);
        end
    endtask
    
    task check_file(input [128 * 8:0] file_name);
        begin
            file = 0;  
            file = $fopen(file_name,"rb");
            
            if (!file) begin
                $display("read: Open Error!\n");
                $finish;
            end
            
            $display("input file : %s\n", file_name);
            
            $fclose(file);
        end
    endtask    
    
    //-----------------------
    //**** Instantiation ****
    //-----------------------
     
    top_simulation u_top_simulation
        (.clk(clk),
        .resetn(resetn),
        .init_txn(init_txn),
        .i_addr(addr),
        .i_data(data),
        .txn_done(txn_done),
        .init_read(init_read),
        .r_addr(r_addr),
        .r_data(r_data),
        .read_done(read_done),
        
        
        .COMMAND            (COMMAND), 
        .input_len	        (input_len), 
        .output_len	        (output_len),
        .width	            (width),
        .F_writedone 		(F_writedone),
        .B_writedone 		(B_writedone),
        .W_writedone 		(W_writedone),
        .conv_done          (conv_done)	
        );
endmodule
