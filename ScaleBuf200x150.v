//======================================================================
// File Name : ScaleBuf200x150.v
// Function  : 640x480 像素流缩放缓存到 200x150，并按窗口坐标读出
//             - 输入为源图像像素流与源坐标 sx/sy，pix_valid 表示有效像素区
//             - 按固定比例抽样完成 640->200、480->150 的缩放
//             - 使用双缓冲 RAM 形成 ping-pong：一帧写入 bank_fill，同时从 bank_disp 读出上一帧
//             - frame_start 作为帧边界触发：交换显示/写入 bank，并重置纵向映射
//             - win_active / win_x / win_y 定义输出窗口内的读坐标
//             - out_valid 仅在窗口有效且已至少完成一帧缓存后有效，避免上电首帧读到未初始化数据
//
// Inputs/Outputs:
//   Inputs : clk, rst_n
//            frame_start
//            pix_valid, sx, sy, in_r, in_g, in_b
//            win_active, win_x, win_y
//   Outputs: out_valid, out_r, out_g, out_b
//
// Parameters:
//   SRC_W, SRC_H : 输入分辨率
//   DST_W, DST_H : 输出分辨率
//   X_INT_STEP, X_REM_STEP : 水平方向整数步进与余数步进
//   Y_INT_STEP, Y_REM_STEP : 垂直方向整数步进与余数步进
//======================================================================

