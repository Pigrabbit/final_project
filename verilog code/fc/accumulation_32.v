module accumulation_32(
    input wire clk,
    input wire rstn,

    input wire en,
    output reg done,

    input wire [255:0] feature, // 32 features 
    input wire [255:0] weight, // 32 weights
    output wire [19:0] result // 20-bit result
);

localparam STATE_IDLE = 3'b000;
localparam STATE_STAGE0 = 3'b001;
localparam STATE_STAGE1 = 3'b010;
localparam STATE_STAGE2 = 3'b011;
localparam STATE_STAGE3 = 3'b100;
localparam STATE_STAGE4 = 3'b101;
localparam STATE_STAGE5 = 3'b110;
localparam STATE_DATASEND = 3'b111;

reg [2:0] state;

reg [31:0] stage0_mul32_en;
reg [15:0] stage1_adder16_en;
reg [7:0] stage2_adder8_en;
reg [3:0] stage3_adder4_en;
reg [1:0] stage4_adder2_en;
reg stage5_adder1_en;

wire [14:0] stage0_mul32_out [0:31];
wire [15:0] stage1_adder16_out [0:15];
wire [16:0] stage2_adder8_out [0:7];
wire [17:0] stage3_adder4_out [0:3];
wire [18:0] stage4_adder2_out [0:1];
wire [19:0] stage5_adder1_out;

wire [31:0] stage0_mul32_done;
wire [15:0] stage1_adder16_done;
wire [7:0] stage2_adder8_done;
wire [3:0] stage3_adder4_done;
wire [1:0] stage4_adder2_done;
wire stage5_adder1_done;

assign result = stage5_adder1_out;


