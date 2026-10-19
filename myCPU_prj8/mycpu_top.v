module mycpu_top(
    input  wire        clk,
    input  wire        resetn,

    // instruction sram interface
    output wire        inst_sram_en,
    output wire [ 3:0] inst_sram_we,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata,

    // data sram interface
    output wire        data_sram_en,
    output wire [ 3:0] data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata,

    // trace debug interface
    (*mark_debug = "true"*)output wire [31:0] debug_wb_pc,
    (*mark_debug = "true"*)output wire [ 3:0] debug_wb_rf_we,
    (*mark_debug = "true"*)output wire [ 4:0] debug_wb_rf_wnum,
    (*mark_debug = "true"*)output wire [31:0] debug_wb_rf_wdata
);

//reset
reg reset;
always @(posedge clk) begin
    reset <= ~resetn;
end

//IF
reg [31:0] pc;  //当前IF正在等待返回的指令PC
reg        fs_valid;    //本拍发出的取值请求有效
reg [31:0] if_id_pc;
reg [31:0] if_id_inst;
reg        if_id_valid;    //if_id_inst有效

wire        stall;  //阻塞，当前id级指令要读的寄存器是之前未写回指令的写入寄存器
wire        id_br_taken;
wire [31:0] id_br_target;

wire [31:0] nextpc = id_br_taken ? id_br_target : (pc + 32'h4); 

assign inst_sram_addr = stall ? pc : nextpc;

always @(posedge clk) begin
    if (reset) begin
        pc       <= 32'h1bfffffc;   //第一条指令在0x1c000000
        fs_valid <= 1'b0;
        if_id_pc    <= 32'h0;
        if_id_inst  <= 32'h0;
        if_id_valid <= 1'b0;
    end
    else if (stall) begin
        //插入气泡，IF不动
    end
    else if (id_br_taken) begin
        pc       <= id_br_target;
        fs_valid <= 1'b1;
        if_id_valid <= 1'b0;
    end
    else begin
        pc       <= pc + 32'h4;
        fs_valid <= 1'b1;
        if_id_pc    <= pc;
        if_id_inst  <= inst_sram_rdata;
        if_id_valid <= fs_valid;
    end
end

assign inst_sram_en    = 1'b1;
assign inst_sram_we    = 4'b0000;
assign inst_sram_wdata = 32'b0;

//ID
wire [31:0] id_inst = if_id_valid ? if_id_inst : 32'b0;
wire [31:0] id_pc   = if_id_pc;

wire [ 5:0] op_31_26 = id_inst[31:26];
wire [ 3:0] op_25_22 = id_inst[25:22];
wire [ 1:0] op_21_20 = id_inst[21:20];
wire [ 4:0] op_19_15 = id_inst[19:15];

wire [ 4:0] rd = id_inst[ 4: 0];
wire [ 4:0] rj = id_inst[ 9: 5];
wire [ 4:0] rk = id_inst[14:10];

wire [11:0] i12 = id_inst[21:10];
wire [19:0] i20 = id_inst[24: 5];
wire [15:0] i16 = id_inst[25:10];
wire [25:0] i26 = {id_inst[ 9: 0], id_inst[25:10]};

wire [63:0] op_31_26_d;
wire [15:0] op_25_22_d;
wire [ 3:0] op_21_20_d;
wire [31:0] op_19_15_d;

decoder_6_64 u_dec0(.in(op_31_26), .out(op_31_26_d));
decoder_4_16 u_dec1(.in(op_25_22), .out(op_25_22_d));
decoder_2_4  u_dec2(.in(op_21_20), .out(op_21_20_d));
decoder_5_32 u_dec3(.in(op_19_15), .out(op_19_15_d));

wire inst_add_w;
wire inst_sub_w;
wire inst_slt;
wire inst_sltu;
wire inst_nor;
wire inst_and;
wire inst_or;
wire inst_xor;
wire inst_slli_w;
wire inst_srli_w;
wire inst_srai_w;
wire inst_addi_w;
wire inst_ld_w;
wire inst_st_w;
wire inst_jirl;
wire inst_b;
wire inst_bl;
wire inst_beq;
wire inst_bne;
wire inst_lu12i_w;

assign inst_add_w   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h00];
assign inst_sub_w   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h02];
assign inst_slt     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h04];
assign inst_sltu    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h05];
assign inst_nor     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h08];
assign inst_and     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h09];
assign inst_or      = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0a];
assign inst_xor     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0b];
assign inst_slli_w  = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h01];
assign inst_srli_w  = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h09];
assign inst_srai_w  = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h11];
assign inst_addi_w  = op_31_26_d[6'h00] & op_25_22_d[4'ha];
assign inst_ld_w    = op_31_26_d[6'h0a] & op_25_22_d[4'h2];
assign inst_st_w    = op_31_26_d[6'h0a] & op_25_22_d[4'h6];
assign inst_jirl    = op_31_26_d[6'h13];
assign inst_b       = op_31_26_d[6'h14];
assign inst_bl      = op_31_26_d[6'h15];
assign inst_beq     = op_31_26_d[6'h16];
assign inst_bne     = op_31_26_d[6'h17];
assign inst_lu12i_w = op_31_26_d[6'h05] & ~id_inst[25];

wire [11:0] id_alu_op;
assign id_alu_op[ 0] = inst_add_w | inst_addi_w | inst_ld_w | inst_st_w
                     | inst_jirl | inst_bl;
assign id_alu_op[ 1] = inst_sub_w;
assign id_alu_op[ 2] = inst_slt;
assign id_alu_op[ 3] = inst_sltu;
assign id_alu_op[ 4] = inst_and;
assign id_alu_op[ 5] = inst_nor;
assign id_alu_op[ 6] = inst_or;
assign id_alu_op[ 7] = inst_xor;
assign id_alu_op[ 8] = inst_slli_w;
assign id_alu_op[ 9] = inst_srli_w;
assign id_alu_op[10] = inst_srai_w;
assign id_alu_op[11] = inst_lu12i_w;

wire need_si20 = inst_lu12i_w;
wire need_si26 = inst_b | inst_bl;
wire src2_is_4 = inst_jirl | inst_bl;

wire [31:0] id_imm = src2_is_4 ? 32'h4 :
                     need_si20 ? {i20[19:0], 12'b0} :
                                 {{20{i12[11]}}, i12[11:0]};

wire [31:0] br_offs   = need_si26 ? {{ 4{i26[25]}}, i26[25:0], 2'b0} :
                                    {{14{i16[15]}}, i16[15:0], 2'b0};
wire [31:0] jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

wire id_src_reg_is_rd = inst_beq | inst_bne | inst_st_w;
wire id_src1_is_pc    = inst_jirl | inst_bl;
wire id_src2_is_imm   = inst_slli_w |
                        inst_srli_w |
                        inst_srai_w |
                        inst_addi_w |
                        inst_ld_w   |
                        inst_st_w   |
                        inst_lu12i_w|
                        inst_jirl   |
                        inst_bl     ;

wire id_res_from_mem = inst_ld_w;
wire id_dst_is_r1    = inst_bl;
wire id_mem_access   = inst_ld_w | inst_st_w;
wire id_mem_we       = inst_st_w;
wire id_gr_we_base   = ~inst_st_w & ~inst_beq & ~inst_bne & ~inst_b;
wire [4:0] id_dest   = id_dst_is_r1 ? 5'd1 : rd;

wire id_gr_we        = if_id_valid & id_gr_we_base;
wire id_mem_access_v = if_id_valid & id_mem_access;
wire id_mem_we_v     = if_id_valid & id_mem_we;

wire [ 4:0] rf_raddr1 = rj;
wire [ 4:0] rf_raddr2 = id_src_reg_is_rd ? rd : rk;
wire [31:0] rf_rdata1;
wire [31:0] rf_rdata2;

wire        wb_gr_we;
wire [ 4:0] wb_dest;
wire [31:0] wb_wdata;

regfile u_regfile(
    .clk    (clk       ),
    .raddr1 (rf_raddr1 ),
    .rdata1 (rf_rdata1 ),
    .raddr2 (rf_raddr2 ),
    .rdata2 (rf_rdata2 ),
    .we     (wb_gr_we  ),
    .waddr  (wb_dest   ),
    .wdata  (wb_wdata  )
);

wire rj_eq_rd = (rf_rdata1 == rf_rdata2);

assign id_br_taken = if_id_valid & (
                         (inst_beq  &  rj_eq_rd)
                       | (inst_bne  & ~rj_eq_rd)
                       |  inst_jirl
                       |  inst_bl
                       |  inst_b
                     );

assign id_br_target = (inst_beq | inst_bne | inst_bl | inst_b) ?
                       (id_pc + br_offs) :
                       (rf_rdata1 + jirl_offs);

wire [31:0] id_alu_src1 = id_src1_is_pc ? id_pc : rf_rdata1;
wire [31:0] id_alu_src2 = id_src2_is_imm ? id_imm : rf_rdata2;
wire [31:0] id_store_data = rf_rdata2;

wire id_src1_needed = if_id_valid & (
                          inst_add_w  | inst_sub_w  | inst_slt   |
                          inst_sltu   | inst_nor    | inst_and   |
                          inst_or     | inst_xor    | inst_slli_w|
                          inst_srli_w | inst_srai_w | inst_addi_w|
                          inst_ld_w   | inst_st_w   | inst_jirl  |
                          inst_beq    | inst_bne
                      );    //需要rf_addr1

wire id_src2_needed = if_id_valid & (
                          inst_add_w | inst_sub_w | inst_slt  |
                          inst_sltu  | inst_nor   | inst_and  |
                          inst_or    | inst_xor   | inst_beq  |
                          inst_bne   | inst_st_w
                      );    //需要rf_addr2

//流水线寄存器
reg [31:0] id_ex_pc;
reg [11:0] id_ex_alu_op;
reg [31:0] id_ex_alu_src1;
reg [31:0] id_ex_alu_src2;
reg        id_ex_res_from_mem;
reg        id_ex_gr_we; //是否写通用寄存器
reg        id_ex_mem_we;
reg        id_ex_mem_access;
reg [ 4:0] id_ex_dest;  //目标寄存器号
reg [31:0] id_ex_store_data;

reg [31:0] ex_mem_pc;
reg        ex_mem_res_from_mem;
reg        ex_mem_gr_we;
reg        ex_mem_mem_we;
reg        ex_mem_mem_access;
reg [ 4:0] ex_mem_dest;
reg [31:0] ex_mem_alu_result;
reg [31:0] ex_mem_store_data;

reg [31:0] mem_wb_pc;
reg        mem_wb_res_from_mem;
reg        mem_wb_gr_we;
reg [ 4:0] mem_wb_dest;
reg [31:0] mem_wb_alu_result;

//阻塞判断
//目前在ex级的指令与id级指令相关
wire src1_hit_ex = id_src1_needed & (rf_raddr1 != 5'd0) &
                   id_ex_gr_we & (id_ex_dest != 5'd0) & (rf_raddr1 == id_ex_dest);
wire src2_hit_ex = id_src2_needed & (rf_raddr2 != 5'd0) &
                   id_ex_gr_we & (id_ex_dest != 5'd0) & (rf_raddr2 == id_ex_dest);

//mem级
wire src1_hit_mem = id_src1_needed & (rf_raddr1 != 5'd0) &
                    ex_mem_gr_we & (ex_mem_dest != 5'd0) & (rf_raddr1 == ex_mem_dest);
wire src2_hit_mem = id_src2_needed & (rf_raddr2 != 5'd0) &
                    ex_mem_gr_we & (ex_mem_dest != 5'd0) & (rf_raddr2 == ex_mem_dest);

//wb级
wire src1_hit_wb = id_src1_needed & (rf_raddr1 != 5'd0) &
                   mem_wb_gr_we & (mem_wb_dest != 5'd0) & (rf_raddr1 == mem_wb_dest);
wire src2_hit_wb = id_src2_needed & (rf_raddr2 != 5'd0) &
                   mem_wb_gr_we & (mem_wb_dest != 5'd0) & (rf_raddr2 == mem_wb_dest);

assign stall = src1_hit_ex | src2_hit_ex |
               src1_hit_mem | src2_hit_mem |
               src1_hit_wb | src2_hit_wb;


//ID-EX寄存器赋值
always @(posedge clk) begin
    if (reset) begin
        id_ex_pc           <= 32'h0;
        id_ex_alu_op       <= 12'h0;
        id_ex_alu_src1     <= 32'h0;
        id_ex_alu_src2     <= 32'h0;
        id_ex_res_from_mem <= 1'b0;
        id_ex_gr_we        <= 1'b0;
        id_ex_mem_we       <= 1'b0;
        id_ex_mem_access   <= 1'b0;
        id_ex_dest         <= 5'h0;
        id_ex_store_data   <= 32'h0;
    end
    else if (stall) begin
        //插入气泡
        id_ex_pc           <= 32'h0;
        id_ex_alu_op       <= 12'h0;
        id_ex_alu_src1     <= 32'h0;
        id_ex_alu_src2     <= 32'h0;
        id_ex_res_from_mem <= 1'b0;
        id_ex_gr_we        <= 1'b0;
        id_ex_mem_we       <= 1'b0;
        id_ex_mem_access   <= 1'b0;
        id_ex_dest         <= 5'h0;
        id_ex_store_data   <= 32'h0;
    end
    else begin
        id_ex_pc           <= id_pc;
        id_ex_alu_op       <= id_alu_op;
        id_ex_alu_src1     <= id_alu_src1;
        id_ex_alu_src2     <= id_alu_src2;
        id_ex_res_from_mem <= id_res_from_mem;
        id_ex_gr_we        <= id_gr_we;
        id_ex_mem_we       <= id_mem_we_v;
        id_ex_mem_access   <= id_mem_access_v;
        id_ex_dest         <= id_dest;
        id_ex_store_data   <= id_store_data;
    end
end

//EX
wire [31:0] ex_alu_result;
alu u_alu(
    .alu_op     (id_ex_alu_op ),
    .alu_src1   (id_ex_alu_src1),
    .alu_src2   (id_ex_alu_src2),
    .alu_result (ex_alu_result)
);

//EX-MEM寄存器赋值
always @(posedge clk) begin
    if (reset) begin
        ex_mem_pc           <= 32'h0;
        ex_mem_res_from_mem <= 1'b0;
        ex_mem_gr_we        <= 1'b0;
        ex_mem_mem_we       <= 1'b0;
        ex_mem_mem_access   <= 1'b0;
        ex_mem_dest         <= 5'h0;
        ex_mem_alu_result   <= 32'h0;
        ex_mem_store_data   <= 32'h0;
    end
    else begin
        ex_mem_pc           <= id_ex_pc;
        ex_mem_res_from_mem <= id_ex_res_from_mem;
        ex_mem_gr_we        <= id_ex_gr_we;
        ex_mem_mem_we       <= id_ex_mem_we;
        ex_mem_mem_access   <= id_ex_mem_access;
        ex_mem_dest         <= id_ex_dest;
        ex_mem_alu_result   <= ex_alu_result;
        ex_mem_store_data   <= id_ex_store_data;
    end
end

//MEM
assign data_sram_en    = ex_mem_mem_access;
assign data_sram_we    = (ex_mem_mem_access & ex_mem_mem_we) ? 4'b1111 : 4'b0000;
assign data_sram_addr  = ex_mem_alu_result;
assign data_sram_wdata = ex_mem_store_data;

//MEM-WB寄存器赋值
always @(posedge clk) begin
    if (reset) begin
        mem_wb_pc           <= 32'h0;
        mem_wb_res_from_mem <= 1'b0;
        mem_wb_gr_we        <= 1'b0;
        mem_wb_dest         <= 5'h0;
        mem_wb_alu_result   <= 32'h0;
    end
    else begin
        mem_wb_pc           <= ex_mem_pc;
        mem_wb_res_from_mem <= ex_mem_res_from_mem;
        mem_wb_gr_we        <= ex_mem_gr_we;
        mem_wb_dest         <= ex_mem_dest;
        mem_wb_alu_result   <= ex_mem_alu_result;
    end
end

//WB
wire [31:0] wb_mem_result = data_sram_rdata;
assign wb_wdata = mem_wb_res_from_mem ? wb_mem_result : mem_wb_alu_result;
assign wb_gr_we = mem_wb_gr_we;
assign wb_dest  = mem_wb_dest;

//debug信号
assign debug_wb_pc       = mem_wb_pc;
assign debug_wb_rf_we    = {4{wb_gr_we}};
assign debug_wb_rf_wnum  = wb_dest;
assign debug_wb_rf_wdata = wb_wdata;

endmodule
