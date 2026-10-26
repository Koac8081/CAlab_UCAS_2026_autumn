//CSR,控制状态寄存器，异常相关
module csr_regfile(
    input  wire        clk,
    input  wire        reset,

    //CSR读写端口
    input  wire [13:0] csr_num,
    output reg  [31:0] csr_rvalue,
    input  wire        csr_we,
    input  wire [31:0] csr_wmask,
    input  wire [31:0] csr_wvalue,

    //写回级的异常/ertn处理
    input  wire        wb_ex,   //写回级有一条异常指令
    input  wire [ 5:0] wb_ecode,
    input  wire [31:0] wb_badv,
    input  wire [31:0] wb_pc,
    input  wire        ertn_flush,  //写回级有ertn

    output wire [31:0] csr_era,
    output wire [31:0] csr_eentry,
    output wire [31:0] csr_tid,
    output wire [63:0] timer_cnt,     // 稳定计数器，供rdcntvl/rdcntvh使用
    output wire        int_pending    // 定时器/软件中断请求
);

//CSR编号
localparam CSR_CRMD   = 14'h0000;   //当前模式寄存器
localparam CSR_PRMD   = 14'h0001;   //异常前模式寄存器
localparam CSR_ECFG   = 14'h0004;
localparam CSR_ESTAT  = 14'h0005;   //异常状态寄存器
localparam CSR_ERA    = 14'h0006;   //异常返回地址
localparam CSR_BADV   = 14'h0007;
localparam CSR_EENTRY = 14'h000c;   //异常入口地址
localparam CSR_SAVE0  = 14'h0030;   //保存寄存器
localparam CSR_SAVE1  = 14'h0031;
localparam CSR_SAVE2  = 14'h0032;
localparam CSR_SAVE3  = 14'h0033;
localparam CSR_TID    = 14'h0040;
localparam CSR_TCFG   = 14'h0041;
localparam CSR_TVAL   = 14'h0042;
localparam CSR_TICLR  = 14'h0044;

//CRMD,31:9保留为0
reg [1:0] crmd_datm;
reg [1:0] crmd_datf;    //取值/访存地址模式
reg       crmd_pg;  //分页模式
reg       crmd_da;  //直接地址翻译模式
reg       crmd_ie;  //中断使能  
reg [1:0] crmd_plv; //特权级，00内核，11用户

//PRMD，31:3保留为0
reg       prmd_pie;
reg [1:0] prmd_pplv;

// ECFG
reg [12:0] ecfg_lie;

//ESTAT，31,15:13为0
reg [5:0]  estat_ecode; //异常类
reg [8:0]  estat_esubcode;  //子类型
reg [12:0] estat_is;              // bit10保留为0

// ERA / EENTRY / BADV / SAVE0~3
reg [31:0] era; //返回地址
reg [31:0] eentry;  //处理入口
reg [31:0] badv;
reg [31:0] save0;   //保存寄存器
reg [31:0] save1;
reg [31:0] save2;
reg [31:0] save3;

// 定时器
reg [31:0] tid;
reg [29:0] tcfg_init;
reg        tcfg_periodic;
reg        tcfg_en;
reg [31:0] tval;
reg [63:0] timer_cnt_r;

//拼接
wire [31:0] crmd_value = {23'b0, crmd_datm, crmd_datf, crmd_pg,
                          crmd_da, crmd_ie, crmd_plv};
