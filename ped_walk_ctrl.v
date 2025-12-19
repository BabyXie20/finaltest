//======================================================================
// File Name : ped_walk_ctrl.v
// Function  : 行人斑马线行走/动画控制模块（像素时钟域）
//             - 将 50MHz/控制域信号（模式、车灯状态、行人请求）同步到 pixel_clk 域
//             - 对行人请求做上升沿检测，形成 pend_ns / pend_ew 挂起请求，避免短脉冲丢失
//             - 在“非夜间/非锁定”模式下：
//                 * 若收到 NS 行人请求且当前 NS 为红灯，则启动行人通行（sel=01）
//                 * 若收到 EW 行人请求且当前 EW 为红灯，则启动行人通行（sel=10）
//             - 行人通行期间根据 frame_tick 推进相位 ped_phase（用于动画/闪烁）
//             - 当对应方向转为绿灯时结束行人通行并复位状态
//
// Inputs/Outputs:
//   Inputs : pixel_clk, rst_n
//            frame_tick
//            mode_sel_50
//            light_ns_50, light_ew_50
//            ped_ns_50, ped_ew_50
//   Outputs: ped_active   : 行人通行激活标志
//            ped_sel      : 斑马线选择（00=无，01=NS/上方横向，10=EW/左侧纵向）
//            ped_phase    : 动画相位（每帧累加）
//
// Parameters:
//   MODE_NIGHT         : 夜间模式编码（进入后强制关闭行人通行）
//   MODE_LOCK          : 锁定模式编码（进入后强制关闭行人通行）
//   PED_STEP_PER_FRAME : 每个 frame_tick 相位步进量（动画速度）
//======================================================================

module ped_walk_ctrl #(
    parameter [1:0] MODE_NIGHT = 2'b10,
    parameter [1:0] MODE_LOCK  = 2'b11,
    parameter [7:0] PED_STEP_PER_FRAME = 8'd2
)(
    input  wire       pixel_clk,
    input  wire       rst_n,
    input  wire       frame_tick,

    input  wire [1:0] mode_sel_50,
    input  wire [2:0] light_ns_50,
    input  wire [2:0] light_ew_50,
    input  wire       ped_ns_50,
    input  wire       ped_ew_50,

    output wire       ped_active,
    output wire [1:0] ped_sel,
    output wire [7:0] ped_phase
);

    //==================================================
    // 1) 模式同步（50MHz/控制域 -> pixel_clk 域）
    //==================================================
    reg [1:0] mode_m, mode_s;
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            mode_m <= 2'b00;
            mode_s <= 2'b00;
        end else begin
            mode_m <= mode_sel_50;
            mode_s <= mode_m;
        end
    end

    //==================================================
    // 2) 车灯状态同步（NS / EW）
    //==================================================
    reg [2:0] lns_m, lns_s;
    reg [2:0] lew_m, lew_s;
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            lns_m <= 3'b000; lns_s <= 3'b000;
            lew_m <= 3'b000; lew_s <= 3'b000;
        end else begin
            lns_m <= light_ns_50; lns_s <= lns_m;
            lew_m <= light_ew_50; lew_s <= lew_m;
        end
    end

    // 灯色拆分（按既定编码：bit2=红，bit0=绿）
    wire ns_red   = lns_s[2];
    wire ns_green = lns_s[0];
    wire ew_red   = lew_s[2];
    wire ew_green = lew_s[0];

    //==================================================
    // 3) 行人请求同步 + 上升沿检测
    //    - 两级同步保证跨时钟域稳定
    //    - 再加 1 级延迟寄存器用于上升沿检测
    //==================================================
    reg pedns_m, pedns_s, pedns_d;
    reg pedew_m, pedew_s, pedew_d;
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            pedns_m <= 1'b0; pedns_s <= 1'b0; pedns_d <= 1'b0;
            pedew_m <= 1'b0; pedew_s <= 1'b0; pedew_d <= 1'b0;
        end else begin
            pedns_m <= ped_ns_50; pedns_s <= pedns_m; pedns_d <= pedns_s;
            pedew_m <= ped_ew_50; pedew_s <= pedew_m; pedew_d <= pedew_s;
        end
    end
    wire pedns_rise = pedns_s & ~pedns_d;   // NS 行人请求上升沿
    wire pedew_rise = pedew_s & ~pedew_d;   // EW 行人请求上升沿

    //==================================================
    // 4) 行人通行状态机（轻量控制）
    //    active_r : 当前是否处于“行人通行/动画”状态
    //    sel_r    : 选择哪条斑马线输出（01=NS，10=EW）
    //    phase_r  : 动画相位（frame_tick 驱动累加）
    //    pend_ns/pend_ew : 挂起的行人请求（等待对应方向变红后启动）
    //==================================================
    reg        active_r;
    reg [1:0]  sel_r;
    reg [7:0]  phase_r;
    reg        pend_ns, pend_ew;

    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            active_r <= 1'b0;
            sel_r    <= 2'b00;
            phase_r  <= 8'd0;
            pend_ns  <= 1'b0;
            pend_ew  <= 1'b0;
        end else begin
            // 夜间/锁定模式：强制清空行人通行与挂起请求
            if (mode_s == MODE_NIGHT || mode_s == MODE_LOCK) begin
                active_r <= 1'b0;
                sel_r    <= 2'b00;
                phase_r  <= 8'd0;
                pend_ns  <= 1'b0;
                pend_ew  <= 1'b0;
            end else begin
                // 记录行人请求（上升沿进入挂起队列）
                if (pedns_rise) pend_ns <= 1'b1;
                if (pedew_rise) pend_ew <= 1'b1;

                // 未激活：满足“请求挂起 + 对应方向红灯”时启动行人通行
                if (!active_r) begin
                    if (pend_ns && ns_red) begin
                        active_r <= 1'b1;
                        sel_r    <= 2'b01;   // NS：上方横向斑马线
                        phase_r  <= 8'd0;
                        pend_ns  <= 1'b0;    // 消耗该请求
                    end else if (pend_ew && ew_red) begin
                        active_r <= 1'b1;
                        sel_r    <= 2'b10;   // EW：左侧纵向斑马线
                        phase_r  <= 8'd0;
                        pend_ew  <= 1'b0;    // 消耗该请求
                    end

                // 已激活：推进动画相位；当对应方向变绿则结束通行
                end else begin
                    if (frame_tick)
                        phase_r <= phase_r + PED_STEP_PER_FRAME;

                    if (sel_r == 2'b01) begin
                        // NS 斑马线：NS 方向变绿，行人通行结束
                        if (ns_green) begin
                            active_r <= 1'b0;
                            sel_r    <= 2'b00;
                            phase_r  <= 8'd0;
                        end
                    end else if (sel_r == 2'b10) begin
                        // EW 斑马线：EW 方向变绿，行人通行结束
                        if (ew_green) begin
                            active_r <= 1'b0;
                            sel_r    <= 2'b00;
                            phase_r  <= 8'd0;
                        end
                    end else begin
                        // 选择码异常保护：回到空闲
                        active_r <= 1'b0;
                        sel_r    <= 2'b00;
                        phase_r  <= 8'd0;
                    end
                end
            end
        end
    end

    //==================================================
    // 5) 输出映射
    //==================================================
    assign ped_active = active_r;
    assign ped_sel    = sel_r;
    assign ped_phase  = phase_r;

endmodule
