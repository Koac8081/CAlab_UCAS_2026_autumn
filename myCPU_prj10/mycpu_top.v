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
wire        pipe_freeze;  //除法进行中，冻结整条流水线
wire        id_br_taken;
wire [31:0] id_br_target;

wire [31:0] nextpc = id_br_taken ? id_br_target : (pc + 32'h4); 

assign inst_sram_addr = (stall | pipe_freeze) ? pc : nextpc;

always @(posedge clk) begin
    if (reset) begin
        pc       <= 32'h1bfffffc;   //第一条指令在0x1c000000
        fs_valid <= 1'b0;
        if_id_pc    <= 32'h0;
        if_id_inst  <= 32'h0;
        if_id_valid <= 1'b0;
    end
    else if (pipe_freeze) begin
        //除法进行中：取指暂停，保持当前状态
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
wire inst_slti;
wire inst_sltui;
wire inst_andi;
wire inst_ori;
wire inst_xori;
wire inst_sll_w;
wire inst_srl_w;
wire inst_sra_w;
wire inst_pcaddu12i;
wire inst_mul_w;
wire inst_mulh_w;
wire inst_mulh_wu;
wire inst_div_w;
wire inst_mod_w;
wire inst_div_wu;
wire inst_mod_wu;

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
assign inst_slti    = op_31_26_d[6'h00] & op_25_22_d[4'h8];
assign inst_sltui   = op_31_26_d[6'h00] & op_25_22_d[4'h9];
assign inst_andi    = op_31_26_d[6'h00] & op_25_22_d[4'hd];
assign inst_ori     = op_31_26_d[6'h00] & op_25_22_d[4'he];
assign inst_xori    = op_31_26_d[6'h00] & op_25_22_d[4'hf];
assign inst_sll_w   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0e];
assign inst_srl_w   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0f];
assign inst_sra_w   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h10];
assign inst_pcaddu12i = op_31_26_d[6'h07] & ~id_inst[25];
assign inst_mul_w   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h18];
assign inst_mulh_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h19];
assign inst_mulh_wu = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h1a];
assign inst_div_w   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h00];
assign inst_mod_w   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h01];
assign inst_div_wu  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h02];
assign inst_mod_wu  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h03];

wire [21:0] id_alu_op;
assign id_alu_op[ 0] = inst_add_w | inst_addi_w | inst_ld_w | inst_st_w
                     | inst_jirl | inst_bl | inst_pcaddu12i;
assign id_alu_op[ 1] = inst_sub_w;
assign id_alu_op[ 2] = inst_slt | inst_slti;
assign id_alu_op[ 3] = inst_sltu | inst_sltui;
assign id_alu_op[ 4] = inst_and | inst_andi;
assign id_alu_op[ 5] = inst_nor;
assign id_alu_op[ 6] = inst_or | inst_ori;
assign id_alu_op[ 7] = inst_xor | inst_xori;
assign id_alu_op[ 8] = inst_slli_w;
assign id_alu_op[ 9] = inst_srli_w;
assign id_alu_op[10] = inst_srai_w;
assign id_alu_op[11] = inst_lu12i_w;
assign id_alu_op[12] = inst_sll_w;
assign id_alu_op[13] = inst_srl_w;
assign id_alu_op[14] = inst_sra_w;
assign id_alu_op[15] = inst_mul_w;
assign id_alu_op[16] = inst_mulh_w;
assign id_alu_op[17] = inst_mulh_wu;
assign id_alu_op[18] = inst_div_w;
assign id_alu_op[19] = inst_mod_w;
assign id_alu_op[20] = inst_div_wu;
assign id_alu_op[21] = inst_mod_wu;

wire need_si20 = inst_lu12i_w | inst_pcaddu12i;
//注意：按参考实现（gettrace 的 SimpleLACore），sltui 的 12 位立即数按符号扩展处理，
//      与 andi/ori/xori 的零扩展不同，这里保持一致才能通过 trace 比对
wire need_ui12 = inst_andi | inst_ori | inst_xori;
wire need_si26 = inst_b | inst_bl;
wire src2_is_4 = inst_jirl | inst_bl;

