//======================================================================
// File Name : vga_sync_640x480.v
// Function  : VGA 时序发生器
//             - 生成 640x480@60Hz 的行/场扫描计数 h_count / v_count
//             - 依据 VGA 标准时序参数产生负极性 hsync / vsync
//             - 输出 video_on 指示当前像素是否处于可视区
//
// Inputs/Outputs:
//   Inputs : clk, reset_n
//   Outputs: h_count, v_count
//            hsync, vsync
//            video_on
//======================================================================

module vga_sync_640x480 (
    input  wire       clk,
    input  wire       reset_n,
    output reg [9:0]  h_count,
    output reg [9:0]  v_count,
    output wire       hsync,
    output wire       vsync,
    output wire       video_on
);

    //==================================================
    // 1) VGA 640x480@60Hz 行/场时序参数
    //    H_MAX = 可视 + 前沿 + 同步 + 后沿
    //    V_MAX = 可视 + 前沿 + 同步 + 后沿
    //==================================================
    localparam H_VISIBLE = 640;
    localparam H_FRONT   = 16;
    localparam H_SYNC    = 96;
    localparam H_BACK    = 48;
    localparam H_MAX     = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;

    localparam V_VISIBLE = 480;
    localparam V_FRONT   = 10;
    localparam V_SYNC    = 2;
    localparam V_BACK    = 33;
    localparam V_MAX     = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;

    //==================================================
    // 2) 行/场计数器
    //    - h_count 每个像素时钟递增，达到行末回零
    //    - 行末时 v_count 递增，达到场末回零
    //==================================================
    wire h_end = (h_count == H_MAX - 1);
    wire v_end = (v_count == V_MAX - 1);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else begin
            if (h_end) begin
                h_count <= 10'd0;
                if (v_end)
                    v_count <= 10'd0;
                else
                    v_count <= v_count + 10'd1;
            end else begin
                h_count <= h_count + 10'd1;
            end
        end
    end

    //==================================================
    // 3) HS/VS 脉冲区间定义
    //    - 同步脉冲为负极性：在同步区间内输出 0
    //==================================================
    localparam HSYNC_START = H_VISIBLE + H_FRONT;
    localparam HSYNC_END   = HSYNC_START + H_SYNC;

    localparam VSYNC_START = V_VISIBLE + V_FRONT;
    localparam VSYNC_END   = VSYNC_START + V_SYNC;

    assign hsync = ~((h_count >= HSYNC_START) && (h_count < HSYNC_END));
    assign vsync = ~((v_count >= VSYNC_START) && (v_count < VSYNC_END));

    //==================================================
    // 4) 可视区指示
    //==================================================
    assign video_on = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);

endmodule
