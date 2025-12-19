//======================================================================
// File Name : reset_soft_n.v
// Function  : 硬复位键 + 软件触发的低有效复位输出
//             - rst_button_n 为板载按键复位，按下时立即产生复位
//             - soft_trig_pulse 为软件触发脉冲，触发后保持复位 SOFT_RST_CYC 个 clk 周期
//             - 输出 rst_n 为低有效复位，等价于“硬复位有效 或 软件复位窗口有效”
//
// Inputs/Outputs:
//   Inputs : clk
//            rst_button_n
//            soft_trig_pulse
//   Outputs: rst_n
//
// Parameters:
//   SOFT_RST_CYC : 软件复位保持周期数
//======================================================================

module reset_soft_n #(
    parameter integer SOFT_RST_CYC = 100_000
)(
    input  wire clk,
    input  wire rst_button_n,
    input  wire soft_trig_pulse,
    output wire rst_n
);

    //==================================================
    // 1) 软件复位窗口状态
    //    soft_rst_act : 软件复位是否处于激活窗口
    //    soft_rst_cnt : 软件复位保持计数
    //==================================================
    reg        soft_rst_act;
    reg [31:0] soft_rst_cnt;

    //==================================================
    // 2) 初始值
    //==================================================
    initial begin
        soft_rst_act = 1'b0;
        soft_rst_cnt = 32'd0;
    end

    //==================================================
    // 3) 软件复位触发与计数
    //    - 硬复位按下时，强制进入复位窗口
    //    - soft_trig_pulse 到来时，重新启动复位窗口
    //    - 在窗口内计数到 SOFT_RST_CYC 后退出窗口
    //==================================================
    always @(posedge clk or negedge rst_button_n) begin
        if (!rst_button_n) begin
            soft_rst_act <= 1'b1;
            soft_rst_cnt <= 32'd0;
        end else begin
            if (soft_trig_pulse) begin
                soft_rst_act <= 1'b1;
                soft_rst_cnt <= 32'd0;
            end else if (soft_rst_act) begin
                if (soft_rst_cnt >= (SOFT_RST_CYC-1)) begin
                    soft_rst_act <= 1'b0;
                    soft_rst_cnt <= 32'd0;
                end else begin
                    soft_rst_cnt <= soft_rst_cnt + 32'd1;
                end
            end
        end
    end

    //==================================================
    // 4) 复位输出合成
    //    - rst_button_n=0 时 rst_n 必为 0
    //    - 软件复位窗口 active 时 rst_n 也为 0
    //==================================================
    assign rst_n = rst_button_n & ~soft_rst_act;

endmodule
