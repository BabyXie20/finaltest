//======================================================================
// File Name : vga_anim_phase.v
// Function  : VGA 动画相位生成模块
//             - 在 pixel_clk 域检测 vga_vs 下降沿，生成每帧一次的 frame_tick
//             - 以帧为单位累加 anim_frame，形成逐帧变化的动画相位
//             - 将 CLOCK_50 域的 tick_1s_50 同步到 pixel_clk 域，得到 tick_1s_pix 脉冲
//             - 每秒对 anim_1s 进行一次步进累加，用于叠加“慢速”变化分量
//             - 输出 anim 为 anim_frame 与 anim_1s 的叠加结果
//
// Inputs/Outputs:
//   Inputs : pixel_clk, rst_n
//            vga_vs
//            tick_1s_50
//   Outputs: anim, frame_tick
//======================================================================

module vga_anim_phase(
    input  wire       pixel_clk,
    input  wire       rst_n,
    input  wire       vga_vs,
    input  wire       tick_1s_50,
    output wire [7:0] anim,
    output wire       frame_tick
);

    //==================================================
    // 1) 帧同步与帧计数
    //    - 通过 vga_vs 下降沿判定帧边界
    //    - anim_frame 每帧自增，用作动画相位基准
    //==================================================
    reg vs_d;
    reg [7:0] anim_frame;

    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            vs_d       <= 1'b1;
            anim_frame <= 8'd0;
        end else begin
            if (vs_d && !vga_vs) begin
                anim_frame <= anim_frame + 8'd1;
            end
            vs_d <= vga_vs;
        end
    end

    assign frame_tick = (vs_d && !vga_vs);

    //==================================================
    // 2) tick_1s 跨时钟域同步与脉冲化
    //    - tick_1s_50 来自 CLOCK_50 域，这里用两级同步到 pixel_clk 域
    //    - 对同步后的信号做上升沿检测，得到 tick_1s_pix 单周期脉冲
    //==================================================
    reg t1_meta, t1_sync, t1_sync_d;
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            t1_meta   <= 1'b0;
            t1_sync   <= 1'b0;
            t1_sync_d <= 1'b0;
        end else begin
            t1_meta   <= tick_1s_50;
            t1_sync   <= t1_meta;
            t1_sync_d <= t1_sync;
        end
    end
    wire tick_1s_pix = t1_sync & ~t1_sync_d;

    //==================================================
    // 3) 秒级相位分量
    //    anim_1s 每秒增加一次，用于叠加低频变化
    //==================================================
    reg [7:0] anim_1s;
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) anim_1s <= 8'd0;
        else if (tick_1s_pix) anim_1s <= anim_1s + 8'd16;
    end

    //==================================================
    // 4) 输出合成
    //==================================================
    assign anim = anim_frame + anim_1s;

endmodule
