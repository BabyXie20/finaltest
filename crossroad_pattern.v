//======================================================================
// File Name : crossroad_pattern.v
// Function  : VGA 场景渲染模块（十字路口 + 人行道 + 斑马线 + 四方向红绿灯 + HUD 数字面板）
//             - 根据像素坐标 (x,y) 与各类状态输入，组合生成当前像素 RGB
//             - 支持四方向车辆绘制、红绿灯及光晕、道路/街区纹理、HUD 数字/字母显示
//             - 支持行人一次走完动画（ped_active/ped_sel/ped_phase）
//             - 支持冲击/爆炸幅度叠加（boom_amp）
//             - [MOD] 四个街区（四象限）背景改为静态；HUD 保持动态
//             - [MOD] 去除：墓碑、ghost、右下角装饰（原恐怖元素）
//             - [MOD] 左上/左下：祭坛 + 骷髅守卫放大，并增加细节
//             - [MOD] 右下街区：祭坛/守卫全部移除
//
// Inputs/Outputs:
//   Inputs :
//     x, y         : 当前像素坐标
//     video_on     : 可视区有效指示（0 表示消隐区，直接输出黑）
//     light_ns     : 南北向红绿灯状态（通常 {R,Y,G} 或与系统一致的 3-bit 编码）
//     light_ew     : 东西向红绿灯状态（同上）
//     ns_tens/ones : HUD 显示用的 NS 倒计时十位/个位（BCD 0..9）
//     ew_tens/ones : HUD 显示用的 EW 倒计时十位/个位（BCD 0..9）
//     mode_num     : HUD 显示用的模式编号（自定义编码）
//     car_n_y      : 北向车（竖直左车道）顶边 y 坐标
//     car_s_y      : 南向车（竖直右车道）顶边 y 坐标
//     car_w_x      : 西向车（水平上车道）左边 x 坐标
//     car_e_x      : 东向车（水平下车道）左边 x 坐标
//     viol_n/s/w/e : 四方向闯红灯标志（用于 HUD 报警显示/闪烁等）
//     anim         : 动画相位（用于动态底纹、霓虹呼吸、HUD 动态等）
//     boom_amp     : 冲击/爆炸强度（用于道路区域加亮与环形冲击波）
//     ped_active   : 行人动画使能（1 表示当前正在过街）
//     ped_sel      : 行人选择（2’b01 上方横向斑马线 L->R；2’b10 左侧纵向斑马线 T->B）
//     ped_phase    : 行人进度（0..255，按比例映射到行人行走路径）
//
//   Outputs:
//     r, g, b      : 当前像素颜色输出（8-bit RGB）
//
//======================================================================

