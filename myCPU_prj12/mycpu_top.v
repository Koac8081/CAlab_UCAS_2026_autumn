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

//exp12，系统调用异常
//异常相关信号，提前声明供取指级使用
wire [31:0] csr_era;    //csr中era寄存器的值
wire [31:0] csr_eentry; //csr中eentry的值
reg        mem_wb_is_csr;   //是否为csr指令
reg        mem_wb_is_syscall;  
reg        mem_wb_is_ertn;  
reg        mem_wb_csr_we;   //写csr
reg [13:0] mem_wb_csr_num;  //访问的csr编号
reg [31:0] mem_wb_csr_wmask;    //csr写掩码
reg [31:0] mem_wb_csr_wdata;    //csr写数据

wire        wb_redirect  = mem_wb_is_syscall | mem_wb_is_ertn;  //wb级指令要求改变pc
wire [31:0] redirect_target = mem_wb_is_ertn ? csr_era : csr_eentry;    //重定向目标

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

assign inst_sram_addr = wb_redirect ? redirect_target :
                        (stall | pipe_freeze) ? pc : nextpc;

always @(posedge clk) begin
    if (reset) begin
        pc       <= 32'h1bfffffc;   //第一条指令在0x1c000000
        fs_valid <= 1'b0;
        if_id_pc    <= 32'h0;
        if_id_inst  <= 32'h0;
        if_id_valid <= 1'b0;
    end
    else if (wb_redirect) begin
        //异常/ertn冲刷取指级，从异常入口或ERA重新取指
        pc          <= redirect_target;
        fs_valid    <= 1'b1;
        if_id_valid <= 1'b0;
    end
    else if (pipe_freeze) begin
        //等待除法
    end
    else if (stall) begin
        //插入气泡，IF不动
    end
    else if (id_br_taken) begin //分支冲刷
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
wire inst_blt;
wire inst_bge;
wire inst_bltu;
wire inst_bgeu;
wire inst_ld_b;
wire inst_ld_h;
wire inst_ld_bu;
wire inst_ld_hu;
wire inst_st_b;
wire inst_st_h;

//exp12
wire inst_csrrd;    //读csr
wire inst_csrwr;    //写csr，取回旧值
wire inst_csrxchg;  //按位交换csr
wire inst_ertn;     //异常返回
wire inst_syscall;  //系统调用

//exp9
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

