//---------------------------------------------------------------------------
// 除法器包装模块
//   内部例化两个 Xilinx Divider Generator IP（参数按教材图 6.2 设置：
//   Radix2、被除数/除数位宽 32、Remainder Type = Remainder、不检测除0、
//   Clocks per Division = 8、Flow Control = Non Blocking、Optimize Goal =
//   Performance、Latency Configuration = Automatic、不勾选 ACLKEN/ARESETN）。
//
//   div_gen_signed   —— 有符号除法，用于 div.w / mod.w
//   div_gen_unsigned —— 无符号除法，用于 div.wu / mod.wu
//
//   接口说明（教材 6.2.1.2 节）：
//     * 两个输入通道各有 tvalid/tready 握手信号。除法指令在执行级且还没成功
//       送入数据时，把被除数、除数通道的 tvalid 同时置 1；一旦某个时钟上升沿
//       同时采到 tvalid 和 tready（握手成功），必须立刻把 tvalid 撤销，
//       否则除法器会认为又来了一个新的除法运算。
//     * 结果在固定延迟之后由 m_axis_dout_tvalid 指示，Non Blocking 流控下
//       输出通道不需要外部反馈 tready。m_axis_dout_tdata 的 [63:32] 是商、
//       [31:0] 是余数。
//---------------------------------------------------------------------------
module div_gen_wrap(
    input  wire        clk,
    input  wire        resetn,
    input  wire        div_req,      //执行级有除/取模指令（保持到指令离开执行级）
    input  wire        div_signed,   //1：有符号除法
    input  wire [31:0] dividend,     //被除数
    input  wire [31:0] divisor,      //除数
    output wire [63:0] dout,         //[63:32]=商 [31:0]=余数
    output wire        dout_valid    //结果已经取回
);

reg started;   //本次除法已经成功送入除法器
reg done;      //本次除法的结果已经取回

//握手：tvalid 保持到被选中的那个除法器同时给出两个通道的 tready
wire tvalid = div_req & ~started & ~done;
wire s_sel  = tvalid &  div_signed;
wire u_sel  = tvalid & ~div_signed;

wire        s_divisor_tready;
wire        s_dividend_tready;
wire        s_dout_valid;
wire [63:0] s_dout;
wire        u_divisor_tready;
wire        u_dividend_tready;
wire        u_dout_valid;
wire [63:0] u_dout;

wire handshake = (s_sel & s_dividend_tready & s_divisor_tready) |
                 (u_sel & u_dividend_tready & u_divisor_tready);

div_gen_signed u_div_gen_signed (
    .aclk                   (clk                ),
    .s_axis_divisor_tvalid  (s_sel              ),
    .s_axis_divisor_tready  (s_divisor_tready   ),
    .s_axis_divisor_tdata   (divisor            ),
    .s_axis_dividend_tvalid (s_sel              ),
    .s_axis_dividend_tready (s_dividend_tready  ),
    .s_axis_dividend_tdata  (dividend           ),
    .m_axis_dout_tvalid     (s_dout_valid       ),
    .m_axis_dout_tdata      (s_dout             )
);

div_gen_unsigned u_div_gen_unsigned (
    .aclk                   (clk                ),
    .s_axis_divisor_tvalid  (u_sel              ),
    .s_axis_divisor_tready  (u_divisor_tready   ),
    .s_axis_divisor_tdata   (divisor            ),
    .s_axis_dividend_tvalid (u_sel              ),
    .s_axis_dividend_tready (u_dividend_tready  ),
    .s_axis_dividend_tdata  (dividend           ),
    .m_axis_dout_tvalid     (u_dout_valid       ),
    .m_axis_dout_tdata      (u_dout             )
);

wire        res_valid = div_signed ? s_dout_valid : u_dout_valid;
wire [63:0] res_dout  = div_signed ? s_dout       : u_dout;

//结果被取走的那个时钟沿：流水线继续前进，这条除法指令离开执行级，
//于是把状态清干净，为下一条除法做准备（连续两条除法也不会漏掉）
wire retire = done & div_req;

always @(posedge clk) begin
    if (~resetn) begin
        started <= 1'b0;
        done    <= 1'b0;
    end
    else if (retire) begin
        started <= 1'b0;
        done    <= 1'b0;
    end
    else begin
        if (handshake) started <= 1'b1;
        if (res_valid) done    <= 1'b1;
    end
end

assign dout       = res_dout;
assign dout_valid = done;

endmodule