module crossroad_pattern (
    input  wire [9:0] x,
    input  wire [9:0] y,
    input  wire       video_on,
    input  wire [2:0] light_ns,
    input  wire [2:0] light_ew,

    input  wire [3:0] ns_tens,
    input  wire [3:0] ns_ones,
    input  wire [3:0] ew_tens,
    input  wire [3:0] ew_ones,
    input  wire [3:0] mode_num,

    // 四辆车的位置
    input  wire [9:0] car_n_y,  // 北向车（竖直左车道）
    input  wire [9:0] car_s_y,  // 南向车（竖直右车道）
    input  wire [9:0] car_w_x,  // 西向车（水平上车道）
    input  wire [9:0] car_e_x,  // 东向车（水平下车道）

    // 闯红灯状态
    input  wire       viol_n,
    input  wire       viol_s,
    input  wire       viol_w,
    input  wire       viol_e,

    // 动画相位/冲击幅度（顶层 pixel_clk 域产生并同步）
    input  wire [7:0] anim,
    input  wire [7:0] boom_amp,

    // 行人一次走完动画（顶层产生）
    input  wire       ped_active,
    input  wire [1:0] ped_sel,
    input  wire [7:0] ped_phase,

    output reg  [7:0] r,
    output reg  [7:0] g,
    output reg  [7:0] b
);

    //========================
    // 几何常量
    //========================
    localparam [9:0] V_ROAD_X_L = 10'd260;
    localparam [9:0] V_ROAD_X_R = 10'd380;   // 右边界不含
    localparam [9:0] H_ROAD_Y_T = 10'd180;
    localparam [9:0] H_ROAD_Y_B = 10'd300;   // 下边界不含

    localparam [9:0] SIDEWALK_W = 10'd16;

    localparam [9:0] V_ROAD_CENTER_X = (V_ROAD_X_L + V_ROAD_X_R) >> 1;
    localparam [9:0] H_ROAD_CENTER_Y = (H_ROAD_Y_T + H_ROAD_Y_B) >> 1;

    localparam [9:0] V_LANE_EAST_CENTER_X  =
        V_ROAD_X_L + ((V_ROAD_X_R - V_ROAD_X_L) * 3) / 4;  // ≈350
    localparam [9:0] H_LANE_SOUTH_CENTER_Y =
        H_ROAD_Y_T + ((H_ROAD_Y_B - H_ROAD_Y_T) * 3) / 4;  // ≈270

    localparam [9:0] V_LANE_WEST_CENTER_X  =
        V_ROAD_X_L + ((V_ROAD_X_R - V_ROAD_X_L) * 1) / 4;  // ≈290
    localparam [9:0] H_LANE_NORTH_CENTER_Y =
        H_ROAD_Y_T + ((H_ROAD_Y_B - H_ROAD_Y_T) * 1) / 4;  // ≈210

    // 小车长宽
    localparam [9:0] CAR_NS_LEN = 10'd20;
    localparam [9:0] CAR_NS_WID = 10'd12;
    localparam [9:0] CAR_EW_LEN = 10'd20;
    localparam [9:0] CAR_EW_WID = 10'd12;

    localparam [9:0] X_MAX = 10'd640;
    localparam [9:0] Y_MAX = 10'd480;

    // 斑马线条纹参数
    localparam [9:0] STRIPE_PERIOD = 10'd12;
    localparam [9:0] STRIPE_WIDTH  = 10'd6;

    //========================
    // 四个“街区”(路口四象限)边界：用于把四块区域做成静态
    //========================
    localparam [9:0] V_OUT_L = V_ROAD_X_L - SIDEWALK_W;  // 244
    localparam [9:0] V_OUT_R = V_ROAD_X_R + SIDEWALK_W;  // 396
    localparam [9:0] H_OUT_T = H_ROAD_Y_T - SIDEWALK_W;  // 164
    localparam [9:0] H_OUT_B = H_ROAD_Y_B + SIDEWALK_W;  // 316

    //========================
    // 祭坛 + 骷髅守卫（静态精灵）参数
    //========================
    // 标准
    localparam [9:0] ALTAR_W = 10'd64;
    localparam [9:0] ALTAR_H = 10'd40;

    localparam [9:0] GUARD_W = 10'd20;
    localparam [9:0] GUARD_H = 10'd34;

    localparam [9:0] GUARD_GAP_X = 10'd4;
    localparam [9:0] GUARD_OFF_Y = 10'd4;
    localparam [9:0] GUARD_OFF_X = 10'd24;

    // 左上/左下：放大尺寸
    localparam [9:0] ALTAR_W_L = 10'd96;
    localparam [9:0] ALTAR_H_L = 10'd64;

    localparam [9:0] GUARD_W_L = 10'd30;
    localparam [9:0] GUARD_H_L = 10'd54;

    localparam [9:0] GUARD_GAP_X_L = 10'd6;
    localparam [9:0] GUARD_OFF_X_L = 10'd40;
    localparam [9:0] GUARD_OFF_Y_L = 10'd8;

    // 三个街区（左上/左下/右下）放置
    localparam [9:0] ALTAR_NW_X = 10'd70;
    localparam [9:0] ALTAR_NW_Y = 10'd44;

    localparam [9:0] ALTAR_SW_X = 10'd70;
    localparam [9:0] ALTAR_SW_Y = 10'd336;

    localparam [9:0] ALTAR_SE_X = 10'd420;
    localparam [9:0] ALTAR_SE_Y = 10'd330;

    // 守卫位置（每个祭坛左右各一个）
    localparam [9:0] G_NW_L_X = ALTAR_NW_X - GUARD_OFF_X_L;
    localparam [9:0] G_NW_R_X = ALTAR_NW_X + ALTAR_W_L + GUARD_GAP_X_L;
    localparam [9:0] G_NW_Y   = ALTAR_NW_Y + GUARD_OFF_Y_L;

    localparam [9:0] G_SW_L_X = ALTAR_SW_X - GUARD_OFF_X_L;
    localparam [9:0] G_SW_R_X = ALTAR_SW_X + ALTAR_W_L + GUARD_GAP_X_L;
    localparam [9:0] G_SW_Y   = ALTAR_SW_Y + GUARD_OFF_Y_L;

    localparam [9:0] G_SE_L_X = ALTAR_SE_X - GUARD_OFF_X;
    localparam [9:0] G_SE_R_X = ALTAR_SE_X + ALTAR_W + GUARD_GAP_X;
    localparam [9:0] G_SE_Y   = ALTAR_SE_Y + GUARD_OFF_Y;

    //========================
    // 石阶/石板路纹理参数
    //========================
    localparam [9:0] STONE_W_MASK = 10'd31;  // 32-1
    localparam [9:0] STONE_H_MASK = 10'd15;  // 16-1

    // 红绿灯尺寸
    localparam [9:0] TL_LONG   = 10'd30;
    localparam [9:0] TL_SHORT  = 10'd10;
    localparam [9:0] TL_SEG    = 10'd10;
    localparam [9:0] TL_MARGIN = 10'd4;

    // 北向灯（横向）
    localparam [9:0] TLN_X = 10'd320 - (TL_LONG >> 1);
    localparam [9:0] TLN_Y = H_ROAD_Y_T - SIDEWALK_W - TL_SHORT - TL_MARGIN;

    // 南向灯（横向）
    localparam [9:0] TLS_X = 10'd320 - (TL_LONG >> 1);
    localparam [9:0] TLS_Y = H_ROAD_Y_B + SIDEWALK_W + TL_MARGIN;

    // 西向灯（竖向）
    localparam [9:0] TLW_X = V_ROAD_X_L - SIDEWALK_W - TL_SHORT - TL_MARGIN;
    localparam [9:0] TLW_Y = 10'd240 - (TL_LONG >> 1);

    // 东向灯（竖向）
    localparam [9:0] TLE_X = V_ROAD_X_R + SIDEWALK_W + TL_MARGIN;
    localparam [9:0] TLE_Y = 10'd240 - (TL_LONG >> 1);

    //========================
    // HUD 参数
    //========================
    localparam [9:0] HUD_X_MIN = 10'd500;
    localparam [9:0] HUD_X_MAX = 10'd640;
    localparam [9:0] HUD_Y_MIN = 10'd0;
    localparam [9:0] HUD_Y_MAX = 10'd150;

    localparam [9:0] DIGIT_WIDTH   = 10'd14;
    localparam [9:0] DIGIT_HEIGHT  = 10'd22;
    localparam [9:0] DIGIT_GAP     = 10'd4;
    localparam [9:0] DIGIT_SPACING = 10'd16;
    localparam [9:0] SEG_WIDTH     = 10'd4;

    // 11-bit 中间运算
    localparam [10:0] TOTAL_DIGIT_AREA_WIDTH = (11'd5 * {1'b0,DIGIT_WIDTH}) + (11'd4 * {1'b0,DIGIT_GAP});
    localparam [10:0] HUD_CENTER_X           = ({1'b0,HUD_X_MIN} + {1'b0,HUD_X_MAX}) >> 1;
    localparam [10:0] START_X                = HUD_CENTER_X - (TOTAL_DIGIT_AREA_WIDTH >> 1);

    localparam [10:0] GLYPH0_X = START_X;
    localparam [10:0] GLYPH1_X = GLYPH0_X + {1'b0,DIGIT_WIDTH} + {1'b0,DIGIT_GAP};
    localparam [10:0] GLYPH2_X = GLYPH1_X + {1'b0,DIGIT_WIDTH} + {1'b0,DIGIT_GAP};
    localparam [10:0] GLYPH3_X = GLYPH2_X + {1'b0,DIGIT_WIDTH} + {1'b0,DIGIT_GAP};
    localparam [10:0] GLYPH4_X = GLYPH3_X + {1'b0,DIGIT_WIDTH} + {1'b0,DIGIT_GAP};

    localparam [9:0] NS_Y    = HUD_Y_MIN + 10'd8;
    localparam [9:0] EW_Y    = NS_Y   + DIGIT_HEIGHT + DIGIT_SPACING;
    localparam [9:0] MODE_Y  = EW_Y   + DIGIT_HEIGHT + DIGIT_SPACING;
    localparam [9:0] ALARM_Y = MODE_Y + DIGIT_HEIGHT + DIGIT_SPACING;

    localparam [10:0] NS_TENS_X   = GLYPH0_X;
    localparam [10:0] NS_ONES_X   = GLYPH1_X;
    localparam [10:0] NS_EW_SEP_X = GLYPH2_X;
    localparam [10:0] EW_TENS_X   = GLYPH3_X;
    localparam [10:0] EW_ONES_X   = GLYPH4_X;

    //========================
    // 行人 sprite 参数
    //========================
    localparam [9:0] PED_W = 10'd10;
    localparam [9:0] PED_H = 10'd12;

    //========================
    // 行人 sprite（简单小人 + 摆腿）
    //========================
    function [0:0] draw_ped;
        input [9:0] px, py;
        input [9:0] ox, oy;      // sprite 左上角
        input [7:0] t;           // 动画相位
        integer lx, ly;
        begin
            draw_ped = 1'b0;
            lx = px - ox;
            ly = py - oy;

            if (lx >= 0 && lx < PED_W && ly >= 0 && ly < PED_H) begin
                // head
                if ((ly <= 2 && lx >= 3 && lx <= 6) ||
                    (ly == 3 && (lx == 2 || lx == 7))) draw_ped = 1'b1;

                // body
                if (lx == 5 && ly >= 4 && ly <= 9) draw_ped = 1'b1;

                // arms
                if (ly == 6 && lx >= 2 && lx <= 8) draw_ped = 1'b1;

                // legs (toggle)
                if (!t[4]) begin
                    if ((ly == 10 && (lx == 4 || lx == 6)) ||
                        (ly == 11 && (lx == 3 || lx == 7))) draw_ped = 1'b1;
                end else begin
                    if ((ly == 10 && (lx == 3 || lx == 7)) ||
                        (ly == 11 && (lx == 2 || lx == 8))) draw_ped = 1'b1;
                end
            end
        end
    endfunction

    //========================
    // 小工具：饱和加减 / 三角波
    //========================
    function [7:0] add_sat8;
        input [7:0] a;
        input [7:0] b2;
        integer sum;
        begin
            sum = a + b2;
            if (sum > 255) add_sat8 = 8'hFF;
            else           add_sat8 = sum[7:0];
        end
    endfunction

    function [7:0] sub_sat8;
        input [7:0] a;
        input [7:0] b2;
        integer diff;
        begin
            diff = a - b2;
            if (diff < 0)  sub_sat8 = 8'h00;
            else           sub_sat8 = diff[7:0];
        end
    endfunction

    function [7:0] tri_wave8;
        input [7:0] t;
        begin
            if (t[7]) tri_wave8 = 8'hFF - t;
            else      tri_wave8 = t;
        end
    endfunction

    //========================
    // 七段段位置函数
    //========================
    function [0:0] segment_a;
        input [9:0] px, py, dx, dy;
        begin
            segment_a = (py >= dy && py < dy + SEG_WIDTH &&
                         px >= dx && px < dx + DIGIT_WIDTH);
        end
    endfunction

    function [0:0] segment_b;
        input [9:0] px, py, dx, dy;
        begin
            segment_b = (px >= dx + DIGIT_WIDTH - SEG_WIDTH && px < dx + DIGIT_WIDTH &&
                         py >= dy && py < dy + (DIGIT_HEIGHT/2) + 1);
        end
    endfunction

    function [0:0] segment_c;
        input [9:0] px, py, dx, dy;
        begin
            segment_c = (px >= dx + DIGIT_WIDTH - SEG_WIDTH && px < dx + DIGIT_WIDTH &&
                         py >= dy + (DIGIT_HEIGHT/2) - 1 && py < dy + DIGIT_HEIGHT);
        end
    endfunction

    function [0:0] segment_d;
        input [9:0] px, py, dx, dy;
        begin
            segment_d = (py >= dy + DIGIT_HEIGHT - SEG_WIDTH && py < dy + DIGIT_HEIGHT &&
                         px >= dx && px < dx + DIGIT_WIDTH);
        end
    endfunction

    function [0:0] segment_e;
        input [9:0] px, py, dx, dy;
        begin
            segment_e = (px >= dx && px < dx + SEG_WIDTH &&
                         py >= dy + (DIGIT_HEIGHT/2) - 1 && py < dy + DIGIT_HEIGHT);
        end
    endfunction

    function [0:0] segment_f;
        input [9:0] px, py, dx, dy;
        begin
            segment_f = (px >= dx && px < dx + SEG_WIDTH &&
                         py >= dy && py < dy + (DIGIT_HEIGHT/2) + 1);
        end
    endfunction

    function [0:0] segment_g;
        input [9:0] px, py, dx, dy;
        begin
            segment_g = (py >= dy + (DIGIT_HEIGHT/2) - (SEG_WIDTH/2) - 1 &&
                         py <  dy + (DIGIT_HEIGHT/2) + (SEG_WIDTH/2) + 1 &&
                         px >= dx && px < dx + DIGIT_WIDTH);
        end
    endfunction

    //========================
    // 七段编码
    //========================
    function [6:0] digit_pattern;
        input [3:0] digit;
        begin
            case(digit)
                4'd0: digit_pattern = 7'b1111110;
                4'd1: digit_pattern = 7'b0110000;
                4'd2: digit_pattern = 7'b1101101;
                4'd3: digit_pattern = 7'b1111001;
                4'd4: digit_pattern = 7'b0110011;
                4'd5: digit_pattern = 7'b1011011;
                4'd6: digit_pattern = 7'b1011111;
                4'd7: digit_pattern = 7'b1110000;
                4'd8: digit_pattern = 7'b1111111;
                4'd9: digit_pattern = 7'b1111011;
                default: digit_pattern = 7'b0000000;
            endcase
        end
    endfunction

    function [6:0] mode_pattern;
        input [3:0] mode;
        begin
            case(mode)
                4'd1: mode_pattern = 7'b0110000;
                4'd2: mode_pattern = 7'b1101101;
                4'd3: mode_pattern = 7'b1111001;
                4'd4: mode_pattern = 7'b0110011;
                default: mode_pattern = 7'b0000000;
            endcase
        end
    endfunction

    function [6:0] char_pattern;
        input [3:0] ch;
        begin
            case (ch)
                4'd0: char_pattern = 7'b1110110; // N/H 近似
                4'd1: char_pattern = 7'b1011011; // S
                4'd2: char_pattern = 7'b1001111; // E
                4'd3: char_pattern = 7'b0111011; // W
                4'd4: char_pattern = 7'b1110110; // M 近似
                4'd5: char_pattern = 7'b0111101; // D
                4'd6: char_pattern = 7'b1111110; // O
                default: char_pattern = 7'b0000000;
            endcase
        end
    endfunction

    //========================
    // 绘制数字/字母/冒号
    //========================
    function [0:0] draw_digit;
        input [9:0] px, py;
        input [9:0] dx, dy;
        input [3:0] digit;
        reg [6:0] pattern;
        reg seg_a_on, seg_b_on, seg_c_on, seg_d_on, seg_e_on, seg_f_on, seg_g_on;
        begin
            pattern   = digit_pattern(digit);
            seg_a_on  = pattern[6] && segment_a(px, py, dx, dy);
            seg_b_on  = pattern[5] && segment_b(px, py, dx, dy);
            seg_c_on  = pattern[4] && segment_c(px, py, dx, dy);
            seg_d_on  = pattern[3] && segment_d(px, py, dx, dy);
            seg_e_on  = pattern[2] && segment_e(px, py, dx, dy);
            seg_f_on  = pattern[1] && segment_f(px, py, dx, dy);
            seg_g_on  = pattern[0] && segment_g(px, py, dx, dy);
            draw_digit = seg_a_on || seg_b_on || seg_c_on ||
                         seg_d_on || seg_e_on || seg_f_on || seg_g_on;
        end
    endfunction

    function [0:0] draw_mode;
        input [9:0] px, py;
        input [9:0] dx, dy;
        input [3:0] mode;
        reg [6:0] pattern;
        reg seg_a_on, seg_b_on, seg_c_on, seg_d_on, seg_e_on, seg_f_on, seg_g_on;
        begin
            pattern   = mode_pattern(mode);
            seg_a_on  = pattern[6] && segment_a(px, py, dx, dy);
            seg_b_on  = pattern[5] && segment_b(px, py, dx, dy);
            seg_c_on  = pattern[4] && segment_c(px, py, dx, dy);
            seg_d_on  = pattern[3] && segment_d(px, py, dx, dy);
            seg_e_on  = pattern[2] && segment_e(px, py, dx, dy);
            seg_f_on  = pattern[1] && segment_f(px, py, dx, dy);
            seg_g_on  = pattern[0] && segment_g(px, py, dx, dy);
            draw_mode = seg_a_on || seg_b_on || seg_c_on ||
                        seg_d_on || seg_e_on || seg_f_on || seg_g_on;
        end
    endfunction

    function [0:0] draw_char;
        input [9:0] px, py;
        input [9:0] dx, dy;
        input [3:0] ch;
        reg [6:0] pattern;
        reg seg_a_on, seg_b_on, seg_c_on, seg_d_on, seg_e_on, seg_f_on, seg_g_on;
        begin
            pattern   = char_pattern(ch);
            seg_a_on  = pattern[6] && segment_a(px, py, dx, dy);
            seg_b_on  = pattern[5] && segment_b(px, py, dx, dy);
            seg_c_on  = pattern[4] && segment_c(px, py, dx, dy);
            seg_d_on  = pattern[3] && segment_d(px, py, dx, dy);
            seg_e_on  = pattern[2] && segment_e(px, py, dx, dy);
            seg_f_on  = pattern[1] && segment_f(px, py, dx, dy);
            seg_g_on  = pattern[0] && segment_g(px, py, dx, dy);
            draw_char = seg_a_on || seg_b_on || seg_c_on ||
                        seg_d_on || seg_e_on || seg_f_on || seg_g_on;
        end
    endfunction

    function [0:0] draw_colon;
        input [9:0] px, py;
        input [9:0] dx, dy;
        begin
            if (px >= dx + DIGIT_WIDTH/2 - 2 && px < dx + DIGIT_WIDTH/2 + 2 &&
               ((py >= dy + DIGIT_HEIGHT/3 - 2      && py < dy + DIGIT_HEIGHT/3 + 2) ||
                (py >= dy + (2*DIGIT_HEIGHT)/3 - 2 && py < dy + (2*DIGIT_HEIGHT)/3 + 2))) begin
                draw_colon = 1'b1;
            end else begin
                draw_colon = 1'b0;
            end
        end
    endfunction

    //========================
    // 点阵解释 "M","O","D"
    //========================
    function [0:0] draw_char_mod;
        input [9:0] px, py;
        input [9:0] dx, dy;
        input [3:0] ch;
        integer cx, cy;
        integer x0, y0;
        reg [2:0] row;
        reg [2:0] col;
        reg [4:0] row_bits;
        localparam FONT_W = 5;
        localparam FONT_H = 7;
        localparam SCALE  = 2;
        localparam PIX_W  = FONT_W*SCALE;   // 10
        localparam PIX_H  = FONT_H*SCALE;   // 14
        begin
            draw_char_mod = 1'b0;
            cx = 0; cy = 0;
            x0 = 0; y0 = 0;
            row = 3'd0;
            col = 3'd0;
            row_bits = 5'b00000;

            x0 = dx + (DIGIT_WIDTH  - PIX_W)/2;
            y0 = dy + (DIGIT_HEIGHT - PIX_H)/2;

            cx = px - x0;
            cy = py - y0;

            if (cx >= 0 && cx < PIX_W && cy >= 0 && cy < PIX_H) begin
                col = (cx >> 1);
                row = (cy >> 1);

                case (ch)
                    4'd4: begin // 'M'
                        case (row)
                            3'd0: row_bits = 5'b11111;
                            3'd1: row_bits = 5'b10001;
                            3'd2: row_bits = 5'b11011;
                            3'd3: row_bits = 5'b10101;
                            3'd4: row_bits = 5'b10001;
                            3'd5: row_bits = 5'b10001;
                            3'd6: row_bits = 5'b10001;
                            default: row_bits = 5'b00000;
                        endcase
                    end
                    4'd6: begin // 'O'
                        case (row)
                            3'd0: row_bits = 5'b01110;
                            3'd1: row_bits = 5'b10001;
                            3'd2: row_bits = 5'b10001;
                            3'd3: row_bits = 5'b10001;
                            3'd4: row_bits = 5'b10001;
                            3'd5: row_bits = 5'b10001;
                            3'd6: row_bits = 5'b01110;
                            default: row_bits = 5'b00000;
                        endcase
                    end
                    4'd5: begin // 'D'
                        case (row)
                            3'd0: row_bits = 5'b11110;
                            3'd1: row_bits = 5'b10001;
                            3'd2: row_bits = 5'b10001;
                            3'd3: row_bits = 5'b10001;
                            3'd4: row_bits = 5'b10001;
                            3'd5: row_bits = 5'b10001;
                            3'd6: row_bits = 5'b11110;
                            default: row_bits = 5'b00000;
                        endcase
                    end
                    default: row_bits = 5'b00000;
                endcase

                if (row_bits[4-col])
                    draw_char_mod = 1'b1;
            end
        end
    endfunction

    //============================================================
    // 祭坛（标准 64x40）：返回 2-bit
    // 00 无，01 石台，10 符文发光，11 顶部火/灵球
    //============================================================
    function [1:0] altar_code;
        input [9:0] px, py;
        input [9:0] ox, oy;
        integer sx, sy;
        integer dx, dy;
        reg stone;
        reg rune;
        reg fire;
        begin
            altar_code = 2'b00;
            stone = 1'b0;
            rune  = 1'b0;
            fire  = 1'b0;

            sx = $signed({1'b0,px}) - $signed({1'b0,ox});
            sy = $signed({1'b0,py}) - $signed({1'b0,oy});

            if (sx >= 0 && sx < ALTAR_W && sy >= 0 && sy < ALTAR_H) begin
                // 三层台阶
                if (sy >= 30 && sy <= 39 && sx >= 6  && sx <= 57) stone = 1'b1;
                if (sy >= 24 && sy <= 29 && sx >= 10 && sx <= 53) stone = 1'b1;
                if (sy >= 20 && sy <= 23 && sx >= 14 && sx <= 49) stone = 1'b1;

                // 台面 + 立柱 + 中央柱
                if (sy >= 14 && sy <= 17 && sx >= 12 && sx <= 51) stone = 1'b1;
                if (sy >= 12 && sy <= 27 && ((sx >= 14 && sx <= 18) || (sx >= 45 && sx <= 49))) stone = 1'b1;
                if (sy >= 4  && sy <= 27 && sx >= 30 && sx <= 33) stone = 1'b1;

                // 符文
                if (sy >= 6 && sy <= 25 && sx >= 29 && sx <= 34) begin
                    if (((sx ^ sy) & 3) == 0) rune = 1'b1;
                end
                if (sy >= 26 && sy <= 28 && sx >= 18 && sx <= 45) begin
                    if (((sx + sy) & 7) == 0) rune = 1'b1;
                end

                // 顶部灵球
                dx = (sx >= 31) ? (sx - 31) : (31 - sx);
                dy = (sy >=  2) ? (sy -  2) : ( 2 - sy);
                if ((dx + (dy<<1)) < 6) fire = 1'b1;

                if (fire)      altar_code = 2'b11;
                else if (rune) altar_code = 2'b10;
                else if (stone)altar_code = 2'b01;
                else           altar_code = 2'b00;
            end
        end
    endfunction

    //============================================================
    // 祭坛（放大 96x64）：更细节，返回 2-bit
    // 00 无，01 石材主体，10 符文/能量刻痕，11 火盆/火焰
    //============================================================
    function [1:0] altar_code_big;
        input [9:0] px, py;
        input [9:0] ox, oy;
        integer sx, sy;
        integer dx, dy;
        reg stone;
        reg rune;
        reg fire;
        reg bowl;
        begin
            altar_code_big = 2'b00;
            stone = 1'b0;
            rune  = 1'b0;
            fire  = 1'b0;
            bowl  = 1'b0;

            sx = $signed({1'b0,px}) - $signed({1'b0,ox});
            sy = $signed({1'b0,py}) - $signed({1'b0,oy});

            if (sx >= 0 && sx < ALTAR_W_L && sy >= 0 && sy < ALTAR_H_L) begin
                // ===== 基座三层台阶（下宽上窄，带斜切边）=====
                // bottom: y 52..63, x 10..85
                if (sy >= 52 && sy <= 63 && sx >= 10 && sx <= 85) stone = 1'b1;
                // mid:    y 42..51, x 16..79
                if (sy >= 42 && sy <= 51 && sx >= 16 && sx <= 79) stone = 1'b1;
                // top:    y 34..41, x 22..73
                if (sy >= 34 && sy <= 41 && sx >= 22 && sx <= 73) stone = 1'b1;

                // beveled edges（更立体）
                if ((sy == 52 || sy == 42 || sy == 34) && (sx >= 12 && sx <= 83)) rune = 1'b1; // 边缘亮线当作刻痕/能量
                if ((sy == 63 || sy == 51 || sy == 41) && (sx >= 12 && sx <= 83)) begin
                    // 下缘阴影用“暗槽”表达：标记为 stone，但在着色时做减亮
                    stone = 1'b1;
                end

                // ===== 台面（中间平台）=====
                if (sy >= 26 && sy <= 33 && sx >= 20 && sx <= 75) stone = 1'b1;

                // ===== 两侧立柱（更厚）=====
                if (sy >= 18 && sy <= 49 && ((sx >= 24 && sx <= 31) || (sx >= 64 && sx <= 71))) stone = 1'b1;

                // ===== 中央主柱（更粗）=====
                if (sy >= 14 && sy <= 49 && sx >= 45 && sx <= 50) stone = 1'b1;

                // ===== 顶部火盆（碗）=====
                if (sy >= 6 && sy <= 14 && sx >= 38 && sx <= 57) begin
                    // 碗沿
                    if (sy == 6 || sy == 14 || sx == 38 || sx == 57) bowl = 1'b1;
                    // 内腔
                    if (sy >= 8 && sy <= 12 && sx >= 40 && sx <= 55) bowl = 1'b1;
                end

                // ===== 符文：台面上的圆环 + 立柱符文 =====
                // 圆环中心(48,30)，用曼哈顿圈近似
                dx = (sx >= 48) ? (sx - 48) : (48 - sx);
                dy = (sy >= 30) ? (sy - 30) : (30 - sy);
                if (sy >= 26 && sy <= 33) begin
                    if ((dx + (dy<<1)) == 18 || (dx + (dy<<1)) == 16) rune = 1'b1;
                    // 中央符号
                    if ((sx >= 46 && sx <= 50) && (sy >= 28 && sy <= 32)) rune = 1'b1;
                end

                // 立柱符文（静态）
                if (sy >= 20 && sy <= 46 && sx >= 44 && sx <= 51) begin
                    if (((sx ^ (sy<<1)) & 5) == 0) rune = 1'b1;
                end
                // 台阶刻痕（模拟石材裂缝/雕纹）
                if (sy >= 44 && sy <= 62 && sx >= 14 && sx <= 82) begin
                    if (((sx + sy) & 31) == 7) rune = 1'b1;
                    if (((sx ^ sy) & 63) == 0) rune = 1'b1;
                end

                // ===== 火焰（静态火舌形状，分叉）=====
                // flame center ~ (48,8)
                if (sy >= 2 && sy <= 12 && sx >= 41 && sx <= 54) begin
                    dx = (sx >= 48) ? (sx - 48) : (48 - sx);
                    // 主火舌：越往上越窄
                    if ((dx + (sy<<1)) < 18) fire = 1'b1;
                    // 左右分叉（更像火舌）
                    if (sy >= 4 && sy <= 10) begin
                        if ((((sx-41) & 3) == 0) && ((sy & 1) == 0)) fire = 1'b1;
                    end
                end

                // 统一输出优先级
                if (fire)              altar_code_big = 2'b11;
                else if (rune)         altar_code_big = 2'b10;
                else if (bowl || stone)altar_code_big = 2'b01;
                else                   altar_code_big = 2'b00;
            end
        end
    endfunction

    //============================================================
    // 骷髅守卫（标准 20x34）：返回 2-bit
    // 00 无，01 骨面/骨架，10 盔甲/孔洞，11 红眼
    //============================================================
    function [1:0] skull_guard_code;
        input [9:0] px, py;
        input [9:0] ox, oy;
        integer sx, sy;
        integer dx, dy;
        reg bone;
        reg dark;
        reg eye;
        begin
            skull_guard_code = 2'b00;
            bone = 1'b0;
            dark = 1'b0;
            eye  = 1'b0;

            sx = $signed({1'b0,px}) - $signed({1'b0,ox});
            sy = $signed({1'b0,py}) - $signed({1'b0,oy});

            if (sx >= 0 && sx < GUARD_W && sy >= 0 && sy < GUARD_H) begin
                // head
                dx = (sx >= 10) ? (sx - 10) : (10 - sx);
                dy = (sy >=  7) ? (sy -  7) : ( 7 - sy);
                if ((dx + (dy<<1)) < 12 && sy <= 13) bone = 1'b1;

                // eyes
                if (sy == 7) begin
                    if ((sx == 7) || (sx == 13)) eye = 1'b1;
                end
                if (sy >= 6 && sy <= 8) begin
                    if ((sx >= 6 && sx <= 8) || (sx >= 12 && sx <= 14)) dark = 1'b1;
                end

                // nose
                if (sy >= 9 && sy <= 11 && sx >= 9 && sx <= 11) dark = 1'b1;

                // jaw + teeth gap
                if (sy >= 12 && sy <= 15 && sx >= 6 && sx <= 14) begin
                    bone = 1'b1;
                    if (((sx - 6) & 2) == 0) dark = 1'b1;
                end

                // torso armor + ribs
                if (sy >= 16 && sy <= 33 && sx >= 5 && sx <= 15) begin
                    dark = 1'b1;
                    if ((sy == 18 || sy == 22 || sy == 26 || sy == 30) && (sx >= 7 && sx <= 13))
                        bone = 1'b1;
                    if (sx == 10 && sy >= 18 && sy <= 32)
                        bone = 1'b1;
                end

                // helmet horns
                if ((sy == 2 || sy == 3) && (sx == 4 || sx == 16)) bone = 1'b1;

                if (eye)       skull_guard_code = 2'b11;
                else if (dark) skull_guard_code = 2'b10;
                else if (bone) skull_guard_code = 2'b01;
                else           skull_guard_code = 2'b00;
            end
        end
    endfunction

    //============================================================
    // 骷髅守卫（放大 30x54）：更逼真，返回 2-bit
    // 00 无，01 骨面/高光，10 盔甲/阴影，11 红眼
    //============================================================
    function [1:0] skull_guard_code_big;
        input [9:0] px, py;
        input [9:0] ox, oy;
        integer sx, sy;
        integer dx, dy;
        reg bone;
        reg dark;
        reg eye;
        reg weapon;
        begin
            skull_guard_code_big = 2'b00;
            bone = 1'b0;
            dark = 1'b0;
            eye  = 1'b0;
            weapon = 1'b0;

            sx = $signed({1'b0,px}) - $signed({1'b0,ox});
            sy = $signed({1'b0,py}) - $signed({1'b0,oy});

            if (sx >= 0 && sx < GUARD_W_L && sy >= 0 && sy < GUARD_H_L) begin
                // ===== 头骨：中心(15,12)，更大椭圆 =====
                dx = (sx >= 15) ? (sx - 15) : (15 - sx);
                dy = (sy >= 12) ? (sy - 12) : (12 - sy);
                if ((dx + (dy<<1)) < 22 && sy <= 22) bone = 1'b1;

                // 头盔/角（更硬朗）
                if (sy <= 6) begin
                    if ((sx <= 4 && sy >= 2) || (sx >= 25 && sy >= 2)) dark = 1'b1;
                    if (sy == 2 && (sx == 5 || sx == 24)) bone = 1'b1;
                end
                if (sy >= 4 && sy <= 10) begin
                    if ((sx == 4 && sy <= 8) || (sx == 25 && sy <= 8)) dark = 1'b1;
                end

                // 眼窝（孔洞）+ 红眼点
                if (sy >= 10 && sy <= 14) begin
                    if ((sx >= 9 && sx <= 12) || (sx >= 18 && sx <= 21)) dark = 1'b1;
                    if (sy == 12) begin
                        if (sx == 10 || sx == 20) eye = 1'b1;
                    end
                end

                // 鼻孔
                if (sy >= 15 && sy <= 18 && sx >= 14 && sx <= 16) dark = 1'b1;

                // 下颚与牙
                if (sy >= 18 && sy <= 24 && sx >= 8 && sx <= 22) begin
                    bone = 1'b1;
                    if (sy >= 21) begin
                        if (((sx - 8) & 2) == 0) dark = 1'b1; // 牙缝
                    end
                end

                // ===== 肩甲/躯干（更像“守卫”）=====
                if (sy >= 24 && sy <= 52) begin
                    // 肩甲轮廓
                    if (sy <= 30) begin
                        if (sx >= 5 && sx <= 25) dark = 1'b1;
                        if (sx == 5 || sx == 25) bone = 1'b1;
                    end
                    // 胸甲主体
                    if (sy >= 28 && sy <= 46 && sx >= 8 && sx <= 22) dark = 1'b1;

                    // 肋骨高光（更逼真：多条弧线）
                    if ((sy == 32 || sy == 36 || sy == 40 || sy == 44) && (sx >= 10 && sx <= 20))
                        bone = 1'b1;

                    // 脊柱
                    if (sx == 15 && sy >= 30 && sy <= 48)
                        bone = 1'b1;

                    // 腰带/护甲边
                    if (sy == 46 && sx >= 8 && sx <= 22)
                        bone = 1'b1;
                end

                // ===== 武器（长矛/权杖）=====
                // 左侧竖杆
                if (sx >= 2 && sx <= 4 && sy >= 20 && sy <= 53) weapon = 1'b1;
                // 枪头
                if (sy >= 14 && sy <= 20) begin
                    if (sx == 3) weapon = 1'b1;
                    if (sy == 14 && (sx >= 2 && sx <= 4)) weapon = 1'b1;
                    if (sy == 15 && (sx == 1 || sx == 5)) weapon = 1'b1;
                end
                if (weapon) dark = 1'b1;

                // 输出优先级
                if (eye)       skull_guard_code_big = 2'b11;
                else if (dark) skull_guard_code_big = 2'b10;
                else if (bone) skull_guard_code_big = 2'b01;
                else           skull_guard_code_big = 2'b00;
            end
        end
    endfunction

    //========================
    // 组合像素着色
    //========================
    integer dx_i, dy_i, d_i, ring_pos, diff_i;
    reg [7:0] glow_phase;
    reg [7:0] glow_lvl;
    reg [7:0] glow2;

    // 行人坐标/动画（组合）
    reg [9:0] ped_x;
    reg [9:0] ped_y;
    reg [7:0] ped_t;
    integer   ped_span;

    // 石阶道路临时变量
    reg        in_v, in_h;
    reg        mortar;
    reg [2:0]  noise;
    reg [9:0]  x_off, y_off;

    // 雾化/阴森背景临时变量
    reg [2:0]  fog_n;
    reg [5:0]  fog_amt;
    reg        mist_band;
    reg        corner_boost;

    // HUD / 区域判断
    reg        in_hud;

    // 四街区静态选择：anim_bg=0 表示完全静态
    reg [7:0] anim_bg;
    reg blk_nw, blk_ne, blk_sw, blk_se;
    reg in_block;

    // 祭坛/守卫 code
    reg in_nw, in_sw, in_se;
    reg [1:0] a0, a1, a2;
    reg [1:0] g0l, g0r, g1l, g1r, g2l, g2r;
    reg [1:0] ac;

    always @* begin
        // --------- 默认值：避免 latch ---------
        glow_phase = 8'd0;
        glow_lvl   = 8'd0;
        glow2      = 8'd0;

        dx_i     = 0;
        dy_i     = 0;
        d_i      = 0;
        ring_pos = 0;
        diff_i   = 0;

        ped_x    = 10'd0;
        ped_y    = 10'd0;
        ped_t    = 8'd0;
        ped_span = 0;

        in_v     = 1'b0;
        in_h     = 1'b0;
        mortar   = 1'b0;
        noise    = 3'd0;
        x_off    = 10'd0;
        y_off    = 10'd0;

        fog_n        = 3'd0;
        fog_amt      = 6'd0;
        mist_band    = 1'b0;
        corner_boost = 1'b0;

        in_hud  = 1'b0;

        anim_bg  = 8'd0;
        blk_nw   = 1'b0; blk_ne = 1'b0; blk_sw = 1'b0; blk_se = 1'b0;
        in_block = 1'b0;

        in_nw = 1'b0; in_sw = 1'b0; in_se = 1'b0;
        a0 = 2'b00; a1 = 2'b00; a2 = 2'b00;
        g0l = 2'b00; g0r = 2'b00; g1l = 2'b00; g1r = 2'b00; g2l = 2'b00; g2r = 2'b00;
        ac = 2'b00;

        if (!video_on) begin
            r = 8'd0; g = 8'd0; b = 8'd0;
        end else begin
            //================================================
            // 0) HUD & 四街区静态判断
            //================================================
            in_hud = (x >= HUD_X_MIN && x < HUD_X_MAX && y >= HUD_Y_MIN && y < HUD_Y_MAX);

            blk_nw = (x <  V_OUT_L) && (y <  H_OUT_T);
            blk_ne = (x >= V_OUT_R) && (y <  H_OUT_T);
            blk_sw = (x <  V_OUT_L) && (y >= H_OUT_B);
            blk_se = (x >= V_OUT_R) && (y >= H_OUT_B);
            in_block = blk_nw || blk_ne || blk_sw || blk_se;

            // 街区背景静态（HUD 不静态）
            if (in_block && !in_hud) anim_bg = 8'd0;
            else                     anim_bg = anim;

            //================================================
            // 0) 背景底色
            //================================================
            r = 8'd14;  g = 8'd20;  b = 8'd34;

            // ---- (A) 四街区静态底纹----
            if (in_block && !in_hud) begin
                // 静态街区：紫灰石广场
                r = 8'd26; g = 8'd22; b = 8'd34;

                // 静态大块石砖：32px 网格
                if ( ((x & 10'd31) == 10'd0) || ((y & 10'd31) == 10'd0) ) begin
                    r = add_sat8(r, 8'd10);
                    g = add_sat8(g, 8'd10);
                    b = add_sat8(b, 8'd14);
                end

                // 静态细裂纹：只依赖坐标
                if ((((x ^ y) & 10'd63) == 10'd0) || (((x + y) & 10'd127) == 10'd0)) begin
                    r = sub_sat8(r, 8'd6);
                    g = sub_sat8(g, 8'd6);
                    b = sub_sat8(b, 8'd6);
                end

                // 静态符文点（微亮）
                if ((((x + (y<<1)) & 10'd63) == 10'd7) && ((x & 10'd7) == 10'd3)) begin
                    r = add_sat8(r, 8'd16);
                    b = add_sat8(b, 8'd22);
                end
            end
            else begin
                // ---- (B) 非街区：动态底纹 ----
                if (y[8]) begin
                    r = add_sat8(r, 8'd10);
                    g = add_sat8(g, 8'd12);
                    b = add_sat8(b, 8'd18);
                end
                if (y[7]) begin
                    r = add_sat8(r, 8'd6);
                    g = add_sat8(g, 8'd8);
                    b = add_sat8(b, 8'd12);
                end
                if (y[6]) begin
                    r = add_sat8(r, 8'd3);
                    g = add_sat8(g, 8'd4);
                    b = add_sat8(b, 8'd6);
                end

                // 细网格：16px
                if ( (((x + {2'b0,anim_bg}) & 10'd15) == 10'd0) ||
                     (((y + {2'b0,anim_bg}) & 10'd15) == 10'd0) ) begin
                    r = add_sat8(r, 8'd16);
                    g = add_sat8(g, 8'd22);
                    b = add_sat8(b, 8'd40);
                end

                // 粗网格：64px
                if ( (((x + {2'b0,anim_bg}) & 10'd63) == 10'd0) ||
                     (((y + {2'b0,anim_bg}) & 10'd63) == 10'd0) ) begin
                    r = add_sat8(r, 8'd18);
                    g = add_sat8(g, 8'd24);
                    b = add_sat8(b, 8'd48);
                end

                // 斜向能量线
                if ( ((((x ^ y) + {2'b0,anim_bg}) & 10'd31) == 10'd0) ) begin
                    g = add_sat8(g, 8'd8);
                    b = add_sat8(b, 8'd18);
                end

                //================================================
                // 雾化叠加（动态区）
                //================================================
                fog_n = (x[7:5] ^ y[6:4] ^ anim_bg[7:5]);     // 0..7
                fog_amt = {fog_n, 3'b000};                    // 0..56

                mist_band = (((y + {2'b0,anim_bg} + {2'b0,anim_bg}) & 10'd63) < 10'd4);
                corner_boost = (x[9:8] == 2'b00) || (x[9:8] == 2'b11) ||
                               (y[8:7] == 2'b00) || (y[8:7] == 2'b11);

                r = sub_sat8(r, (fog_amt >> 4));
                g = add_sat8(g, (fog_amt >> 5));
                b = add_sat8(b, (fog_amt >> 3));

                if (mist_band) begin
                    r = sub_sat8(r, 8'd2);
                    g = add_sat8(g, 8'd6);
                    b = add_sat8(b, 8'd14);
                end

                if (corner_boost) begin
                    r = sub_sat8(r, 8'd2);
                    b = add_sat8(b, 8'd10);
                end
            end

            glow_phase = tri_wave8(anim_bg);
            glow_lvl   = (glow_phase >> 4);                            // 0..15
            glow2      = add_sat8((glow_phase >> 2), (boom_amp >> 3));  // 0..63 + boom

            //================================================
            // 1) 人行道
            //================================================
            if (x >= V_ROAD_X_L - SIDEWALK_W && x < V_ROAD_X_L && y < Y_MAX) begin
                r = 8'd70; g = 8'd80; b = 8'd95;
            end
            if (x >= V_ROAD_X_R && x < V_ROAD_X_R + SIDEWALK_W && y < Y_MAX) begin
                r = 8'd70; g = 8'd80; b = 8'd95;
            end
            if (y >= H_ROAD_Y_T - SIDEWALK_W && y < H_ROAD_Y_T && x < X_MAX) begin
                r = 8'd70; g = 8'd80; b = 8'd95;
            end
            if (y >= H_ROAD_Y_B && y < H_ROAD_Y_B + SIDEWALK_W && x < X_MAX) begin
                r = 8'd70; g = 8'd80; b = 8'd95;
            end

            //================================================
            // 2) 机动车道（石阶/石板）
            //================================================
            in_v = (x >= V_ROAD_X_L && x < V_ROAD_X_R);
            in_h = (y >= H_ROAD_Y_T && y < H_ROAD_Y_B);

            if (in_v || in_h) begin
                r = 8'd46; g = 8'd48; b = 8'd52;

                noise = (x[6:4] + y[6:4] + anim[7:5]); // 道路仍允许轻微动感
                if (noise[0]) begin
                    r = add_sat8(r, 8'd4);
                    g = add_sat8(g, 8'd4);
                    b = add_sat8(b, 8'd4);
                end
                if (noise[1]) begin
                    r = sub_sat8(r, 8'd3);
                    g = sub_sat8(g, 8'd3);
                    b = sub_sat8(b, 8'd3);
                end

                mortar = 1'b0;

                if (in_v) begin
                    if ( (y & STONE_H_MASK) == 0 ) mortar = 1'b1;
                    x_off = x + (y[4] ? 10'd16 : 10'd0);
                    if ( (x_off & STONE_W_MASK) == 0 ) mortar = 1'b1;

                    if ( (y & STONE_H_MASK) == 1 ) begin
                        r = add_sat8(r, 8'd10);
                        g = add_sat8(g, 8'd10);
                        b = add_sat8(b, 8'd10);
                    end
                end

                if (in_h) begin
                    if ( (x & STONE_W_MASK) == 0 ) mortar = 1'b1;
                    y_off = y + (x[5] ? 10'd8 : 10'd0);
                    if ( (y_off & STONE_H_MASK) == 0 ) mortar = 1'b1;

                    if ( (x & STONE_W_MASK) == 1 ) begin
                        r = add_sat8(r, 8'd10);
                        g = add_sat8(g, 8'd10);
                        b = add_sat8(b, 8'd10);
                    end
                end

                if (mortar) begin
                    r = 8'd24; g = 8'd24; b = 8'd26;
                end
            end

            // 3) 斑马线
            if (x >= V_ROAD_X_L && x < V_ROAD_X_R &&
                y >= H_ROAD_Y_T - SIDEWALK_W && y < H_ROAD_Y_T) begin
                if ( ((x - V_ROAD_X_L) % STRIPE_PERIOD) < STRIPE_WIDTH ) begin
                    r = 8'd235; g = 8'd240; b = 8'd255;
                end
            end
            if (x >= V_ROAD_X_L && x < V_ROAD_X_R &&
                y >= H_ROAD_Y_B && y < H_ROAD_Y_B + SIDEWALK_W) begin
                if ( ((x - V_ROAD_X_L) % STRIPE_PERIOD) < STRIPE_WIDTH ) begin
                    r = 8'd235; g = 8'd240; b = 8'd255;
                end
            end
            if (x >= V_ROAD_X_L - SIDEWALK_W && x < V_ROAD_X_L &&
                y >= H_ROAD_Y_T && y < H_ROAD_Y_B) begin
                if ( ((y - H_ROAD_Y_T) % STRIPE_PERIOD) < STRIPE_WIDTH ) begin
                    r = 8'd235; g = 8'd240; b = 8'd255;
                end
            end
            if (x >= V_ROAD_X_R && x < V_ROAD_X_R + SIDEWALK_W &&
                y >= H_ROAD_Y_T && y < H_ROAD_Y_B) begin
                if ( ((y - H_ROAD_Y_T) % STRIPE_PERIOD) < STRIPE_WIDTH ) begin
                    r = 8'd235; g = 8'd240; b = 8'd255;
                end
            end

            // 4) 中心线：霓虹青（呼吸）
            if (x >= 10'd318 && x < 10'd322 && y < Y_MAX) begin
                r = 8'd20;
                g = add_sat8(8'd180, glow_lvl);
                b = add_sat8(8'd200, glow_lvl);
            end
            if (y >= 10'd238 && y < 10'd242 && x < X_MAX) begin
                r = 8'd20;
                g = add_sat8(8'd180, glow_lvl);
                b = add_sat8(8'd200, glow_lvl);
            end

            //================================================
            // 5) 小车
            //================================================
            if (x >= V_LANE_WEST_CENTER_X - (CAR_NS_WID >> 1) &&
                x <  V_LANE_WEST_CENTER_X + (CAR_NS_WID >> 1) &&
                y >= car_n_y && y < car_n_y + CAR_NS_LEN) begin
                r = 8'd40; g = 8'd90; b = 8'd220;
                if (y < car_n_y + (CAR_NS_LEN/3)) begin
                    r = 8'd170; g = 8'd230; b = 8'd255;
                end
                if ( (y >= car_n_y + (CAR_NS_LEN*2/3)) &&
                     ( (x <  V_LANE_WEST_CENTER_X - (CAR_NS_WID>>1) + 2) ||
                       (x >= V_LANE_WEST_CENTER_X + (CAR_NS_WID>>1) - 2) ) ) begin
                    r = 8'd20; g = 8'd20; b = 8'd20;
                end
            end

            if (x >= V_LANE_EAST_CENTER_X - (CAR_NS_WID >> 1) &&
                x <  V_LANE_EAST_CENTER_X + (CAR_NS_WID >> 1) &&
                y >= car_s_y && y < car_s_y + CAR_NS_LEN) begin
                r = 8'd200; g = 8'd60; b = 8'd220;
                if (y > car_s_y + (CAR_NS_LEN*2/3)) begin
                    r = 8'd255; g = 8'd210; b = 8'd255;
                end
                if ( (y <= car_s_y + (CAR_NS_LEN/3)) &&
                     ( (x <  V_LANE_EAST_CENTER_X - (CAR_NS_WID>>1) + 2) ||
                       (x >= V_LANE_EAST_CENTER_X + (CAR_NS_WID>>1) - 2) ) ) begin
                    r = 8'd20; g = 8'd20; b = 8'd20;
                end
            end

            if (y >= H_LANE_NORTH_CENTER_Y - (CAR_EW_WID >> 1) &&
                y <  H_LANE_NORTH_CENTER_Y + (CAR_EW_WID >> 1) &&
                x >= car_w_x && x < car_w_x + CAR_EW_LEN) begin
                r = 8'd240; g = 8'd120; b = 8'd30;
                if (x < car_w_x + (CAR_EW_LEN/3)) begin
                    r = 8'd255; g = 8'd230; b = 8'd180;
                end
                if ( (x >= car_w_x + (CAR_EW_LEN*2/3)) &&
                     ( (y <  H_LANE_NORTH_CENTER_Y - (CAR_EW_WID>>1) + 2) ||
                       (y >= H_LANE_NORTH_CENTER_Y + (CAR_EW_WID>>1) - 2) ) ) begin
                    r = 8'd20; g = 8'd20; b = 8'd20;
                end
            end

            if (y >= H_LANE_SOUTH_CENTER_Y - (CAR_EW_WID >> 1) &&
                y <  H_LANE_SOUTH_CENTER_Y + (CAR_EW_WID >> 1) &&
                x >= car_e_x && x < car_e_x + CAR_EW_LEN) begin
                r = 8'd60; g = 8'd220; b = 8'd160;
                if (x > car_e_x + (CAR_EW_LEN*2/3)) begin
                    r = 8'd200; g = 8'd255; b = 8'd230;
                end
                if ( (x <= car_e_x + (CAR_EW_LEN/3)) &&
                     ( (y <  H_LANE_SOUTH_CENTER_Y - (CAR_EW_WID>>1) + 2) ||
                       (y >= H_LANE_SOUTH_CENTER_Y + (CAR_EW_WID>>1) - 2) ) ) begin
                    r = 8'd20; g = 8'd20; b = 8'd20;
                end
            end

            //================================================
            // 6) 红绿灯 halo + 灯体
            //================================================
            // halo（北/南/西/东）——保持原逻辑
            if (light_ns[2] &&
                x >= TLN_X - 3 && x < TLN_X + TL_SEG + 3 &&
                y >= TLN_Y - 3 && y < TLN_Y + TL_SHORT + 3) begin
                r = add_sat8(r, 8'd30 + (glow2 >> 1));
            end
            if (light_ns[1] &&
                x >= TLN_X + TL_SEG - 3 && x < TLN_X + (TL_SEG*2) + 3 &&
                y >= TLN_Y - 3 && y < TLN_Y + TL_SHORT + 3) begin
                r = add_sat8(r, 8'd18 + (glow2 >> 2));
                g = add_sat8(g, 8'd18 + (glow2 >> 2));
            end
            if (light_ns[0] &&
                x >= TLN_X + (TL_SEG*2) - 3 && x < TLN_X + (TL_SEG*3) + 3 &&
                y >= TLN_Y - 3 && y < TLN_Y + TL_SHORT + 3) begin
                g = add_sat8(g, 8'd30 + (glow2 >> 1));
            end

            if (light_ns[2] &&
                x >= TLS_X - 3 && x < TLS_X + TL_SEG + 3 &&
                y >= TLS_Y - 3 && y < TLS_Y + TL_SHORT + 3) begin
                r = add_sat8(r, 8'd30 + (glow2 >> 1));
            end
            if (light_ns[1] &&
                x >= TLS_X + TL_SEG - 3 && x < TLS_X + (TL_SEG*2) + 3 &&
                y >= TLS_Y - 3 && y < TLS_Y + TL_SHORT + 3) begin
                r = add_sat8(r, 8'd18 + (glow2 >> 2));
                g = add_sat8(g, 8'd18 + (glow2 >> 2));
            end
            if (light_ns[0] &&
                x >= TLS_X + (TL_SEG*2) - 3 && x < TLS_X + (TL_SEG*3) + 3 &&
                y >= TLS_Y - 3 && y < TLS_Y + TL_SHORT + 3) begin
                g = add_sat8(g, 8'd30 + (glow2 >> 1));
            end

            if (light_ew[2] &&
                x >= TLW_X - 3 && x < TLW_X + TL_SHORT + 3 &&
                y >= TLW_Y - 3 && y < TLW_Y + TL_SEG + 3) begin
                r = add_sat8(r, 8'd30 + (glow2 >> 1));
            end
            if (light_ew[1] &&
                x >= TLW_X - 3 && x < TLW_X + TL_SHORT + 3 &&
                y >= TLW_Y + TL_SEG - 3 && y < TLW_Y + (TL_SEG*2) + 3) begin
                r = add_sat8(r, 8'd18 + (glow2 >> 2));
                g = add_sat8(g, 8'd18 + (glow2 >> 2));
            end
            if (light_ew[0] &&
                x >= TLW_X - 3 && x < TLW_X + TL_SHORT + 3 &&
                y >= TLW_Y + (TL_SEG*2) - 3 && y < TLW_Y + (TL_SEG*3) + 3) begin
                g = add_sat8(g, 8'd30 + (glow2 >> 1));
            end

            if (light_ew[2] &&
                x >= TLE_X - 3 && x < TLE_X + TL_SHORT + 3 &&
                y >= TLE_Y - 3 && y < TLE_Y + TL_SEG + 3) begin
                r = add_sat8(r, 8'd30 + (glow2 >> 1));
            end
            if (light_ew[1] &&
                x >= TLE_X - 3 && x < TLE_X + TL_SHORT + 3 &&
                y >= TLE_Y + TL_SEG - 3 && y < TLE_Y + (TL_SEG*2) + 3) begin
                r = add_sat8(r, 8'd18 + (glow2 >> 2));
                g = add_sat8(g, 8'd18 + (glow2 >> 2));
            end
            if (light_ew[0] &&
                x >= TLE_X - 3 && x < TLE_X + TL_SHORT + 3 &&
                y >= TLE_Y + (TL_SEG*2) - 3 && y < TLE_Y + (TL_SEG*3) + 3) begin
                g = add_sat8(g, 8'd30 + (glow2 >> 1));
            end

            // 灯体壳
            if (x >= TLN_X && x < TLN_X + TL_LONG && y >= TLN_Y && y < TLN_Y + TL_SHORT) begin
                r = 8'd28; g = 8'd28; b = 8'd30;
            end
            if (x >= TLS_X && x < TLS_X + TL_LONG && y >= TLS_Y && y < TLS_Y + TL_SHORT) begin
                r = 8'd28; g = 8'd28; b = 8'd30;
            end
            if (x >= TLW_X && x < TLW_X + TL_SHORT && y >= TLW_Y && y < TLW_Y + TL_LONG) begin
                r = 8'd28; g = 8'd28; b = 8'd30;
            end
            if (x >= TLE_X && x < TLE_X + TL_SHORT && y >= TLE_Y && y < TLE_Y + TL_LONG) begin
                r = 8'd28; g = 8'd28; b = 8'd30;
            end

            // 灯芯
            if (light_ns[2] &&
                x >= TLN_X + 1 && x < TLN_X + TL_SEG - 1 &&
                y >= TLN_Y + 1 && y < TLN_Y + TL_SHORT - 1) begin
                r = 8'd255; g = 8'd20;  b = 8'd20;
            end
            if (light_ns[1] &&
                x >= TLN_X + TL_SEG + 1 && x < TLN_X + (TL_SEG*2) - 1 &&
                y >= TLN_Y + 1 && y < TLN_Y + TL_SHORT - 1) begin
                r = 8'd255; g = 8'd230; b = 8'd40;
            end
            if (light_ns[0] &&
                x >= TLN_X + (TL_SEG*2) + 1 && x < TLN_X + (TL_SEG*3) - 1 &&
                y >= TLN_Y + 1 && y < TLN_Y + TL_SHORT - 1) begin
                r = 8'd30;  g = 8'd255; b = 8'd80;
            end

            if (light_ns[2] &&
                x >= TLS_X + 1 && x < TLS_X + TL_SEG - 1 &&
                y >= TLS_Y + 1 && y < TLS_Y + TL_SHORT - 1) begin
                r = 8'd255; g = 8'd20;  b = 8'd20;
            end
            if (light_ns[1] &&
                x >= TLS_X + TL_SEG + 1 && x < TLS_X + (TL_SEG*2) - 1 &&
                y >= TLS_Y + 1 && y < TLS_Y + TL_SHORT - 1) begin
                r = 8'd255; g = 8'd230; b = 8'd40;
            end
            if (light_ns[0] &&
                x >= TLS_X + (TL_SEG*2) + 1 && x < TLS_X + (TL_SEG*3) - 1 &&
                y >= TLS_Y + 1 && y < TLS_Y + TL_SHORT - 1) begin
                r = 8'd30;  g = 8'd255; b = 8'd80;
            end

            if (light_ew[2] &&
                x >= TLW_X + 1 && x < TLW_X + TL_SHORT - 1 &&
                y >= TLW_Y + 1 && y < TLW_Y + TL_SEG - 1) begin
                r = 8'd255; g = 8'd20;  b = 8'd20;
            end
            if (light_ew[1] &&
                x >= TLW_X + 1 && x < TLW_X + TL_SHORT - 1 &&
                y >= TLW_Y + TL_SEG + 1 && y < TLW_Y + (TL_SEG*2) - 1) begin
                r = 8'd255; g = 8'd230; b = 8'd40;
            end
            if (light_ew[0] &&
                x >= TLW_X + 1 && x < TLW_X + TL_SHORT - 1 &&
                y >= TLW_Y + (TL_SEG*2) + 1 && y < TLW_Y + (TL_SEG*3) - 1) begin
                r = 8'd30;  g = 8'd255; b = 8'd80;
            end

            if (light_ew[2] &&
                x >= TLE_X + 1 && x < TLE_X + TL_SHORT - 1 &&
                y >= TLE_Y + 1 && y < TLE_Y + TL_SEG - 1) begin
                r = 8'd255; g = 8'd20;  b = 8'd20;
            end
            if (light_ew[1] &&
                x >= TLE_X + 1 && x < TLE_X + TL_SHORT - 1 &&
                y >= TLE_Y + TL_SEG + 1 && y < TLE_Y + (TL_SEG*2) - 1) begin
                r = 8'd255; g = 8'd230; b = 8'd40;
            end
            if (light_ew[0] &&
                x >= TLE_X + 1 && x < TLE_X + TL_SHORT - 1 &&
                y >= TLE_Y + (TL_SEG*2) + 1 && y < TLE_Y + (TL_SEG*3) - 1) begin
                r = 8'd30;  g = 8'd255; b = 8'd80;
            end

            //================================================
            // 7) HUD（动态）
            //================================================
            if (in_hud) begin
                r = 8'd16; g = 8'd18; b = 8'd22;

                if (x == HUD_X_MIN || x == HUD_X_MAX-1 || y == HUD_Y_MIN || y == HUD_Y_MAX-1) begin
                    r = 8'd60; g = 8'd70; b = 8'd90;
                    if ( (((x + {2'b0,anim}) & 10'd15) == 10'd0) ||
                         (((y + {2'b0,anim}) & 10'd15) == 10'd0) ) begin
                        r = add_sat8(r, 8'd40);
                        g = add_sat8(g, 8'd40);
                        b = add_sat8(b, 8'd60);
                    end
                end

                if ( (((y + {2'b0,anim}) % 10'd6) == 10'd0) ) begin
                    r = add_sat8(r, 8'd10);
                    g = add_sat8(g, 8'd14);
                    b = add_sat8(b, 8'd22);
                end

                if ( ((y + {2'b0,anim}) & 10'd31) == 10'd0 ) begin
                    r = add_sat8(r, 8'd18);
                    g = add_sat8(g, 8'd25);
                    b = add_sat8(b, 8'd35);
                end

                if (draw_char (x, y, NS_TENS_X[9:0], NS_Y, 4'd0)) begin r=8'd220; g=8'd235; b=8'd255; end
                if (draw_char (x, y, NS_ONES_X[9:0], NS_Y, 4'd1)) begin r=8'd220; g=8'd235; b=8'd255; end
                if (draw_colon(x, y, NS_EW_SEP_X[9:0], NS_Y))       begin r=8'd220; g=8'd235; b=8'd255; end
                if (draw_digit(x, y, EW_TENS_X[9:0], NS_Y, ns_tens)) begin r=8'd220; g=8'd235; b=8'd255; end
                if (draw_digit(x, y, EW_ONES_X[9:0], NS_Y, ns_ones)) begin r=8'd220; g=8'd235; b=8'd255; end

                if (draw_char (x, y, NS_TENS_X[9:0], EW_Y, 4'd2)) begin r=8'd220; g=8'd235; b=8'd255; end
                if (draw_char (x, y, NS_ONES_X[9:0], EW_Y, 4'd3)) begin r=8'd220; g=8'd235; b=8'd255; end
                if (draw_colon(x, y, NS_EW_SEP_X[9:0], EW_Y))       begin r=8'd220; g=8'd235; b=8'd255; end
                if (draw_digit(x, y, EW_TENS_X[9:0], EW_Y, ew_tens)) begin r=8'd220; g=8'd235; b=8'd255; end
                if (draw_digit(x, y, EW_ONES_X[9:0], EW_Y, ew_ones)) begin r=8'd220; g=8'd235; b=8'd255; end

                if (draw_char_mod(x, y, NS_TENS_X[9:0], MODE_Y, 4'd4)) begin r=8'd220; g=8'd235; b=8'd255; end
                if (draw_char_mod(x, y, NS_ONES_X[9:0], MODE_Y, 4'd6)) begin r=8'd220; g=8'd235; b=8'd255; end
                if (draw_char_mod(x, y, NS_EW_SEP_X[9:0], MODE_Y, 4'd5)) begin r=8'd220; g=8'd235; b=8'd255; end
                if (draw_colon   (x, y, EW_TENS_X[9:0], MODE_Y)) begin r=8'd220; g=8'd235; b=8'd255; end
                if (draw_mode    (x, y, EW_ONES_X[9:0], MODE_Y, mode_num)) begin r=8'd255; g=8'd120; b=8'd140; end

                if (draw_char(x, y, NS_TENS_X[9:0], ALARM_Y, 4'd0)) begin
                    if (viol_n) begin r=8'd255; g=8'd40;  b=8'd40; end
                    else        begin r=8'd170; g=8'd180; b=8'd200; end
                end
                if (draw_char(x, y, NS_ONES_X[9:0], ALARM_Y, 4'd1)) begin
                    if (viol_s) begin r=8'd255; g=8'd40;  b=8'd40; end
                    else        begin r=8'd170; g=8'd180; b=8'd200; end
                end
                if (draw_char(x, y, EW_TENS_X[9:0], ALARM_Y, 4'd3)) begin
                    if (viol_w) begin r=8'd255; g=8'd40;  b=8'd40; end
                    else        begin r=8'd170; g=8'd180; b=8'd200; end
                end
                if (draw_char(x, y, EW_ONES_X[9:0], ALARM_Y, 4'd2)) begin
                    if (viol_e) begin r=8'd255; g=8'd40;  b=8'd40; end
                    else        begin r=8'd170; g=8'd180; b=8'd200; end
                end
            end

            //========================
            // 7.5) 行人
            //========================
            if (ped_active) begin
                ped_t = anim + ped_phase;

                ped_x    = 10'd0;
                ped_y    = 10'd0;
                ped_span = 0;

                if (ped_sel == 2'b01) begin
                    ped_span = (V_ROAD_X_R - V_ROAD_X_L - PED_W);
                    ped_x    = V_ROAD_X_L + ((ped_span * ped_phase) >> 8);
                    ped_y    = (H_ROAD_Y_T - SIDEWALK_W) + ((SIDEWALK_W - PED_H) >> 1);
                end else if (ped_sel == 2'b10) begin
                    ped_span = (H_ROAD_Y_B - H_ROAD_Y_T - PED_H);
                    ped_x    = (V_ROAD_X_L - SIDEWALK_W) + ((SIDEWALK_W - PED_W) >> 1);
                    ped_y    = H_ROAD_Y_T + ((ped_span * ped_phase) >> 8);
                end

                if (draw_ped(x, y, ped_x, ped_y, ped_t)) begin
                    r = 8'd255; g = 8'd150; b = 8'd40;
                    if (x == ped_x || x == (ped_x + PED_W - 1) ||
                        y == ped_y || y == (ped_y + PED_H - 1)) begin
                        r = 8'd10; g = 8'd18; b = 8'd28;
                    end
                end
            end

            //================================================
            // 7.6) 两个街区加入：祭坛 + 骷髅守卫
            //   - 左上/左下：使用放大更逼真的版本（含守卫）
            //   - 右下：祭坛/守卫全部不要
            //================================================
            if (!in_hud) begin
                in_nw = blk_nw;
                in_sw = blk_sw;
         
                in_se = 1'b0;

                if (in_nw) begin
                    a0  = altar_code_big(x, y, ALTAR_NW_X, ALTAR_NW_Y);
                    g0l = skull_guard_code_big(x, y, G_NW_L_X, G_NW_Y);
                    g0r = skull_guard_code_big(x, y, G_NW_R_X, G_NW_Y);
                end else begin
                    a0  = 2'b00; g0l = 2'b00; g0r = 2'b00;
                end

                if (in_sw) begin
                    a1  = altar_code_big(x, y, ALTAR_SW_X, ALTAR_SW_Y);
                    g1l = skull_guard_code_big(x, y, G_SW_L_X, G_SW_Y);
                    g1r = skull_guard_code_big(x, y, G_SW_R_X, G_SW_Y);
                end else begin
                    a1  = 2'b00; g1l = 2'b00; g1r = 2'b00;
                end

           
                a2  = 2'b00;
                g2l = 2'b00;
                g2r = 2'b00;

                // 祭坛先画（低优先级）——只看 a0/a1
                if (a0 != 2'b00 || a1 != 2'b00) begin
                    ac = (a0 != 2'b00) ? a0 : a1;

                    if (ac == 2'b01) begin
                        // 石材主体：紫灰石 + 静态纹理
                        r = 8'd78; g = 8'd70; b = 8'd92;
                        if (((x + y) & 10'd7) == 10'd0) begin
                            r = add_sat8(r, 8'd10);
                            b = add_sat8(b, 8'd12);
                        end
                        if (((x ^ y) & 10'd31) == 10'd0) begin
                            r = sub_sat8(r, 8'd8);
                            g = sub_sat8(g, 8'd8);
                            b = sub_sat8(b, 8'd8);
                        end
                    end else if (ac == 2'b10) begin
                        // 符文：紫粉霓虹
                        r = 8'd255; g = 8'd70; b = 8'd220;
                        if (((x + y) & 10'd3) == 10'd0) begin
                            r = 8'd230; g = 8'd40; b = 8'd255;
                        end
                    end else begin
                        // 火焰：橙白火芯
                        r = 8'd255; g = 8'd150; b = 8'd60;
                        if (((x + y) & 10'd1) == 10'd0) begin
                            r = 8'd255; g = 8'd220; b = 8'd160;
                        end
                    end
                end

                // 守卫后画（更高优先级）——只包含左上/左下
                if (g0l == 2'b11 || g0r == 2'b11 || g1l == 2'b11 || g1r == 2'b11) begin
                    r = 8'd255; g = 8'd35;  b = 8'd30;      // 红眼
                end
                else if (g0l == 2'b10 || g0r == 2'b10 || g1l == 2'b10 || g1r == 2'b10) begin
                    r = 8'd18;  g = 8'd16;  b = 8'd24;      // 盔甲/阴影
                    if (((x + y) & 10'd7) == 10'd0) begin
                        b = add_sat8(b, 8'd12);             // 冷光反射
                    end
                end
                else if (g0l == 2'b01 || g0r == 2'b01 || g1l == 2'b01 || g1r == 2'b01) begin
                    r = 8'd230; g = 8'd238; b = 8'd242;     // 骨面高光
                    if (((x ^ y) & 10'd15) == 10'd0) begin
                        r = 8'd200; g = 8'd210; b = 8'd218; // 阴影颗粒
                    end
                end
            end


            //================================================
            // 8) boom 冲击
            //================================================
            if (boom_amp != 8'd0) begin
                if ((x >= V_ROAD_X_L && x < V_ROAD_X_R) ||
                    (y >= H_ROAD_Y_T && y < H_ROAD_Y_B)) begin
                    r = add_sat8(r, boom_amp);
                    g = add_sat8(g, (boom_amp >> 2));
                    b = sub_sat8(b, (boom_amp >> 3));
                end

                dx_i = (x >= 10'd320) ? (x - 10'd320) : (10'd320 - x);
                dy_i = (y >= 10'd240) ? (y - 10'd240) : (10'd240 - y);
                d_i  = dx_i + dy_i;

                ring_pos = (anim << 1);
                diff_i   = (d_i >= ring_pos) ? (d_i - ring_pos) : (ring_pos - d_i);

                if (!in_hud && !(in_block)) begin
                    if (diff_i < 4) begin
                        r = add_sat8(r, (boom_amp >> 1));
                        g = add_sat8(g, (boom_amp >> 3));
                        b = add_sat8(b, (boom_amp >> 2));
                    end
                end
            end
        end
    end

endmodule
