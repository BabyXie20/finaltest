//======================================================================
// File Name : tlc_core_stage1.v
// Function  : 交通灯控制核心
//             - 支持四种模式：固定配时、感应控制、夜间黄闪、封禁全红
//             - 固定/感应模式下按状态机输出 NS/EW 车灯，并提供 phase_id 与 time_left
//             - 感应模式下根据支路来车信号决定是否提前结束当前绿灯，并设置最小/最大绿灯约束
//             - 黄灯相位在固定/感应模式下按 1Hz 闪烁输出
//             - 夜间模式下两方向黄灯闪烁
//             - 新增行人过街覆盖：在固定/感应模式且对应方向为绿时接收行人请求，触发车辆全红保持 T_PED_RED 秒
//               行人覆盖期间冻结车辆相位与秒计数，结束后恢复原相位继续运行
//
// Inputs/Outputs:
//   Inputs : clk, rst_n, tick_1s
//            mode_sel
//            veh_NS, veh_EW
//            ped_NS, ped_EW
//   Outputs: light_ns, light_ew
//            phase_id, time_left
//======================================================================

module tlc_core_stage1(
    input        clk,
    input        rst_n,
    input        tick_1s,
    input  [1:0] mode_sel,
    input        veh_NS,
    input        veh_EW,
    input        ped_NS,
    input        ped_EW,

    output reg [2:0] light_ns,
    output reg [2:0] light_ew,
    output reg [3:0] phase_id,
    output reg [7:0] time_left
);

    //==================================================
    // 1) 模式定义与模式判定
    //==================================================
    localparam [1:0] MODE_FIXED = 2'b00;
    localparam [1:0] MODE_ACT   = 2'b01;
    localparam [1:0] MODE_NIGHT = 2'b10;
    localparam [1:0] MODE_LOCK  = 2'b11;

    wire mode_fixed = (mode_sel == MODE_FIXED);
    wire mode_act   = (mode_sel == MODE_ACT);
    wire mode_night = (mode_sel == MODE_NIGHT);
    wire mode_lock  = (mode_sel == MODE_LOCK);

    //==================================================
    // 2) 配时参数
    //==================================================
    localparam integer T_NS_GREEN_MIN  = 15;
    localparam integer T_NS_GREEN_MAX  = 25;
    localparam integer T_EW_GREEN_MIN  = 10;
    localparam integer T_EW_GREEN_MAX  = 20;
    localparam integer T_YELLOW        = 5;
    localparam integer T_ALL_RED       = 2;

    localparam integer T_PED_RED       = 10;

    //==================================================
    // 3) 车辆相位状态编码
    //==================================================
    localparam [3:0]
        S_NS_GREEN  = 4'd0,
        S_NS_YELLOW = 4'd1,
        S_ALL_RED_1 = 4'd2,
        S_EW_GREEN  = 4'd3,
        S_EW_YELLOW = 4'd4,
        S_ALL_RED_2 = 4'd5;

    reg [3:0] state, next_state;
    reg [7:0] sec_counter;

    //==================================================
    // 4) 夜间黄闪计数
    //==================================================
    reg [23:0] blink_cnt;
    reg        blink_on;

    //==================================================
    // 5) 固定/感应模式下黄灯闪烁
    //==================================================
    wire in_yellow = (state == S_NS_YELLOW) || (state == S_EW_YELLOW);

    localparam integer YBLINK_HALF = 25_000_000;
    reg [24:0] yellow_cnt;
    reg        yellow_blink;

    //==================================================
    // 6) 行人过街覆盖状态
    //    ped_active      : 覆盖有效标志
    //    ped_sec_counter : 覆盖持续秒计数
    //==================================================
    reg        ped_active;
    reg [3:0]  ped_sec_counter;

    //==================================================
    // 7) 行人过街覆盖触发与计时
    //    - 仅固定/感应模式允许触发
    //    - 仅在对应方向为绿灯时接受该方向行人请求
    //    - 覆盖持续 T_PED_RED 秒，到期自动结束
    //==================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ped_active      <= 1'b0;
            ped_sec_counter <= 4'd0;
        end else begin
            if (!(mode_fixed || mode_act)) begin
                ped_active      <= 1'b0;
                ped_sec_counter <= 4'd0;
            end else if (ped_active) begin
                if (tick_1s) begin
                    if (ped_sec_counter >= T_PED_RED-1) begin
                        ped_active      <= 1'b0;
                        ped_sec_counter <= 4'd0;
                    end else begin
                        ped_sec_counter <= ped_sec_counter + 4'd1;
                    end
                end
            end else begin
                if ((state == S_NS_GREEN) && ped_NS) begin
                    ped_active      <= 1'b1;
                    ped_sec_counter <= 4'd0;
                end else if ((state == S_EW_GREEN) && ped_EW) begin
                    ped_active      <= 1'b1;
                    ped_sec_counter <= 4'd0;
                end
            end
        end
    end

    //==================================================
    // 8) 状态寄存器与秒计数
    //    - 行人覆盖期间冻结 state/sec_counter
    //    - 夜间/封禁模式下不进行车辆相位计时
    //==================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_NS_GREEN;
            sec_counter <= 8'd0;
        end else begin
            if (ped_active && (mode_fixed || mode_act)) begin
                state       <= state;
                sec_counter <= sec_counter;
            end else begin
                state <= next_state;

                if (mode_night || mode_lock) begin
                    sec_counter <= 8'd0;
                end else if (next_state != state) begin
                    sec_counter <= 8'd0;
                end else if (tick_1s) begin
                    sec_counter <= sec_counter + 8'd1;
                end
            end
        end
    end

    //==================================================
    // 9) 状态转移逻辑
    //    - 仅固定/感应模式生效
    //    - 行人覆盖期间冻结 next_state
    //==================================================
    always @(*) begin
        next_state = state;

        if (ped_active && (mode_fixed || mode_act)) begin
            next_state = state;
        end else if (mode_fixed || mode_act) begin
            case (state)
                S_NS_GREEN: begin
                    if (mode_fixed) begin
                        if (sec_counter >= T_NS_GREEN_MIN-1)
                            next_state = S_NS_YELLOW;
                    end else begin
                        if (sec_counter < T_NS_GREEN_MIN-1) begin
                            next_state = S_NS_GREEN;
                        end else if (veh_EW) begin
                            next_state = S_NS_YELLOW;
                        end else if (sec_counter >= T_NS_GREEN_MAX-1) begin
                            next_state = S_NS_YELLOW;
                        end else begin
                            next_state = S_NS_GREEN;
                        end
                    end
                end

                S_NS_YELLOW: begin
                    if (sec_counter >= T_YELLOW-1)
                        next_state = S_ALL_RED_1;
                end

                S_ALL_RED_1: begin
                    if (sec_counter >= T_ALL_RED-1)
                        next_state = S_EW_GREEN;
                end

                S_EW_GREEN: begin
                    if (mode_fixed) begin
                        if (sec_counter >= T_EW_GREEN_MIN-1)
                            next_state = S_EW_YELLOW;
                    end else begin
                        if (sec_counter < T_EW_GREEN_MIN-1) begin
                            next_state = S_EW_GREEN;
                        end else if (veh_NS) begin
                            next_state = S_EW_YELLOW;
                        end else if (sec_counter >= T_EW_GREEN_MAX-1) begin
                            next_state = S_EW_YELLOW;
                        end else begin
                            next_state = S_EW_GREEN;
                        end
                    end
                end

                S_EW_YELLOW: begin
                    if (sec_counter >= T_YELLOW-1)
                        next_state = S_ALL_RED_2;
                end

                S_ALL_RED_2: begin
                    if (sec_counter >= T_ALL_RED-1)
                        next_state = S_NS_GREEN;
                end

                default: begin
                    next_state = S_NS_GREEN;
                end
            endcase
        end
    end

    //==================================================
    // 10) time_left 生成
    //     - 固定模式使用最小绿灯作为绿灯持续时间
    //     - 感应模式在最小绿阶段显示最小绿剩余，其后显示最大绿剩余
    //==================================================
    always @(*) begin
        time_left = 8'd0;

        if (mode_fixed || mode_act) begin
            case (state)
                S_NS_GREEN: begin
                    if (mode_fixed) begin
                        time_left = (sec_counter >= T_NS_GREEN_MIN) ? 8'd0
                                   : (T_NS_GREEN_MIN - sec_counter);
                    end else begin
                        if (sec_counter < T_NS_GREEN_MIN)
                            time_left = T_NS_GREEN_MIN - sec_counter;
                        else
                            time_left = (sec_counter >= T_NS_GREEN_MAX) ? 8'd0
                                       : (T_NS_GREEN_MAX - sec_counter);
                    end
                end

                S_EW_GREEN: begin
                    if (mode_fixed) begin
                        time_left = (sec_counter >= T_EW_GREEN_MIN) ? 8'd0
                                   : (T_EW_GREEN_MIN - sec_counter);
                    end else begin
                        if (sec_counter < T_EW_GREEN_MIN)
                            time_left = T_EW_GREEN_MIN - sec_counter;
                        else
                            time_left = (sec_counter >= T_EW_GREEN_MAX) ? 8'd0
                                       : (T_EW_GREEN_MAX - sec_counter);
                    end
                end

                S_NS_YELLOW,
                S_EW_YELLOW: begin
                    time_left = (sec_counter >= T_YELLOW) ? 8'd0
                               : (T_YELLOW - sec_counter);
                end

                S_ALL_RED_1,
                S_ALL_RED_2: begin
                    time_left = (sec_counter >= T_ALL_RED) ? 8'd0
                               : (T_ALL_RED - sec_counter);
                end

                default: begin
                    time_left = 8'd0;
                end
            endcase
        end
    end

    //==================================================
    // 11) phase_id 输出
    //==================================================
    always @(*) begin
        phase_id = state;
    end

    //==================================================
    // 12) 夜间黄闪产生
    //==================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            blink_cnt <= 24'd0;
            blink_on  <= 1'b0;
        end else if (mode_night) begin
            blink_cnt <= blink_cnt + 24'd1;
            blink_on  <= blink_cnt[22];
        end else begin
            blink_cnt <= 24'd0;
            blink_on  <= 1'b0;
        end
    end

    //==================================================
    // 13) 黄灯相位闪烁计数
    //==================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            yellow_cnt   <= 25'd0;
            yellow_blink <= 1'b1;
        end else if (!(mode_fixed || mode_act)) begin
            yellow_cnt   <= 25'd0;
            yellow_blink <= 1'b1;
        end else if (ped_active) begin
            yellow_cnt   <= 25'd0;
            yellow_blink <= 1'b1;
        end else if (!in_yellow) begin
            yellow_cnt   <= 25'd0;
            yellow_blink <= 1'b1;
        end else begin
            if (yellow_cnt == YBLINK_HALF-1) begin
                yellow_cnt   <= 25'd0;
                yellow_blink <= ~yellow_blink;
            end else begin
                yellow_cnt <= yellow_cnt + 25'd1;
            end
        end
    end

    //==================================================
    // 14) 车灯输出
    //     - 默认全红
    //     - 夜间模式黄闪
    //     - 固定/感应模式按状态机输出，黄灯相位使用 yellow_blink 闪烁
    //     - 行人覆盖期间两方向强制全红
    //==================================================
    always @(*) begin
        light_ns = 3'b100;
        light_ew = 3'b100;

        if (mode_night) begin
            if (blink_on) begin
                light_ns = 3'b010;
                light_ew = 3'b010;
            end else begin
                light_ns = 3'b000;
                light_ew = 3'b000;
            end

        end else if (mode_fixed || mode_act) begin
            if (ped_active) begin
                light_ns = 3'b100;
                light_ew = 3'b100;
            end else begin
                case (state)
                    S_NS_GREEN: begin
                        light_ns = 3'b001;
                        light_ew = 3'b100;
                    end
                    S_NS_YELLOW: begin
                        light_ns = yellow_blink ? 3'b010 : 3'b000;
                        light_ew = 3'b100;
                    end
                    S_ALL_RED_1: begin
                        light_ns = 3'b100;
                        light_ew = 3'b100;
                    end
                    S_EW_GREEN: begin
                        light_ns = 3'b100;
                        light_ew = 3'b001;
                    end
                    S_EW_YELLOW: begin
                        light_ns = 3'b100;
                        light_ew = yellow_blink ? 3'b010 : 3'b000;
                    end
                    S_ALL_RED_2: begin
                        light_ns = 3'b100;
                        light_ew = 3'b100;
                    end
                    default: begin
                        light_ns = 3'b100;
                        light_ew = 3'b100;
                    end
                endcase
            end
        end
    end

endmodule
