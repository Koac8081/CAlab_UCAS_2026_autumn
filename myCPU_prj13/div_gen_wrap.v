//除法器包装模块
module div_gen_wrap(
    input  wire        clk,
    input  wire        resetn,
    input  wire        div_req,      //ex级有除/取模指令
    input  wire        div_signed,   //有符号除法
    input  wire [31:0] dividend,     //被除数
    input  wire [31:0] divisor,      //除数
    output wire [63:0] dout,         //[63:32]=商，[31:0]=余数
    output wire        dout_valid    //结果已经取回
);

reg started;   //本次除法已送入除法器
reg done;      //本次除法结果已取回

//握手信号，tvalid保持到握手成功
wire tvalid = div_req & ~started & ~done;
wire s_sel  = tvalid &  div_signed; //选择有符号
wire u_sel  = tvalid & ~div_signed; //无符号

//有符号
wire        s_divisor_tready;
wire        s_dividend_tready;
wire        s_dout_valid;
wire [63:0] s_dout;

//无符号
wire        u_divisor_tready;
wire        u_dividend_tready;
wire        u_dout_valid;
wire [63:0] u_dout;

wire handshake = (s_sel & s_dividend_tready & s_divisor_tready) |
                 (u_sel & u_dividend_tready & u_divisor_tready);    //握手成功

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

wire retire = done & div_req;   //结果被取走，指令即将离开ex级

//除法指令持续多拍，需要用start/done寄存状态
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
