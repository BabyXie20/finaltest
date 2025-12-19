//======================================================================
// File Name : ps2_keyboard.v
// Function  : PS/2 键盘扫描码解析模块
//             - 解析 PS/2 Set 2 扫描码
//             - 正确处理 E0 扩展前缀与 F0 释放前缀
//             - 方向键与 W/S/A/D 输出为 level，支持多键同时按住
//             - 感应模式 veh_* 使用 T/G 为 level，F/H 为 pulse
//             - R 为复位脉冲，O/P 为行人请求脉冲
//             - 对 pulse 类按键做“按下锁存”抑制 typematic 连发
//
// Inputs/Outputs:
//   Inputs : clk, rst_n
//            scan_code, new_code
//   Outputs: mode_sel
//            veh_NS_level, veh_EW_level, veh_NS_pulse, veh_EW_pulse
//            reset_pulse
//            ns_up, ns_down, ew_left, ew_right
//            ns_ws_fwd, ns_ws_bwd, ew_ad_fwd, ew_ad_bwd
//            ped_NS_req, ped_EW_req
//======================================================================

module ps2_keyboard (
    input  wire       clk,
    input  wire       rst_n,

    input  wire [7:0] scan_code,
    input  wire       new_code,

    output reg  [1:0] mode_sel,

    output reg        veh_NS_level,
    output reg        veh_EW_level,
    output reg        veh_NS_pulse,
    output reg        veh_EW_pulse,

    output reg        reset_pulse,

    output reg        ns_up,
    output reg        ns_down,
    output reg        ew_left,
    output reg        ew_right,

    output reg        ns_ws_fwd,
    output reg        ns_ws_bwd,
    output reg        ew_ad_fwd,
    output reg        ew_ad_bwd,

    output reg        ped_NS_req,
    output reg        ped_EW_req
);

    //==================================================
    // 1) Set 2 扫描码常量
    //==================================================
    localparam [7:0]
        SCAN_A = 8'h1C,
        SCAN_S = 8'h1B,
        SCAN_D = 8'h23,
        SCAN_W = 8'h1D,

        SCAN_R = 8'h2D,
        SCAN_1 = 8'h16,
        SCAN_2 = 8'h1E,
        SCAN_3 = 8'h26,
        SCAN_4 = 8'h25,

        SCAN_T = 8'h2C,
        SCAN_G = 8'h34,
        SCAN_F = 8'h2B,
        SCAN_H = 8'h33,

        SCAN_UP    = 8'h75,
        SCAN_DOWN  = 8'h72,
        SCAN_LEFT  = 8'h6B,
        SCAN_RIGHT = 8'h74,

        SCAN_O = 8'h44,
        SCAN_P = 8'h4D;

    //==================================================
    // 2) 前缀状态
    //    break_flag : 收到 F0 后置 1，表示下一字节是释放码
    //    ext_flag   : 收到 E0 后置 1，表示下一字节是扩展键码
    //==================================================
    reg break_flag;
    reg ext_flag;

    wire make     = ~break_flag;
    wire extended =  ext_flag;

    //==================================================
    // 3) pulse 类按键按下锁存
    //    用于避免键盘 typematic 重复码导致脉冲连发
    //==================================================
    reg f_down, h_down, r_down, o_down, p_down;

    //==================================================
    // 4) 主状态更新
    //    - 每收到 new_code 处理一个字节
    //    - 先识别 E0 / F0 前缀，再处理实际键码
    //    - pulse 输出默认每周期清零，命中条件时仅置 1 个周期
    //==================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            break_flag   <= 1'b0;
            ext_flag     <= 1'b0;

            mode_sel     <= 2'b00;

            veh_NS_level <= 1'b0;
            veh_EW_level <= 1'b0;
            veh_NS_pulse <= 1'b0;
            veh_EW_pulse <= 1'b0;

            reset_pulse  <= 1'b0;

            ns_up        <= 1'b0;
            ns_down      <= 1'b0;
            ew_left      <= 1'b0;
            ew_right     <= 1'b0;

            ns_ws_fwd    <= 1'b0;
            ns_ws_bwd    <= 1'b0;
            ew_ad_fwd    <= 1'b0;
            ew_ad_bwd    <= 1'b0;

            ped_NS_req   <= 1'b0;
            ped_EW_req   <= 1'b0;

            f_down       <= 1'b0;
            h_down       <= 1'b0;
            r_down       <= 1'b0;
            o_down       <= 1'b0;
            p_down       <= 1'b0;

        end else begin
            veh_NS_pulse <= 1'b0;
            veh_EW_pulse <= 1'b0;
            reset_pulse  <= 1'b0;
            ped_NS_req   <= 1'b0;
            ped_EW_req   <= 1'b0;

            if (new_code) begin
                if (scan_code == 8'hE0) begin
                    ext_flag <= 1'b1;
                end else if (scan_code == 8'hF0) begin
                    break_flag <= 1'b1;
                end else begin
                    //==================================================
                    // 处理实际键码字节
                    //==================================================
                    if (extended) begin
                        // 扩展键：方向键输出为 level
                        case (scan_code)
                            SCAN_UP:    ns_up    <= make;
                            SCAN_DOWN:  ns_down  <= make;
                            SCAN_LEFT:  ew_left  <= make;
                            SCAN_RIGHT: ew_right <= make;
                            default: ;
                        endcase
                    end else begin
                        if (!make) begin
                            // 释放：level 清 0；pulse 键锁存清 0
                            case (scan_code)
                                SCAN_W: ns_ws_fwd <= 1'b0;
                                SCAN_S: ns_ws_bwd <= 1'b0;
                                SCAN_D: ew_ad_fwd <= 1'b0;
                                SCAN_A: ew_ad_bwd <= 1'b0;

                                SCAN_T: veh_NS_level <= 1'b0;
                                SCAN_G: veh_EW_level <= 1'b0;

                                SCAN_F: f_down <= 1'b0;
                                SCAN_H: h_down <= 1'b0;
                                SCAN_R: r_down <= 1'b0;
                                SCAN_O: o_down <= 1'b0;
                                SCAN_P: p_down <= 1'b0;
                                default: ;
                            endcase
                        end else begin
                            // 按下：更新模式/level；pulse 键首次按下输出 1-cycle
                            case (scan_code)
                                SCAN_1: mode_sel <= 2'b00;
                                SCAN_2: mode_sel <= 2'b01;
                                SCAN_3: mode_sel <= 2'b10;
                                SCAN_4: mode_sel <= 2'b11;

                                SCAN_W: ns_ws_fwd <= 1'b1;
                                SCAN_S: ns_ws_bwd <= 1'b1;
                                SCAN_D: ew_ad_fwd <= 1'b1;
                                SCAN_A: ew_ad_bwd <= 1'b1;

                                SCAN_T: veh_NS_level <= 1'b1;
                                SCAN_G: veh_EW_level <= 1'b1;

                                SCAN_F: begin
                                    if (!f_down) begin
                                        veh_NS_pulse <= 1'b1;
                                        f_down       <= 1'b1;
                                    end
                                end
                                SCAN_H: begin
                                    if (!h_down) begin
                                        veh_EW_pulse <= 1'b1;
                                        h_down       <= 1'b1;
                                    end
                                end

                                SCAN_R: begin
                                    if (!r_down) begin
                                        reset_pulse <= 1'b1;
                                        r_down      <= 1'b1;
                                    end
                                end
                                SCAN_O: begin
                                    if (!o_down) begin
                                        ped_NS_req <= 1'b1;
                                        o_down     <= 1'b1;
                                    end
                                end
                                SCAN_P: begin
                                    if (!p_down) begin
                                        ped_EW_req <= 1'b1;
                                        p_down     <= 1'b1;
                                    end
                                end

                                default: ;
                            endcase
                        end
                    end

                    // 处理完一个实际键码后清前缀状态
                    break_flag <= 1'b0;
                    ext_flag   <= 1'b0;
                end
            end
        end
    end

endmodule
