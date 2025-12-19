//======================================================================
// File Name : boom_gen.v
// Function  : 爆炸/闪光强度生成器
//             - 对来自其它时钟域/异步域的 4 路违规触发信号进行同步
//             - 检测任意一路上升沿后，将 boom_amp 置为最大值 0xFF
//             - 在每个 frame_tick 到来时对 boom_amp 做线性衰减，直至 0
//
// Inputs    : pixel_clk   - 像素时钟（本模块工作时钟域）
//             rst_n       - 低有效复位（异步复位）
//             frame_tick  - 帧节拍脉冲（每帧 1 次，用于控制衰减节奏）
//             viol_n_50   - 北向违规触发信号
//             viol_s_50   - 南向违规触发信号
//             viol_w_50   - 西向违规触发信号
//             viol_e_50   - 东向违规触发信号
//
// Outputs   : boom_amp    - 爆炸/闪光强度输出（8 位，0~255）
//======================================================================

module boom_gen(
    input  wire       pixel_clk,
    input  wire       rst_n,
    input  wire       frame_tick,

    input  wire       viol_n_50,
    input  wire       viol_s_50,
    input  wire       viol_w_50,
    input  wire       viol_e_50,

    output reg  [7:0] boom_amp
);

    // 2FF sync + edge detect
    reg vn_m, vn_s, vn_d;
    reg vs_m, vs_s, vs_d;
    reg vw_m, vw_s, vw_d;
    reg ve_m, ve_s, ve_d;

    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            vn_m <= 1'b0; vn_s <= 1'b0; vn_d <= 1'b0;
            vs_m <= 1'b0; vs_s <= 1'b0; vs_d <= 1'b0;
            vw_m <= 1'b0; vw_s <= 1'b0; vw_d <= 1'b0;
            ve_m <= 1'b0; ve_s <= 1'b0; ve_d <= 1'b0;
        end else begin
            vn_m <= viol_n_50; vn_s <= vn_m; vn_d <= vn_s;
            vs_m <= viol_s_50; vs_s <= vs_m; vs_d <= vs_s;
            vw_m <= viol_w_50; vw_s <= vw_m; vw_d <= vw_s;
            ve_m <= viol_e_50; ve_s <= ve_m; ve_d <= ve_s;
        end
    end

    wire boom_trigger = (vn_s & ~vn_d) | (vs_s & ~vs_d) | (vw_s & ~vw_d) | (ve_s & ~ve_d);

    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            boom_amp <= 8'd0;
        end else if (boom_trigger) begin
            boom_amp <= 8'hFF;
        end else if (frame_tick) begin
            if (boom_amp != 8'd0) begin
                if (boom_amp > 8'd16) boom_amp <= boom_amp - 8'd16;
                else                  boom_amp <= 8'd0;
            end
        end
    end

endmodule