wire [31:0] id_imm = src2_is_4 ? 32'h4 :
                     need_si20 ? {i20[19:0], 12'b0} :
                     need_ui12 ? {20'b0, i12[11:0]} :
                                 {{20{i12[11]}}, i12[11:0]};

wire [31:0] br_offs   = need_si26 ? {{ 4{i26[25]}}, i26[25:0], 2'b0} :
                                    {{14{i16[15]}}, i16[15:0], 2'b0};
wire [31:0] jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

wire id_src_reg_is_rd = inst_beq | inst_bne | inst_st_w;
wire id_src1_is_pc    = inst_jirl | inst_bl | inst_pcaddu12i;
wire id_src2_is_imm   = inst_slli_w |
                        inst_srli_w |
                        inst_srai_w |
                        inst_addi_w |
                        inst_slti   |
                        inst_sltui  |
                        inst_andi   |
                        inst_ori    |
                        inst_xori   |
                        inst_ld_w   |
                        inst_st_w   |
                        inst_lu12i_w|
                        inst_pcaddu12i |
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

//前递之后的源操作数（生成逻辑见下面“数据前递”一节）
wire [31:0] rf_rdata1_fwd;
wire [31:0] rf_rdata2_fwd;
wire [31:0] ex_alu_result;  //执行级ALU的运算结果
//除法相关信号提前声明（赋值见下面“除法器”一节）
wire        id_ex_is_div;    //执行级是除/取模指令
wire        div_dout_valid;  //除法结果已经取回
wire [31:0] div_result;      //除法结果（商或余数）

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

wire rj_eq_rd = (rf_rdata1_fwd == rf_rdata2_fwd);

assign id_br_taken = if_id_valid & (
                         (inst_beq  &  rj_eq_rd)
                       | (inst_bne  & ~rj_eq_rd)
                       |  inst_jirl
                       |  inst_bl
                       |  inst_b
                     );

assign id_br_target = (inst_beq | inst_bne | inst_bl | inst_b) ?
                       (id_pc + br_offs) :
                       (rf_rdata1_fwd + jirl_offs);

wire [31:0] id_alu_src1 = id_src1_is_pc ? id_pc : rf_rdata1_fwd;
wire [31:0] id_alu_src2 = id_src2_is_imm ? id_imm : rf_rdata2_fwd;
wire [31:0] id_store_data = rf_rdata2_fwd;

wire id_src1_needed = if_id_valid & (
                          inst_add_w  | inst_sub_w  | inst_slt   |
                          inst_sltu   | inst_nor    | inst_and   |
                          inst_or     | inst_xor    | inst_slli_w|
                          inst_srli_w | inst_srai_w | inst_addi_w|
                          inst_ld_w   | inst_st_w   | inst_jirl  |
                          inst_beq    | inst_bne    |
                          inst_slti   | inst_sltui  | inst_andi  |
                          inst_ori    | inst_xori   | inst_sll_w |
                          inst_srl_w  | inst_sra_w  | inst_mul_w |
                          inst_mulh_w | inst_mulh_wu| inst_div_w |
                          inst_mod_w  | inst_div_wu | inst_mod_wu
                      );    //需要rf_addr1

wire id_src2_needed = if_id_valid & (
                          inst_add_w | inst_sub_w | inst_slt  |
                          inst_sltu  | inst_nor   | inst_and  |
                          inst_or    | inst_xor   | inst_beq  |
                          inst_bne   | inst_st_w  |
                          inst_sll_w | inst_srl_w | inst_sra_w|
                          inst_mul_w | inst_mulh_w| inst_mulh_wu|
                          inst_div_w | inst_mod_w | inst_div_wu|
                          inst_mod_wu
                      );    //需要rf_addr2

//流水线寄存器
reg [31:0] id_ex_pc;
reg [21:0] id_ex_alu_op;
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

//数据前递（forwarding）
//  写后读相关的本质是：译码级指令要读的寄存器，前面某条指令还没写回。可是前面
//  那条指令的结果往往早就运算出来了，只是还放在流水线寄存器里没有写进寄存器堆。
//  增加前递通路，把这个结果直接送到译码级的源操作数选择逻辑，就可以省掉等待。
//  结果越新的流水级优先级越高：执行级 > 访存级 > 写回级 > 寄存器堆读出结果。

//命中判断：前面指令确实要写通用寄存器，且目的寄存器号正是译码级要读的寄存器号
wire src1_hit_ex = id_src1_needed & (rf_raddr1 != 5'd0) &
                   id_ex_gr_we & (id_ex_dest != 5'd0) & (rf_raddr1 == id_ex_dest);
wire src2_hit_ex = id_src2_needed & (rf_raddr2 != 5'd0) &
                   id_ex_gr_we & (id_ex_dest != 5'd0) & (rf_raddr2 == id_ex_dest);

wire src1_hit_mem = id_src1_needed & (rf_raddr1 != 5'd0) &
                    ex_mem_gr_we & (ex_mem_dest != 5'd0) & (rf_raddr1 == ex_mem_dest);
wire src2_hit_mem = id_src2_needed & (rf_raddr2 != 5'd0) &
                    ex_mem_gr_we & (ex_mem_dest != 5'd0) & (rf_raddr2 == ex_mem_dest);

wire src1_hit_wb = id_src1_needed & (rf_raddr1 != 5'd0) &
                   mem_wb_gr_we & (mem_wb_dest != 5'd0) & (rf_raddr1 == mem_wb_dest);
wire src2_hit_wb = id_src2_needed & (rf_raddr2 != 5'd0) &
                   mem_wb_gr_we & (mem_wb_dest != 5'd0) & (rf_raddr2 == mem_wb_dest);

//load指令要到访存级结束才能从数据RAM取回数据，所以执行级、访存级都没有它的结果
//（执行级ALU给出的是访存地址，不是读数），这两条前递通路要把load指令排除掉；
//而到了写回级，load的数据已经出现在data_sram_rdata上，可以正常前递
//除/取模指令的结果来自除法器，执行级ALU的输出对它没有意义，同样要排除，
//改为在结果取回的那一拍直接前递 div_result
wire src1_fwd_div = src1_hit_ex  & id_ex_is_div & div_dout_valid;
wire src2_fwd_div = src2_hit_ex  & id_ex_is_div & div_dout_valid;
wire src1_fwd_ex  = src1_hit_ex  & ~id_ex_res_from_mem & ~id_ex_is_div;
wire src2_fwd_ex  = src2_hit_ex  & ~id_ex_res_from_mem & ~id_ex_is_div;
wire src1_fwd_mem = src1_hit_mem & ~ex_mem_res_from_mem;
wire src2_fwd_mem = src2_hit_mem & ~ex_mem_res_from_mem;

//带优先级的多选：除法器结果 > 执行级 > 访存级 > 写回级 > 寄存器堆
assign rf_rdata1_fwd = src1_fwd_div ? div_result        :
                       src1_fwd_ex  ? ex_alu_result     :
                       src1_fwd_mem ? ex_mem_alu_result :
                       src1_hit_wb  ? wb_wdata          :
                                      rf_rdata1;

assign rf_rdata2_fwd = src2_fwd_div ? div_result        :
                       src2_fwd_ex  ? ex_alu_result     :
                       src2_fwd_mem ? ex_mem_alu_result :
                       src2_hit_wb  ? wb_wdata          :
                                      rf_rdata2;

//阻塞判断
//  前递之后，只有当产生结果的最近一条指令是load、而它的数据还没有从数据RAM
//  取回来（load在执行级或访存级）时，译码级才需要停一拍等它。
//  src1_hit_ex等信号指示的已经是该寄存器的最近一个产生者（流水线是按序的）
wire src1_stall = ( src1_hit_ex & id_ex_res_from_mem) |
                  (~src1_hit_ex & src1_hit_mem & ex_mem_res_from_mem);
wire src2_stall = ( src2_hit_ex & id_ex_res_from_mem) |
                  (~src2_hit_ex & src2_hit_mem & ex_mem_res_from_mem);

assign stall = src1_stall | src2_stall;


//ID-EX寄存器赋值
always @(posedge clk) begin
    if (reset) begin
        id_ex_pc           <= 32'h0;
        id_ex_alu_op       <= 22'h0;
        id_ex_alu_src1     <= 32'h0;
        id_ex_alu_src2     <= 32'h0;
        id_ex_res_from_mem <= 1'b0;
        id_ex_gr_we        <= 1'b0;
        id_ex_mem_we       <= 1'b0;
        id_ex_mem_access   <= 1'b0;
        id_ex_dest         <= 5'h0;
        id_ex_store_data   <= 32'h0;
    end
    else if (pipe_freeze) begin
        //除法进行中：保持执行级这条除法指令不动
    end
    else if (stall) begin
        //插入气泡
        id_ex_pc           <= 32'h0;
        id_ex_alu_op       <= 22'h0;
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
//------------------------------------------------------------------
//除法器：div.w / mod.w / div.wu / mod.wu 由 Xilinx Divider Generator IP 完成，
//多周期，所以执行级有这类指令时要冻结整条流水线，等结果回来再继续
//------------------------------------------------------------------
assign id_ex_is_div    = id_ex_alu_op[18] | id_ex_alu_op[19] |
                         id_ex_alu_op[20] | id_ex_alu_op[21];
wire id_ex_div_signed  = id_ex_alu_op[18] | id_ex_alu_op[19];   //div.w / mod.w
wire id_ex_div_is_mod  = id_ex_alu_op[19] | id_ex_alu_op[21];   //mod.w / mod.wu

wire [63:0] div_dout;        //[63:32]=商 [31:0]=余数

div_gen_wrap u_div_gen_wrap(
    .clk        (clk             ),
    .resetn     (resetn          ),
    .div_req    (id_ex_is_div    ),
    .div_signed (id_ex_div_signed),
    .dividend   (id_ex_alu_src1  ),
    .divisor    (id_ex_alu_src2  ),
    .dout       (div_dout        ),
    .dout_valid (div_dout_valid  )
);

//除法未完成：冻结整条流水线（所有流水寄存器保持不变）
assign pipe_freeze = id_ex_is_div & ~div_dout_valid;

assign div_result = id_ex_div_is_mod ? div_dout[31:0] : div_dout[63:32];
wire [31:0] ex_result  = id_ex_is_div ? div_result : ex_alu_result;

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
    else if (pipe_freeze) begin
        //除法进行中：访存级清成气泡，让后面的指令正常排空（每条指令只写回一次）
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
        ex_mem_alu_result   <= ex_result;
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