module ScaleBuf200x150 #(
    parameter integer SRC_W = 640,
    parameter integer SRC_H = 480,
    parameter integer DST_W = 200,
    parameter integer DST_H = 150,
    parameter integer X_INT_STEP = SRC_W / DST_W,
    parameter integer X_REM_STEP = SRC_W % DST_W,
    parameter integer Y_INT_STEP = SRC_H / DST_H,
    parameter integer Y_REM_STEP = SRC_H % DST_H
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        frame_start,

    input  wire        pix_valid,
    input  wire [10:0] sx,
    input  wire [10:0] sy,
    input  wire [9:0]  in_r,
    input  wire [9:0]  in_g,
    input  wire [9:0]  in_b,

    input  wire        win_active,
    input  wire [7:0]  win_x,
    input  wire [7:0]  win_y,

    output reg         out_valid,
    output reg  [9:0]  out_r,
    output reg  [9:0]  out_g,
    output reg  [9:0]  out_b
);

    //==================================================
    // 1) 输入格式压缩
    //    将 10bit RGB 转为 RGB565 存入 RAM，降低存储带宽与容量
    //==================================================
    wire [15:0] rgb565 = { in_r[9:5], in_g[9:4], in_b[9:5] };

    //==================================================
    // 2) 二维地址映射
    //    将 200x150 的坐标映射为线性地址 y*200 + x
    //==================================================
    function automatic [14:0] addr_2d;
        input [7:0] y;
        input [7:0] x;
        reg [15:0] a;
        begin
            a = ( {8'd0,y} << 7 ) + ( {8'd0,y} << 6 ) + ( {8'd0,y} << 3 ) + x;
            addr_2d = a[14:0];
        end
    endfunction

    //==================================================
    // 3) 行起始/行结束检测
    //    通过 pix_valid 上升沿/下降沿得到 line_start / line_end
    //==================================================
    reg pix_valid_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pix_valid_d <= 1'b0;
        else        pix_valid_d <= pix_valid;
    end

    wire line_start =  pix_valid & ~pix_valid_d;
    wire line_end   = ~pix_valid &  pix_valid_d;

    //==================================================
    // 4) 双缓冲银行控制
    //    bank_fill : 本帧写入的 bank
    //    bank_disp : 输出读取的 bank
    //    have_frame: 至少完成一帧写入后才允许输出
    //==================================================
    reg bank_fill;
    reg bank_disp;
    reg fs_seen;
    reg have_frame;

    //==================================================
    // 5) 写侧缩放状态
    //    dy/next_sy/y_rem 控制纵向抽样
    //    dx/next_sx/x_rem 控制横向抽样
    //    line_sample 表示当前源行是否需要被采样写入
    //==================================================
    reg [7:0]  dy;
    reg [10:0] next_sy;
    reg [8:0]  y_rem;
    reg        line_sample;

    reg [10:0] next_sx;
    reg [8:0]  x_rem;
    reg [7:0]  dx;

    reg        we;
    reg [15:0] waddr;
    reg [15:0] wdata;

    //==================================================
    // 6) 读侧窗口访问状态
    //==================================================
    reg [15:0] raddr;
    reg [15:0] rdata;
    reg        win_active_d;

    //==================================================
    // 7) 双 bank 存储体
    //    使用 64K x 16 RAM，最高位作为 bank 选择
    //==================================================
    (* ramstyle = "M10K" *) reg [15:0] mem [0:65535];

    always @(posedge clk) begin
        if (we) mem[waddr] <= wdata;
        rdata <= mem[raddr];
    end

    //==================================================
    // 8) 主时序逻辑
    //    - frame_start 触发银行交换与纵向映射复位
    //    - 在被选中的源行上按 sx==next_sx 抽样写入目标坐标 dy/dx
    //    - 行结束时推进 dy 与 next_sy
    //    - 窗口读出始终从 bank_disp 读取，并对齐 RAM 读延迟输出 out_valid/out_rgb
    //==================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bank_fill    <= 1'b0;
            bank_disp    <= 1'b0;
            fs_seen      <= 1'b0;
            have_frame   <= 1'b0;

            dy           <= 8'd0;
            next_sy      <= 11'd0;
            y_rem        <= 9'd0;
            line_sample  <= 1'b0;

            next_sx      <= 11'd0;
            x_rem        <= 9'd0;
            dx           <= 8'd0;

            we           <= 1'b0;
            waddr        <= 16'd0;
            wdata        <= 16'd0;

            raddr        <= 16'd0;
            win_active_d <= 1'b0;

            out_valid    <= 1'b0;
            out_r        <= 10'd0;
            out_g        <= 10'd0;
            out_b        <= 10'd0;

        end else begin
            we <= 1'b0;

            // 帧边界处理
            if (frame_start) begin
                bank_disp  <= bank_fill;
                bank_fill  <= ~bank_fill;

                have_frame <= fs_seen;
                fs_seen    <= 1'b1;

                dy      <= 8'd0;
                next_sy <= 11'd0;
                y_rem   <= 9'd0;
            end

            // 判定当前源行是否需要采样，并在行起始处初始化横向映射
            if (line_start) begin
                line_sample <= (dy < DST_H) && (sy == next_sy);
                if ((dy < DST_H) && (sy == next_sy)) begin
                    next_sx <= 11'd0;
                    x_rem   <= 9'd0;
                    dx      <= 8'd0;
                end
            end

            // 横向抽样写入
            if (pix_valid && line_sample && (dy < DST_H) && (dx < DST_W) && (sx == next_sx)) begin
                we    <= 1'b1;
                waddr <= {bank_fill, addr_2d(dy, dx)};
                wdata <= rgb565;

                if (x_rem + X_REM_STEP >= DST_W) begin
                    next_sx <= next_sx + X_INT_STEP + 11'd1;
                    x_rem   <= x_rem + X_REM_STEP - DST_W;
                end else begin
                    next_sx <= next_sx + X_INT_STEP;
                    x_rem   <= x_rem + X_REM_STEP;
                end
                dx <= dx + 8'd1;
            end

            // 行结束推进纵向映射
            if (line_end && line_sample && (dy < DST_H)) begin
                dy <= dy + 8'd1;

                if (y_rem + Y_REM_STEP >= DST_H) begin
                    next_sy <= next_sy + Y_INT_STEP + 11'd1;
                    y_rem   <= y_rem + Y_REM_STEP - DST_H;
                end else begin
                    next_sy <= next_sy + Y_INT_STEP;
                    y_rem   <= y_rem + Y_REM_STEP;
                end
            end

            // 窗口读地址生成
            if (win_active) raddr <= {bank_disp, addr_2d(win_y, win_x)};
            else            raddr <= {bank_disp, 15'd0};

            win_active_d <= win_active;

            // 输出有效控制
            out_valid <= win_active_d & have_frame;

            // RGB565 解包并扩展到 10bit 输出
            if (win_active_d & have_frame) begin
                out_r <= {rdata[15:11], rdata[15:11]};
                out_g <= {rdata[10:5],  rdata[10:7]};
                out_b <= {rdata[4:0],   rdata[4:0]};
            end else begin
                out_r <= 10'd0;
                out_g <= 10'd0;
                out_b <= 10'd0;
            end
        end
    end

endmodule
