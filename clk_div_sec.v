//======================================================================
// File Name : clk_dividers.v
// Function  : 时钟分频/节拍产生模块集合
//             1) clk_div_sec      : 50MHz -> 1 秒一次 tick_1s（单个 clk 周期脉冲）
//             2) vga_pixclk_div2  : 50MHz -> 25MHz 像素时钟 pixclk（2 分频方波）
//             3) car_tick_div     : 可参数化的节拍产生器 tick_car（单个 clk 周期脉冲）
//
// Inputs/Outputs:
//   [clk_div_sec]
//     Inputs : clk（输入时钟，如 50MHz）, rst_n（低有效复位）
//     Output : tick_1s（1 秒节拍脉冲，宽度 1 个 clk 周期）
//
//   [vga_pixclk_div2]
//     Inputs : clk50（50MHz 输入时钟）, rst_n（低有效复位）
//     Output : pixclk（25MHz 像素时钟输出，2 分频）
//
//   [car_tick_div]
//     Inputs : clk（输入时钟）, rst_n（低有效复位）
//     Output : tick_car（车辆移动节拍脉冲，宽度 1 个 clk 周期）
//======================================================================


//======================================================
// 1) clk_div_sec：50MHz -> 1 秒一个 tick
//======================================================
module clk_div_sec #(
    // 50MHz 时钟 -> 1 秒一个 tick
    parameter CNT_MAX = 32'd50_000_000 - 1
)(
    input       clk,       // 输入时钟（例如 50MHz）
    input       rst_n,      // 低有效复位
    output reg  tick_1s     // 1 秒节拍脉冲（宽度 1 个 clk 周期）
);
    reg [31:0] cnt;         // 计数器

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt     <= 32'd0;
            tick_1s <= 1'b0;
        end else begin
            if (cnt >= CNT_MAX) begin
                cnt     <= 32'd0;
                tick_1s <= 1'b1;   // 产生一个周期为 1 个 clk 的脉冲
            end else begin
                cnt     <= cnt + 32'd1;
                tick_1s <= 1'b0;
            end
        end
    end

endmodule


//======================================================
// 2) vga_pixclk_div2：50MHz -> 25MHz 像素时钟（2 分频）
//======================================================
module vga_pixclk_div2(
    input  wire clk50,     // 50MHz 输入时钟
    input  wire rst_n,      // 低有效复位
    output wire pixclk     // 25MHz 输出像素时钟（2 分频）
);
    reg q;                  // 分频触发器

    always @(posedge clk50 or negedge rst_n) begin
        if (!rst_n) q <= 1'b0;
        else        q <= ~q; // 每个上升沿翻转一次，实现 2 分频
    end

    assign pixclk = q;

endmodule


//======================================================
// 3) car_tick_div：可参数化节拍（用于车辆移动等）
//======================================================
module car_tick_div #(
    // DIV_MAX 决定 tick_car 的周期：计数到 DIV_MAX 时输出 1 个周期脉冲
    parameter [25:0] DIV_MAX = 26'd4_999_999
)(
    input  wire clk,       // 输入时钟
    input  wire rst_n,      // 低有效复位
    output reg  tick_car    // 节拍脉冲输出（宽度 1 个 clk 周期）
);
    reg [25:0] cnt;         // 计数器

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt      <= 26'd0;
            tick_car <= 1'b0;
        end else begin
            if (cnt == DIV_MAX) begin
                cnt      <= 26'd0;
                tick_car <= 1'b1;  // 到达分频终值，输出 1 个周期脉冲
            end else begin
                cnt      <= cnt + 26'd1;
                tick_car <= 1'b0;
            end
        end
    end
endmodule
