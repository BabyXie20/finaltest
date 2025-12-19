//======================================================================
// File Name : time_splitter.v
// Function  : 倒计时显示拆分模块
//             - 根据当前模式 mode_sel 与相位 phase_id，将 time_left 分配到 NS 或 EW 的倒计时通道
//             - 仅在固定模式与感应模式下输出倒计时，其它模式下清零
//             - 将 NS/EW 的 0..99 时间值拆分为十位与个位，供数码管/OSD 显示
//             - 同时输出 mode_num 与 mode_ones，用于显示当前模式编号
//
// Inputs/Outputs:
//   Inputs : mode_sel, phase_id, time_left
//   Outputs: ns_tens, ns_ones, ew_tens, ew_ones
//            mode_num, mode_ones
//
// Parameters:
//   MODE_FIXED, MODE_ACT : 参与倒计时显示的模式编码
//   S_NS_GREEN, S_NS_YELLOW, S_EW_GREEN, S_EW_YELLOW : 相位编号
//======================================================================

module time_splitter #(
    parameter [1:0] MODE_FIXED  = 2'b00,
    parameter [1:0] MODE_ACT    = 2'b01,
    parameter [3:0] S_NS_GREEN  = 4'd0,
    parameter [3:0] S_NS_YELLOW = 4'd1,
    parameter [3:0] S_EW_GREEN  = 4'd3,
    parameter [3:0] S_EW_YELLOW = 4'd4
)(
    input  wire [1:0] mode_sel,
    input  wire [3:0] phase_id,
    input  wire [7:0] time_left,

    output wire [3:0] ns_tens,
    output wire [3:0] ns_ones,
    output wire [3:0] ew_tens,
    output wire [3:0] ew_ones,
    output wire [3:0] mode_num,
    output wire [3:0] mode_ones
);

    //==================================================
    // 1) NS/EW 倒计时分配寄存器
    //    time_left_ns : 需要在 NS 方向显示的倒计时
    //    time_left_ew : 需要在 EW 方向显示的倒计时
    //==================================================
    reg [7:0] time_left_ns, time_left_ew;

    //==================================================
    // 2) 倒计时分配逻辑
    //    - 仅在 MODE_FIXED 或 MODE_ACT 下进行显示分配
    //    - 依据 phase_id 判断当前是 NS 相位还是 EW 相位
    //==================================================
    always @(*) begin
        time_left_ns = 8'd0;
        time_left_ew = 8'd0;

        if (mode_sel == MODE_FIXED || mode_sel == MODE_ACT) begin
            case (phase_id)
                S_NS_GREEN,
                S_NS_YELLOW: begin
                    time_left_ns = time_left;
                    time_left_ew = 8'd0;
                end
                S_EW_GREEN,
                S_EW_YELLOW: begin
                    time_left_ns = 8'd0;
                    time_left_ew = time_left;
                end
                default: begin
                    time_left_ns = 8'd0;
                    time_left_ew = 8'd0;
                end
            endcase
        end
    end

    //==================================================
    // 3) 十位/个位拆分
    //==================================================
    assign ns_tens = time_left_ns / 10;
    assign ns_ones = time_left_ns % 10;
    assign ew_tens = time_left_ew / 10;
    assign ew_ones = time_left_ew % 10;

    //==================================================
    // 4) 模式编号输出
    //    mode_num  : 将 mode_sel 映射为 1..4 的显示数值
    //    mode_ones : 个位显示
    //==================================================
    assign mode_num  = {2'b00, mode_sel} + 4'd1;
    assign mode_ones = mode_num % 10;

endmodule