genvar i;
// mul32 compute I_k * W_k, where k from 0 to 32
generate for(i = 0; i < 32; i = i + 1) begin: generate_mul32
    mac_fc #(.A_BITWIDTH(8), . OUT_BITWIDTH(15))
        u_mac_stage0_mul32 (
            .clk(clk),
            .rstn(rstn),
            .en(stage0_mul32_en[i]),
            .data_a(feature[8 * (i + 1) - 1: 8 * i]),
            .data_b(weight[8 * (i + 1) - 1: 8 * i]),
            .data_c(14'b0),
            .mout(stage0_mul32_out[i]),
            .done(stage0_mul32_done[i])
        );
    end
endgenerate
// adder 16 add up two products of I and W
generate for(i = 0; i < 16; i = i + 1) begin: generate_adder16
    mac_fc #(.A_BITWIDTH(15), .B_BITWIDTH(2), .OUT_BITWIDTH(16))
        u_mac_stage1_adder16 (
            .clk(clk),
            .rstn(rstn),
            .en(stage1_adder16_en[i]),
            .data_a(stage0_mul32_out[2 * i]),
            .data_b(2'b01),
            .data_c(stage0_mul32_out[2 * i + 1]),
            .mout(stage1_adder16_out[i]),
            .done(stage1_adder16_done[i])
        );
    end
endgenerate

generate for(i = 0; i < 8; i = i + 1) begin: generate_adder8
    mac_fc #(.A_BITWIDTH(16), .B_BITWIDTH(2), .OUT_BITWIDTH(17))
        u_mac_stage2_adder8 (
            .clk(clk),
            .rstn(rstn),
            .en(stage2_adder8_en[i]),
            .data_a(stage1_adder16_out[2 * i]),
            .data_b(2'b01),
            .data_c(stage1_adder16_out[2 * i + 1]),
            .mout(stage2_adder8_out[i]),
            .done(stage2_adder8_done[i])
        );
    end
endgenerate

generate for(i = 0; i < 4; i = i + 1) begin: generate_adder4
    mac_fc #(.A_BITWIDTH(17), .B_BITWIDTH(2), .OUT_BITWIDTH(18))
        u_mac_stage3_adder4 (
            .clk(clk),
            .rstn(rstn),
            .en(stage3_adder4_en[i]),
            .data_a(stage2_adder8_out[2 * i]),
            .data_b(2'b01),
            .data_c(stage2_adder8_out[2 * i + 1]),
            .mout(stage3_adder4_out[i]),
            .done(stage3_adder4_done[i])
        );
    end
endgenerate

generate for(i = 0; i < 2; i = i + 1) begin: generate_adder2
    mac_fc #(.A_BITWIDTH(18), .B_BITWIDTH(2), .OUT_BITWIDTH(19))
        u_mac_stage4_adder2 (
            .clk(clk),
            .rstn(rstn),
            .en(stage4_adder2_en[i]),
            .data_a(stage3_adder4_out[2 * i]),
            .data_b(2'b01),
            .data_c(stage3_adder4_out[2 * i + 1]),
            .mout(stage4_adder2_out[i]),
            .done(stage4_adder2_done[i])
        );
    end
endgenerate

mac_fc #(.A_BITWIDTH(19), .B_BITWIDTH(2), .OUT_BITWIDTH(20))
    u_mac_stage5_adder1 (
        .clk(clk),
        .rstn(rstn),
        .en(stage5_adder1_en),
        .data_a(stage4_adder2_out[0]),
        .data_b(2'b01),
        .data_c(stage4_adder2_out[1]),
        .mout(stage5_adder1_out),
        .done(stage5_adder1_done)
    );

// Control Path
always @(posedge clk or negedge rstn) begin
    if(!rstn) begin
        state <= STATE_IDLE;
    end
    else begin
        case(state)
            STATE_IDLE: begin
                if(en && !done) state <= STATE_STAGE0;
                else state <= STATE_IDLE;
            end
        
            STATE_STAGE0: begin
                if(stage0_mul32_done == {32{1'b1}}) state <= STATE_STAGE1;
            end

            STATE_STAGE1: begin
                if(stage1_adder16_done == {16{1'b1}}) state <= STATE_STAGE2;
            end

            STATE_STAGE2: begin
                if(stage2_adder8_done == {8{1'b1}}) state <= STATE_STAGE3;
            end

            STATE_STAGE3: begin
                if(stage3_adder4_done == {4{1'b1}}) state <= STATE_STAGE4;
            end

            STATE_STAGE4: begin
                if(stage4_adder2_done == {2{1'b1}}) state <= STATE_STAGE5;
            end

            STATE_STAGE5: begin
                if(stage5_adder1_done == 1'b1) state <= STATE_DATASEND;
            end

            STATE_DATASEND: begin
                if (done == 1'b1) state <= STATE_IDLE;
            end
        endcase
    end

end
// Data path
always @(posedge clk or negedge rstn) begin
    if(!rstn) begin
        stage0_mul32_en <= 32'b0;
        stage1_adder16_en <= 16'b0;
        stage2_adder8_en <= 8'b0;
        stage3_adder4_en <= 4'b0;
        stage4_adder2_en <= 2'b0;
        stage5_adder1_en <= 1'b0;
        done <= 1'b0;
    end 
    else begin
        case(state)
            STATE_IDLE: begin
                done <= 1'b0;
            end

            STATE_STAGE0: begin
                if(stage0_mul32_done == {32{1'b1}}) stage0_mul32_en <= {32{1'b0}};
                else begin
                    stage0_mul32_en <= {32{1'b1}};
                end
            end

            STATE_STAGE1: begin
                if(stage1_adder16_done == {16{1'b1}}) stage1_adder16_en <= {16{1'b0}};
                else begin
                    stage1_adder16_en <= {16{1'b1}};
                end
            end

            STATE_STAGE2: begin
                if(stage2_adder8_done == {8{1'b1}}) stage2_adder8_en <= {8{1'b0}};
                else begin
                    stage2_adder8_en <= {8{1'b1}};
                end
            end

            STATE_STAGE3: begin
                if(stage3_adder4_done == {4{1'b1}}) stage3_adder4_en <= {4{1'b0}};
                else begin
                    stage3_adder4_en <= {4{1'b1}};
                end
            end

            STATE_STAGE4: begin
                if(stage4_adder2_done == {2{1'b1}}) stage4_adder2_en <= {2{1'b0}};
                else begin
                    stage4_adder2_en <= {2{1'b1}};
                end
            end

            STATE_STAGE5: begin
                if(stage5_adder1_done) stage5_adder1_en <= 1'b0;
                else begin
                    stage5_adder1_en <= 1'b1;
                end
            end

            STATE_DATASEND: begin
                done <= 1'b1;
            end
        endcase
    end   
end
endmodule