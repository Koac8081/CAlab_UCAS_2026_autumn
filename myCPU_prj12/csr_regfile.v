// 控制状态寄存器堆,CSR
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
    input  wire [ 8:0] wb_esubcode,
    input  wire [31:0] wb_pc,
    input  wire        ertn_flush,  //写回级有ertn

    output wire [31:0] csr_era,
    output wire [31:0] csr_eentry
);

//CSR编号
localparam CSR_CRMD   = 14'h0000;   //当前模式寄存器
localparam CSR_PRMD   = 14'h0001;   //异常前模式寄存器
localparam CSR_ESTAT  = 14'h0005;   //异常状态寄存器
localparam CSR_ERA    = 14'h0006;   //异常返回地址
localparam CSR_EENTRY = 14'h000c;   //异常入口地址
localparam CSR_SAVE0  = 14'h0030;   //保存寄存器
localparam CSR_SAVE1  = 14'h0031;
localparam CSR_SAVE2  = 14'h0032;
localparam CSR_SAVE3  = 14'h0033;

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

//ESTAT，31,15:13为0
reg [5:0]  estat_ecode; //异常类
reg [8:0]  estat_esubcode;  //子类型
reg [12:0] estat_is;    //中断状态

//ERA/EENTRY/SAVE0~3
reg [31:0] era; //返回地址
reg [31:0] eentry;  //处理入口
reg [31:0] save0;   //保存寄存器
reg [31:0] save1;
reg [31:0] save2;
reg [31:0] save3;

//拼接
wire [31:0] crmd_value = {23'b0, crmd_datm, crmd_datf, crmd_pg,
                          crmd_da, crmd_ie, crmd_plv};
wire [31:0] prmd_value = {29'b0, prmd_pie, prmd_pplv};
wire [31:0] estat_value = {1'b0, estat_esubcode, estat_ecode,
                           3'b0, estat_is};

assign csr_era    = era;
assign csr_eentry = eentry;

//CSR读口：组合读出，写回级据此把旧值写入rd
always @(*) begin
    case (csr_num)
        CSR_CRMD:   csr_rvalue = crmd_value;
        CSR_PRMD:   csr_rvalue = prmd_value;
        CSR_ESTAT:  csr_rvalue = estat_value;
        CSR_ERA:    csr_rvalue = era;
        CSR_EENTRY: csr_rvalue = eentry;
        CSR_SAVE0:  csr_rvalue = save0;
        CSR_SAVE1:  csr_rvalue = save1;
        CSR_SAVE2:  csr_rvalue = save2;
        CSR_SAVE3:  csr_rvalue = save3;
        default:    csr_rvalue = 32'b0;
    endcase
end

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
        estat_ecode  <= 6'b0;
        estat_esubcode <= 9'b0;
        estat_is     <= 13'b0;
        era          <= 32'b0;
        eentry       <= 32'b0;
        save0        <= 32'b0;
        save1        <= 32'b0;
        save2        <= 32'b0;
        save3        <= 32'b0;
    end
    else if (wb_ex) begin
        //进入异常：保存现场，关闭中断并进入内核态
        era            <= wb_pc;
        estat_ecode    <= wb_ecode;
        estat_esubcode <= wb_esubcode;
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
            CSR_ESTAT: begin
                // Ecode/EsubCode由硬件在异常时更新，软件只写IS域
                estat_is <= (estat_is & ~csr_wmask[12:0]) |
                            (csr_wvalue[12:0] & csr_wmask[12:0]);
            end
            CSR_ERA: begin
                era <= (era & ~csr_wmask) |
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
            default: begin
                //未实现的CSR写入忽略，读回0
            end
        endcase
    end
end

endmodule