//exp10,11
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
assign inst_blt     = op_31_26_d[6'h18];
assign inst_bge     = op_31_26_d[6'h19];
assign inst_bltu    = op_31_26_d[6'h1a];
assign inst_bgeu    = op_31_26_d[6'h1b];
assign inst_ld_b    = op_31_26_d[6'h0a] & op_25_22_d[4'h0];
assign inst_ld_h    = op_31_26_d[6'h0a] & op_25_22_d[4'h1];
assign inst_st_b    = op_31_26_d[6'h0a] & op_25_22_d[4'h4];
assign inst_st_h    = op_31_26_d[6'h0a] & op_25_22_d[4'h5];
assign inst_ld_bu   = op_31_26_d[6'h0a] & op_25_22_d[4'h8];
assign inst_ld_hu   = op_31_26_d[6'h0a] & op_25_22_d[4'h9];

//exp12
//CSR指令的[23:10]为CSR号；[9:5]为0/1分别表示csrrd/csrwr，
//其余值表示csrxchg中存放写掩码的rj寄存器号
assign inst_csrrd   = op_31_26_d[6'h01] & op_25_22_d[4'h0] & (rj == 5'd0);
assign inst_csrwr   = op_31_26_d[6'h01] & op_25_22_d[4'h0] & (rj == 5'd1);
assign inst_csrxchg = op_31_26_d[6'h01] & op_25_22_d[4'h0] &
                      (rj != 5'd0) & (rj != 5'd1);
assign inst_ertn    = (id_inst == 32'h06483800);
assign inst_syscall = (id_inst[31:15] == 17'h00056);

wire [21:0] id_alu_op;
//exp9
assign id_alu_op[ 0] = inst_add_w | inst_addi_w | inst_ld_w | inst_st_w
                     | inst_jirl | inst_bl | inst_pcaddu12i
                     | inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu
                     | inst_st_b | inst_st_h;
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

//exp10,11
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

//exp9
wire need_si26 = inst_b | inst_bl;  //偏移26位
wire src2_is_4 = inst_jirl | inst_bl;

//exp10,11
wire need_si20 = inst_lu12i_w | inst_pcaddu12i; //立即数高20位
wire need_ui12 = inst_andi | inst_ori | inst_xori;  //立即数12位

wire [31:0] id_imm = src2_is_4 ? 32'h4 :
                     need_si20 ? {i20[19:0], 12'b0} :
                     need_ui12 ? {20'b0, i12[11:0]} :
                                 {{20{i12[11]}}, i12[11:0]};

wire [31:0] br_offs   = need_si26 ? {{ 4{i26[25]}}, i26[25:0], 2'b0} :
                                    {{14{i16[15]}}, i16[15:0], 2'b0};
wire [31:0] jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

wire id_src_reg_is_rd = inst_beq | inst_bne | inst_st_w |
                        inst_blt | inst_bge | inst_bltu | inst_bgeu |
                        inst_st_b | inst_st_h |
                        inst_csrwr | inst_csrxchg;
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
                        inst_ld_b   |
                        inst_ld_h   |
                        inst_ld_bu  |
                        inst_ld_hu  |
                        inst_st_b   |
                        inst_st_h   |
                        inst_lu12i_w|
                        inst_pcaddu12i |
                        inst_jirl   |
                        inst_bl     ;

wire id_res_from_mem = inst_ld_w | inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu;
wire id_dst_is_r1    = inst_bl;
wire id_mem_access   = inst_ld_w | inst_st_w |
                       inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu |
                       inst_st_b | inst_st_h;
wire id_mem_we       = inst_st_w | inst_st_b | inst_st_h;
wire id_gr_we_base   = ~inst_st_w & ~inst_st_b & ~inst_st_h
                     & ~inst_beq & ~inst_bne & ~inst_b
                     & ~inst_blt & ~inst_bge & ~inst_bltu & ~inst_bgeu
                     & ~inst_syscall & ~inst_ertn;

wire [1:0] id_mem_size   = (inst_ld_b | inst_ld_bu | inst_st_b) ? 2'b01 :
                           (inst_ld_h | inst_ld_hu | inst_st_h) ? 2'b10 : 2'b00;    //访存宽度，00为字
wire       id_mem_unsign = inst_ld_bu | inst_ld_hu; //load扩展方式
wire [4:0] id_dest   = id_dst_is_r1 ? 5'd1 : rd;

//避免空指令/无效指令访存/访寄存器
wire id_gr_we        = if_id_valid & id_gr_we_base;
wire id_mem_access_v = if_id_valid & id_mem_access;
wire id_mem_we_v     = if_id_valid & id_mem_we;

wire [ 4:0] rf_raddr1 = rj;
wire [ 4:0] rf_raddr2 = id_src_reg_is_rd ? rd : rk;
wire [31:0] rf_rdata1;
wire [31:0] rf_rdata2;

//前递之后的源操作数
wire [31:0] rf_rdata1_fwd;
wire [31:0] rf_rdata2_fwd;
wire [31:0] ex_alu_result;  //ex级ALU的运算结果

//CSR读写信息随流水线传到写回级
wire [13:0] id_csr_num   = id_inst[23:10];
wire        id_is_csr    = if_id_valid &
                           (inst_csrrd | inst_csrwr | inst_csrxchg);
wire        id_csr_we    = if_id_valid & (inst_csrwr | inst_csrxchg);
wire [31:0] id_csr_wmask = inst_csrwr ? 32'hffffffff : rf_rdata1_fwd;
wire [31:0] id_csr_wdata = rf_rdata2_fwd;
wire        id_is_syscall = if_id_valid & inst_syscall;
wire        id_is_ertn    = if_id_valid & inst_ertn;

//除法相关信号提前声明
wire        id_ex_is_div;    //ex级是除/取模指令
wire        div_dout_valid;  //除法结果已经取回
wire [31:0] div_result;      //除法结果

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
wire rj_lt_rd  = $signed(rf_rdata1_fwd) < $signed(rf_rdata2_fwd);   //有符号比较
wire rj_ltu_rd = rf_rdata1_fwd < rf_rdata2_fwd;                     //无符号比较

assign id_br_taken = if_id_valid & (
                         (inst_beq  &  rj_eq_rd)
                       | (inst_bne  & ~rj_eq_rd)
                       | (inst_blt  &  rj_lt_rd)
                       | (inst_bge  & ~rj_lt_rd)
                       | (inst_bltu &  rj_ltu_rd)
                       | (inst_bgeu & ~rj_ltu_rd)
                       |  inst_jirl
                       |  inst_bl
                       |  inst_b
                     );

assign id_br_target = (inst_beq | inst_bne | inst_bl | inst_b |
                       inst_blt | inst_bge | inst_bltu | inst_bgeu) ?
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
                          | inst_blt  | inst_bge   | inst_bltu | inst_bgeu
                          | inst_ld_b | inst_ld_h  | inst_ld_bu| inst_ld_hu
                          | inst_st_b | inst_st_h
                          | inst_csrxchg
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
                          | inst_blt  | inst_bge   | inst_bltu | inst_bgeu
                          | inst_st_b | inst_st_h
                          | inst_csrwr | inst_csrxchg
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
reg [ 1:0] id_ex_mem_size;    //访存宽度,00=字 01=字节 10=半字
reg        id_ex_mem_unsign;  //零扩展（ld.bu/ld.hu）
reg        id_ex_is_csr;
reg [13:0] id_ex_csr_num;
reg        id_ex_csr_we;
reg [31:0] id_ex_csr_wmask;
reg [31:0] id_ex_csr_wdata;
reg        id_ex_is_syscall;
reg        id_ex_is_ertn;

reg [31:0] ex_mem_pc;
reg        ex_mem_res_from_mem;
reg        ex_mem_gr_we;
reg        ex_mem_mem_we;
reg        ex_mem_mem_access;
reg [ 4:0] ex_mem_dest;
reg [31:0] ex_mem_alu_result;
reg [31:0] ex_mem_store_data;
reg [ 1:0] ex_mem_mem_size;
reg        ex_mem_mem_unsign;
reg        ex_mem_is_csr;
reg [13:0] ex_mem_csr_num;
reg        ex_mem_csr_we;
reg [31:0] ex_mem_csr_wmask;
reg [31:0] ex_mem_csr_wdata;
reg        ex_mem_is_syscall;
reg        ex_mem_is_ertn;

reg [31:0] mem_wb_pc;
reg        mem_wb_res_from_mem;
reg        mem_wb_gr_we;
reg [ 4:0] mem_wb_dest;
reg [31:0] mem_wb_alu_result;
reg [ 1:0] mem_wb_mem_size;
reg        mem_wb_mem_unsign;

//相关判断
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

//前递条件判断
//load指令的alu结果为访存地址
//除/取模指令的结果来自除法器，alu的输出无意义
//在结果取回时前递div_result
wire src1_fwd_div = src1_hit_ex  & id_ex_is_div & div_dout_valid;
wire src2_fwd_div = src2_hit_ex  & id_ex_is_div & div_dout_valid;
wire src1_fwd_ex  = src1_hit_ex  & ~id_ex_res_from_mem & ~id_ex_is_div & ~id_ex_is_csr;
wire src2_fwd_ex  = src2_hit_ex  & ~id_ex_res_from_mem & ~id_ex_is_div & ~id_ex_is_csr;
wire src1_fwd_mem = src1_hit_mem & ~ex_mem_res_from_mem & ~ex_mem_is_csr;
wire src2_fwd_mem = src2_hit_mem & ~ex_mem_res_from_mem & ~ex_mem_is_csr;

//前递数据，除法器结果>执行级>访存级>写回级>寄存器堆
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
wire src1_stall = ( src1_hit_ex & id_ex_res_from_mem) |
                  (~src1_hit_ex & src1_hit_mem & ex_mem_res_from_mem);
wire src2_stall = ( src2_hit_ex & id_ex_res_from_mem) |
                  (~src2_hit_ex & src2_hit_mem & ex_mem_res_from_mem);

//CSR读出的旧值要到写回级才可用，因此相关指令继续用阻塞等待
wire src1_csr_stall = ( src1_hit_ex & id_ex_is_csr) |
                      (~src1_hit_ex & src1_hit_mem & ex_mem_is_csr);
wire src2_csr_stall = ( src2_hit_ex & id_ex_is_csr) |
                      (~src2_hit_ex & src2_hit_mem & ex_mem_is_csr);

assign stall = src1_stall | src2_stall | src1_csr_stall | src2_csr_stall;


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
        id_ex_mem_size     <= 2'h0;
        id_ex_mem_unsign   <= 1'b0;
        id_ex_is_csr       <= 1'b0;
        id_ex_csr_num      <= 14'h0;
        id_ex_csr_we       <= 1'b0;
        id_ex_csr_wmask    <= 32'h0;
        id_ex_csr_wdata    <= 32'h0;
        id_ex_is_syscall   <= 1'b0;
        id_ex_is_ertn      <= 1'b0;
    end
    else if (wb_redirect) begin
        //异常/ertn：清空错误路径上的ID-EX寄存器
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
        id_ex_mem_size     <= 2'h0;
        id_ex_mem_unsign   <= 1'b0;
        id_ex_is_csr       <= 1'b0;
        id_ex_csr_num      <= 14'h0;
        id_ex_csr_we       <= 1'b0;
        id_ex_csr_wmask    <= 32'h0;
        id_ex_csr_wdata    <= 32'h0;
        id_ex_is_syscall   <= 1'b0;
        id_ex_is_ertn      <= 1'b0;
    end
    else if (pipe_freeze) begin
        //除法等待
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
        id_ex_mem_size     <= 2'h0;
        id_ex_mem_unsign   <= 1'b0;
        id_ex_is_csr       <= 1'b0;
        id_ex_csr_num      <= 14'h0;
        id_ex_csr_we       <= 1'b0;
        id_ex_csr_wmask    <= 32'h0;
        id_ex_csr_wdata    <= 32'h0;
        id_ex_is_syscall   <= 1'b0;
        id_ex_is_ertn      <= 1'b0;
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
        id_ex_mem_size     <= id_mem_size;
        id_ex_mem_unsign   <= id_mem_unsign;
        id_ex_is_csr       <= id_is_csr;
        id_ex_csr_num      <= id_csr_num;
        id_ex_csr_we       <= id_csr_we;
        id_ex_csr_wmask    <= id_csr_wmask;
        id_ex_csr_wdata    <= id_csr_wdata;
        id_ex_is_syscall   <= id_is_syscall;
        id_ex_is_ertn      <= id_is_ertn;
    end
end

//EX
//除法器相关信号
assign id_ex_is_div    = id_ex_alu_op[18] | id_ex_alu_op[19] |
                         id_ex_alu_op[20] | id_ex_alu_op[21];
wire id_ex_div_signed  = id_ex_alu_op[18] | id_ex_alu_op[19];   //div.w / mod.w
wire id_ex_div_is_mod  = id_ex_alu_op[19] | id_ex_alu_op[21];   //mod.w / mod.wu

//MEM/WB级已有异常或ertn时，EX级属于年轻指令，不能启动新的除法
wire exception_ahead = mem_wb_is_syscall | mem_wb_is_ertn |
                       ex_mem_is_syscall | ex_mem_is_ertn;
wire div_req = id_ex_is_div & ~exception_ahead;

wire [63:0] div_dout;        //[63:32]=商，[31:0]=余数

div_gen_wrap u_div_gen_wrap(
    .clk        (clk             ),
    .resetn     (resetn          ),
    .div_req    (div_req         ),
    .div_signed (id_ex_div_signed),
    .dividend   (id_ex_alu_src1  ),
    .divisor    (id_ex_alu_src2  ),
    .dout       (div_dout        ),
    .dout_valid (div_dout_valid  )
);

//除法未完成则冻结流水线;但wb/mem级中有syscall/ertn时，不可冻结
assign pipe_freeze = id_ex_is_div & ~div_dout_valid & ~exception_ahead;

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
        ex_mem_mem_size     <= 2'h0;
        ex_mem_mem_unsign   <= 1'b0;
        ex_mem_is_csr       <= 1'b0;
        ex_mem_csr_num      <= 14'h0;
        ex_mem_csr_we       <= 1'b0;
        ex_mem_csr_wmask    <= 32'h0;
        ex_mem_csr_wdata    <= 32'h0;
        ex_mem_is_syscall   <= 1'b0;
        ex_mem_is_ertn      <= 1'b0;
    end
    else if (wb_redirect) begin
        //异常/ertn：清空错误路径上的EX-MEM寄存器
        ex_mem_pc           <= 32'h0;
        ex_mem_res_from_mem <= 1'b0;
        ex_mem_gr_we        <= 1'b0;
        ex_mem_mem_we       <= 1'b0;
        ex_mem_mem_access   <= 1'b0;
        ex_mem_dest         <= 5'h0;
        ex_mem_alu_result   <= 32'h0;
        ex_mem_store_data   <= 32'h0;
        ex_mem_mem_size     <= 2'h0;
        ex_mem_mem_unsign   <= 1'b0;
        ex_mem_is_csr       <= 1'b0;
        ex_mem_csr_num      <= 14'h0;
        ex_mem_csr_we       <= 1'b0;
        ex_mem_csr_wmask    <= 32'h0;
        ex_mem_csr_wdata    <= 32'h0;
        ex_mem_is_syscall   <= 1'b0;
        ex_mem_is_ertn      <= 1'b0;
    end
    else if (pipe_freeze) begin
        ex_mem_pc           <= 32'h0;
        ex_mem_res_from_mem <= 1'b0;
        ex_mem_gr_we        <= 1'b0;
        ex_mem_mem_we       <= 1'b0;
        ex_mem_mem_access   <= 1'b0;
        ex_mem_dest         <= 5'h0;
        ex_mem_alu_result   <= 32'h0;
        ex_mem_store_data   <= 32'h0;
        ex_mem_mem_size     <= 2'h0;
        ex_mem_mem_unsign   <= 1'b0;
        ex_mem_is_csr       <= 1'b0;
        ex_mem_csr_num      <= 14'h0;
        ex_mem_csr_we       <= 1'b0;
        ex_mem_csr_wmask    <= 32'h0;
        ex_mem_csr_wdata    <= 32'h0;
        ex_mem_is_syscall   <= 1'b0;
        ex_mem_is_ertn      <= 1'b0;
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
        ex_mem_mem_size     <= id_ex_mem_size;
        ex_mem_mem_unsign   <= id_ex_mem_unsign;
        ex_mem_is_csr       <= id_ex_is_csr;
        ex_mem_csr_num      <= id_ex_csr_num;
        ex_mem_csr_we       <= id_ex_csr_we;
        ex_mem_csr_wmask    <= id_ex_csr_wmask;
        ex_mem_csr_wdata    <= id_ex_csr_wdata;
        ex_mem_is_syscall   <= id_ex_is_syscall;
        ex_mem_is_ertn      <= id_ex_is_ertn;
    end
end

//MEM
//先复制数据，再通过使能信号选出字节
//字节写使能
wire [3:0] ex_mem_we_bytes = (ex_mem_mem_size == 2'b01) ? (4'b0001 << ex_mem_alu_result[1:0]) : //st.b
                             (ex_mem_mem_size == 2'b10) ? (ex_mem_alu_result[1] ? 4'b1100 : 4'b0011) :  //st.h
                                                          4'b1111;  //st.w

//写数据
wire [31:0] ex_mem_store_data_w = (ex_mem_mem_size == 2'b01) ? {4{ex_mem_store_data[ 7:0]}} :   //st.b
                                  (ex_mem_mem_size == 2'b10) ? {2{ex_mem_store_data[15:0]}} :   //st.h
                                                               ex_mem_store_data;   //st.w

//写回级发现异常/ertn时，MEM级中的指令是年轻指令，禁止其产生访存副作用
assign data_sram_en    = ex_mem_mem_access & ~wb_redirect;
assign data_sram_we    = (ex_mem_mem_access & ex_mem_mem_we & ~wb_redirect) ?
                         ex_mem_we_bytes : 4'b0000;
assign data_sram_addr  = ex_mem_alu_result;
assign data_sram_wdata = ex_mem_store_data_w;

//MEM-WB寄存器赋值
always @(posedge clk) begin
    if (reset) begin
        mem_wb_pc           <= 32'h0;
        mem_wb_res_from_mem <= 1'b0;
        mem_wb_gr_we        <= 1'b0;
        mem_wb_dest         <= 5'h0;
        mem_wb_alu_result   <= 32'h0;
        mem_wb_mem_size     <= 2'h0;
        mem_wb_mem_unsign   <= 1'b0;
        mem_wb_is_csr       <= 1'b0;
        mem_wb_csr_num      <= 14'h0;
        mem_wb_csr_we       <= 1'b0;
        mem_wb_csr_wmask    <= 32'h0;
        mem_wb_csr_wdata    <= 32'h0;
        mem_wb_is_syscall   <= 1'b0;
        mem_wb_is_ertn      <= 1'b0;
    end
    else if (wb_redirect) begin
        //异常/ertn：写回级本身不产生通用寄存器写，后续流水级清空
        mem_wb_pc           <= 32'h0;
        mem_wb_res_from_mem <= 1'b0;
        mem_wb_gr_we        <= 1'b0;
        mem_wb_dest         <= 5'h0;
        mem_wb_alu_result   <= 32'h0;
        mem_wb_mem_size     <= 2'h0;
        mem_wb_mem_unsign   <= 1'b0;
        mem_wb_is_csr       <= 1'b0;
        mem_wb_csr_num      <= 14'h0;
        mem_wb_csr_we       <= 1'b0;
        mem_wb_csr_wmask    <= 32'h0;
        mem_wb_csr_wdata    <= 32'h0;
        mem_wb_is_syscall   <= 1'b0;
        mem_wb_is_ertn      <= 1'b0;
    end
    else begin
        mem_wb_pc           <= ex_mem_pc;
        mem_wb_res_from_mem <= ex_mem_res_from_mem;
        mem_wb_gr_we        <= ex_mem_gr_we;
        mem_wb_dest         <= ex_mem_dest;
        mem_wb_alu_result   <= ex_mem_alu_result;
        mem_wb_mem_size     <= ex_mem_mem_size;
        mem_wb_mem_unsign   <= ex_mem_mem_unsign;
        mem_wb_is_csr       <= ex_mem_is_csr;
        mem_wb_csr_num      <= ex_mem_csr_num;
        mem_wb_csr_we       <= ex_mem_csr_we;
        mem_wb_csr_wmask    <= ex_mem_csr_wmask;
        mem_wb_csr_wdata    <= ex_mem_csr_wdata;
        mem_wb_is_syscall   <= ex_mem_is_syscall;
        mem_wb_is_ertn      <= ex_mem_is_ertn;
    end
end

//WB
//从内存输出的32位数据中按地址最低两位挑出字节/半字，并按指令做符号/零扩展
wire [1:0]  mem_wb_lo   = mem_wb_alu_result[1:0];
wire [7:0]  mem_wb_byte = mem_wb_lo[1] ? (mem_wb_lo[0] ? data_sram_rdata[31:24] : data_sram_rdata[23:16])
                                        : (mem_wb_lo[0] ? data_sram_rdata[15: 8] : data_sram_rdata[ 7: 0]);
wire [15:0] mem_wb_half = mem_wb_lo[1] ? data_sram_rdata[31:16] : data_sram_rdata[15:0];

wire [31:0] wb_mem_result = (mem_wb_mem_size == 2'b01) ?
                                (mem_wb_mem_unsign ? {24'b0, mem_wb_byte}
                                                   : {{24{mem_wb_byte[7]}}, mem_wb_byte}) :
                            (mem_wb_mem_size == 2'b10) ?
                                (mem_wb_mem_unsign ? {16'b0, mem_wb_half}
                                                   : {{16{mem_wb_half[15]}}, mem_wb_half}) :
                                data_sram_rdata;

//CSR与异常处理放在写回级
wire [31:0] csr_rvalue; //csr读出值
wire [ 5:0] wb_ecode    = mem_wb_is_syscall ? 6'h0b : 6'h0; //异常原因码，syscall0x0B
wire [ 8:0] wb_esubcode = 9'h0; //异常子原因码，exp12固定为0

csr_regfile u_csr_regfile(
    .clk        (clk                 ),
    .reset      (reset               ),
    .csr_num    (mem_wb_csr_num      ),
    .csr_rvalue (csr_rvalue          ),
    .csr_we     (mem_wb_csr_we & ~wb_redirect),
    .csr_wmask  (mem_wb_csr_wmask    ),
    .csr_wvalue (mem_wb_csr_wdata    ),
    .wb_ex      (mem_wb_is_syscall   ),
    .wb_ecode   (wb_ecode            ),
    .wb_esubcode(wb_esubcode         ),
    .wb_pc      (mem_wb_pc           ),
    .ertn_flush (mem_wb_is_ertn      ),
    .csr_era    (csr_era             ),
    .csr_eentry (csr_eentry          )
);

assign wb_wdata = mem_wb_res_from_mem ? wb_mem_result :
                  mem_wb_is_csr     ? csr_rvalue   :
                                      mem_wb_alu_result;
assign wb_gr_we = mem_wb_gr_we & ~wb_redirect;
assign wb_dest  = mem_wb_dest;

//debug信号
assign debug_wb_pc       = mem_wb_pc;
assign debug_wb_rf_we    = {4{wb_gr_we}};
assign debug_wb_rf_wnum  = wb_dest;
assign debug_wb_rf_wdata = wb_wdata;

endmodule