wire [31:0] prmd_value = {29'b0, prmd_pie, prmd_pplv};
wire [31:0] ecfg_value = {19'b0, ecfg_lie};
//ESTAT: {EsubCode[8:0], Ecode[5:0], 3'b0, IS[12],IS[11],1'b0,IS[9:8],IS[7:0]}
wire [31:0] estat_value = {1'b0, estat_esubcode, estat_ecode,
                           3'b0, estat_is[12], estat_is[11], 1'b0,
                           estat_is[9:8], estat_is[7:0]};
wire [31:0] tcfg_value = {tcfg_init, tcfg_periodic, tcfg_en};

assign csr_era    = era;
assign csr_eentry = eentry;
assign csr_tid    = tid;
assign timer_cnt  = timer_cnt_r;
// 中断请求：CRMD.IE && (ECFG.LIE & ESTAT.IS) 任一位为1
assign int_pending = crmd_ie & (|(ecfg_lie & estat_is));

// 定时器递减/重装（每个时钟周期）
wire [31:0] tval_tick = tcfg_en ? ((tval != 32'h0) ? (tval - 32'h1) :
                                   (tcfg_periodic ? {tcfg_init, 2'b00} : tval))
                                : tval;
wire        is_ti_tick = tcfg_en ? ((tval != 32'h0) ? ((tval == 32'h1) | estat_is[11])
                                                    : estat_is[11])
                                 : estat_is[11];

//CSR读口：组合读出，写回级据此把旧值写入rd
always @(*) begin
    case (csr_num)
        CSR_CRMD:   csr_rvalue = crmd_value;
        CSR_PRMD:   csr_rvalue = prmd_value;
        CSR_ECFG:   csr_rvalue = ecfg_value;
        CSR_ESTAT:  csr_rvalue = estat_value;
        CSR_ERA:    csr_rvalue = era;
        CSR_BADV:   csr_rvalue = badv;
        CSR_EENTRY: csr_rvalue = eentry;
        CSR_SAVE0:  csr_rvalue = save0;
        CSR_SAVE1:  csr_rvalue = save1;
        CSR_SAVE2:  csr_rvalue = save2;
        CSR_SAVE3:  csr_rvalue = save3;
        CSR_TID:    csr_rvalue = tid;
        CSR_TCFG:   csr_rvalue = tcfg_value;
        CSR_TVAL:   csr_rvalue = tval;
        // TICLR为只写寄存器，读回0
        default:    csr_rvalue = 32'b0;
    endcase
end

// TCFG 写操作的下一个值
wire [31:0] tcfg_next = (tcfg_value & ~csr_wmask) | (csr_wvalue & csr_wmask);
wire        next_en      = tcfg_next[0];
wire        next_periodic= tcfg_next[1];
wire [29:0] next_init    = tcfg_next[31:2];

always @(posedge clk) begin
    if (reset) begin
        crmd_datm    <= 2'b0;
        crmd_datf    <= 2'b0;
        crmd_pg      <= 1'b0;
        crmd_da      <= 1'b1;
        crmd_ie      <= 1'b0;
        crmd_plv     <= 2'b0;
        prmd_pie     <= 1'b0;
        prmd_pplv    <= 2'b0;
        ecfg_lie     <= 13'b0;
        estat_ecode  <= 6'b0;
        estat_esubcode <= 9'b0;
        estat_is     <= 13'b0;
        era          <= 32'b0;
        eentry       <= 32'b0;
        badv         <= 32'b0;
        save0        <= 32'b0;
        save1        <= 32'b0;
        save2        <= 32'b0;
        save3        <= 32'b0;
        tid          <= 32'b0;
        tcfg_init    <= 30'b0;
        tcfg_periodic<= 1'b0;
        tcfg_en      <= 1'b0;
        tval         <= 32'b0;
        timer_cnt_r  <= 64'b0;
    end
    else begin
        // 稳定计数器与定时器默认动作
        timer_cnt_r <= timer_cnt_r + 64'd1;
        tval        <= tval_tick;
        estat_is[11]<= is_ti_tick;

        if (wb_ex) begin
            //进入异常：保存现场，关闭中断并进入内核态
            era            <= wb_pc;
            estat_ecode    <= wb_ecode;
            estat_esubcode <= 9'b0;
            //ADEF(0x8)/ALE(0x9)需要把出错地址写入BADV
            if ((wb_ecode == 6'h08) || (wb_ecode == 6'h09))
                badv       <= wb_badv;
            prmd_pplv      <= crmd_plv;
            prmd_pie       <= crmd_ie;
            crmd_plv       <= 2'b0;
            crmd_ie        <= 1'b0;
        end
        else if (ertn_flush) begin
            //异常返回：从 PRMD 恢复特权级和中断使能
            crmd_plv <= prmd_pplv;
            crmd_ie  <= prmd_pie;
        end
        else if (csr_we) begin  //写入
            case (csr_num)
                CSR_CRMD: begin
                    crmd_datm <= (crmd_datm & ~csr_wmask[8:7]) |
                                 (csr_wvalue[8:7] & csr_wmask[8:7]);
                    crmd_datf <= (crmd_datf & ~csr_wmask[6:5]) |
                                 (csr_wvalue[6:5] & csr_wmask[6:5]);
                    crmd_pg   <= (crmd_pg & ~csr_wmask[4]) |
                                 (csr_wvalue[4] & csr_wmask[4]);
                    crmd_da   <= (crmd_da & ~csr_wmask[3]) |
                                 (csr_wvalue[3] & csr_wmask[3]);
                    crmd_ie   <= (crmd_ie & ~csr_wmask[2]) |
                                 (csr_wvalue[2] & csr_wmask[2]);
                    crmd_plv  <= (crmd_plv & ~csr_wmask[1:0]) |
                                 (csr_wvalue[1:0] & csr_wmask[1:0]);
                end
                CSR_PRMD: begin
                    prmd_pie  <= (prmd_pie & ~csr_wmask[2]) |
                                 (csr_wvalue[2] & csr_wmask[2]);
                    prmd_pplv <= (prmd_pplv & ~csr_wmask[1:0]) |
                                 (csr_wvalue[1:0] & csr_wmask[1:0]);
                end
                CSR_ECFG: begin
                    // LIE[10]保留，写掩码限制为0x1bff
                    ecfg_lie <= (ecfg_lie & ~(csr_wmask[12:0] & 13'h1bff)) |
                                (csr_wvalue[12:0] & csr_wmask[12:0] & 13'h1bff);
                end
                CSR_ESTAT: begin
                    // Ecode/EsubCode 由硬件在异常时更新，软件只能写 IS[1:0]
                    estat_is[1:0] <= (estat_is[1:0] & ~csr_wmask[1:0]) |
                                     (csr_wvalue[1:0] & csr_wmask[1:0]);
                end
                CSR_ERA: begin
                    era <= (era & ~csr_wmask) |
                           (csr_wvalue & csr_wmask);
                end
                CSR_BADV: begin
                    badv <= (badv & ~csr_wmask) |
                            (csr_wvalue & csr_wmask);
                end
                CSR_EENTRY: begin
                    // EENTRY低6位固定为0
                    eentry <= (eentry & ~(csr_wmask & 32'hffffffc0)) |
                              (csr_wvalue & csr_wmask & 32'hffffffc0);
                end
                CSR_SAVE0: begin
                    save0 <= (save0 & ~csr_wmask) |
                             (csr_wvalue & csr_wmask);
                end
                CSR_SAVE1: begin
                    save1 <= (save1 & ~csr_wmask) |
                             (csr_wvalue & csr_wmask);
                end
                CSR_SAVE2: begin
                    save2 <= (save2 & ~csr_wmask) |
                             (csr_wvalue & csr_wmask);
                end
                CSR_SAVE3: begin
                    save3 <= (save3 & ~csr_wmask) |
                             (csr_wvalue & csr_wmask);
                end
                CSR_TID: begin
                    tid <= (tid & ~csr_wmask) |
                           (csr_wvalue & csr_wmask);
                end
                CSR_TCFG: begin
                    tcfg_init     <= next_init;
                    tcfg_periodic <= next_periodic;
                    tcfg_en       <= next_en;
                    // 使能时TVAL立即装入初值；否则继续当前倒计数
                    tval          <= next_en ? {next_init, 2'b00} : tval_tick;
                    estat_is[11]  <= next_en ? ((next_init == 30'h0) | is_ti_tick)
                                             : is_ti_tick;
                end
                CSR_TICLR: begin
                    // 写1清除定时器中断
                    if (csr_wmask[0] & csr_wvalue[0])
                        estat_is[11] <= 1'b0;
                end
                default: begin
                    //未实现的CSR写入忽略，读回0
                end
            endcase
        end
    end
end

endmodule
