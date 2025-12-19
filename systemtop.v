//======================================================================
// File Name : system_top.v
// Function  : 顶层模块（DE1/类似平台板级 Top）
//             - 基础层：640x480 VGA 十字路口交通灯场景（crossroad_pattern）
//             - 画中画PIP：摄像头(MIPI) -> SDRAM缓存 -> RAW2RGB -> 缩放到 200x150
//               并叠加到右下角（RB corner）
//             - 关键点：pip_cam_200x150 模块输出 25MHz VGA 像素时钟（VGA_CLK_25），
//               本顶层不再额外输入 25MHz 时钟
//
// Inputs    : CLOCK2_50/CLOCK3_50/CLOCK4_50/CLOCK_50 - 板载 50MHz 时钟输入
//             KEY[3:0]    - 按键输入（KEY[0]复位等）
//             SW[9:0]     - 拨码开关输入
//             PS2_CLK/DAT - PS2 键盘接口
//             GPIO_1[9:0] - GPIO（连接 HC-SR04 超声波、LED等）
//             SDRAM pins  - 外部 SDRAM 引脚
//             MIPI pins   - 摄像头/MIPI Bridge 引脚
//
// Outputs   : LEDR[9:0]   - 状态/调试指示灯
//             HEX0~HEX5   - 数码管显示
//             VGA_*       - VGA 输出信号（RGB/HS/VS/BLANK/SYNC/CLK）
//             SDRAM pins  - SDRAM 控制引脚输出
//             MIPI pins   - 摄像头桥接控制引脚输出
//======================================================================

module systemtop(
    //================================================
    // clocks
    //================================================
    input         CLOCK2_50,
    input         CLOCK3_50,
    input         CLOCK4_50,
    input         CLOCK_50,

    //================================================
    // keys/switch
    //================================================
    input  [3:0]  KEY,
    input  [9:0]  SW,

    //================================================
    // LEDs/HEX
    //================================================
    output [9:0]  LEDR,
    output [6:0]  HEX0,
    output [6:0]  HEX1,
    output [6:0]  HEX2,
    output [6:0]  HEX3,
    output [6:0]  HEX4,
    output [6:0]  HEX5,

    //================================================
    // VGA out
    //================================================
    output [7:0]  VGA_R,
    output [7:0]  VGA_G,
    output [7:0]  VGA_B,
    output        VGA_HS,
    output        VGA_VS,
    output        VGA_BLANK_N,
    output        VGA_SYNC_N,
    output        VGA_CLK,

    //================================================
    // PS2
    //================================================
    input         PS2_CLK,
    input         PS2_DAT,

    //================================================
    // GPIO（HC-SR04 等）
    //================================================
    inout  [9:0]  GPIO_1,

    //================================================
    // SDRAM pins（供 pip_cam_200x150 / Sdram_Control）
    //================================================
    output [12:0] DRAM_ADDR,
    output [1:0]  DRAM_BA,
    output        DRAM_CAS_N,
    output        DRAM_CKE,
    output        DRAM_CLK,
    output        DRAM_CS_N,
    inout  [15:0] DRAM_DQ,
    output        DRAM_LDQM,
    output        DRAM_RAS_N,
    output        DRAM_UDQM,
    output        DRAM_WE_N,

    //================================================
    // Camera / MIPI bridge pins（供 pip_cam_200x150）
    //================================================
    inout         CAMERA_I2C_SCL,
    inout         CAMERA_I2C_SDA,
    output        CAMERA_PWDN_n,
    output        MIPI_CS_n,
    inout         MIPI_I2C_SCL,
    inout         MIPI_I2C_SDA,
    output        MIPI_MCLK,
    input         MIPI_PIXEL_CLK,
    input  [9:0]  MIPI_PIXEL_D,
    input         MIPI_PIXEL_HS,
    input         MIPI_PIXEL_VS,
    output        MIPI_REFCLK,
    output        MIPI_RESET_n
);

    //================================================
    // 常量定义：模式/相位/车辆尺寸与边界/道路边界
    //================================================
    localparam [1:0] MODE_FIXED = 2'b00;  // 固定配时模式
    localparam [1:0] MODE_ACT   = 2'b01;  // 感应/自适应模式
    localparam [1:0] MODE_NIGHT = 2'b10;  // 夜间模式
    localparam [1:0] MODE_LOCK  = 2'b11;  // 锁定模式

    // 交通灯状态机相位编号
    localparam [3:0]
        S_NS_GREEN  = 4'd0,
        S_NS_YELLOW = 4'd1,
        S_ALL_RED_1 = 4'd2,
        S_EW_GREEN  = 4'd3,
        S_EW_YELLOW = 4'd4,
        S_ALL_RED_2 = 4'd5;

    // 车辆尺寸、坐标范围、步进
    localparam [9:0] CAR_NS_LEN     = 10'd20;
    localparam [9:0] CAR_EW_LEN     = 10'd20;
    localparam [9:0] CAR_NS_Y_START = 10'd0;
    localparam [9:0] CAR_NS_Y_MAX   = 10'd480 - CAR_NS_LEN;
    localparam [9:0] CAR_EW_X_START = 10'd0;
    localparam [9:0] CAR_EW_X_MAX   = 10'd640 - CAR_EW_LEN;
    localparam [9:0] CAR_STEP_PIX   = 10'd8;

    // 道路矩形范围（用于违规检测等）
    localparam [9:0] V_ROAD_X_L = 10'd260;
    localparam [9:0] V_ROAD_X_R = 10'd380;
    localparam [9:0] H_ROAD_Y_T = 10'd180;
    localparam [9:0] H_ROAD_Y_B = 10'd300;

    //================================================
    // 复位（低有效）
    //================================================
    wire rst_button_n = KEY[0];  // 板上按键复位输入（低有效/或按你的硬件定义）
    wire rst_n;                  // 系统复位（经软复位管理输出）

    //================================================
    // PS2 键盘：原始扫描码与新码脉冲
    //================================================
    wire [7:0] kb_scan;
    wire       kb_new;

    // 模式选择（来自键盘解码）
    wire [1:0] mode_sel;

    // 车辆请求（键盘电平/脉冲）
    wire       veh_NS_level_kbd, veh_EW_level_kbd;
    wire       veh_NS_pulse_kbd, veh_EW_pulse_kbd;

    // 键盘触发的软复位脉冲
    wire       reset_pulse_kbd;

    // 键盘控制的车辆移动方向
    wire       ns_up, ns_down, ew_left, ew_right;
    wire       ns_ws_fwd, ns_ws_bwd, ew_ad_fwd, ew_ad_bwd;

    // 行人请求（键盘）
    wire       ped_NS_req_kbd, ped_EW_req_kbd;

    //================================================
    // 交通灯核心输出
    //================================================
    wire [2:0] light_ns, light_ew;   // 交通灯输出 {R,Y,G}
    wire [3:0] phase_id;            // 当前相位编号
    wire [7:0] time_left;           // 当前相位剩余时间

    //================================================
    // 车辆请求（合并后）
    //================================================
    wire veh_NS, veh_EW;

    //================================================
    // 1 秒 tick（50MHz 域）
    //================================================
    wire tick_1s;

    //================================================
    // HC-SR04 超声波（两路：NS / EW）
    //================================================
    wire hcsr_ns_echo, hcsr_ew_echo;
    wire hcsr_ns_trig, hcsr_ew_trig;

    wire ped_NS_req_hc, ped_EW_req_hc;
    wire done_ns, done_ew;
    wire start_ns, start_ew;

    // 行人请求合并（键盘 OR 超声波）
    wire ped_NS_req = ped_NS_req_kbd | ped_NS_req_hc;
    wire ped_EW_req = ped_EW_req_kbd | ped_EW_req_hc;

    //================================================
    // BCD 数码管显示数据
    //================================================
    wire [3:0] ns_ones, ns_tens, ew_ones, ew_tens;
    wire [3:0] mode_num, mode_ones;

    //================================================
    // VGA 时序相关（pixel_clk 域）
    //================================================
    wire        pixel_clk;     // 25MHz 像素时钟（来自 pip_cam_200x150 输出）
    wire [9:0]  h_count;       // 水平计数 0..799
    wire [9:0]  v_count;       // 垂直计数 0..524
    wire        video_on;      // 可视区有效

    // 动画相位/每帧 tick/爆炸强度
    wire [7:0]  anim;
    wire        frame_tick;
    wire [7:0]  boom_amp;

    //================================================
    // 车辆/违规（CLOCK_50 域）
    //================================================
    wire        tick_car;
    wire [9:0]  car_n_y, car_s_y, car_w_x, car_e_x;
    wire        viol_n, viol_s, viol_w, viol_e;

    //================================================
    // 行人（pixel_clk 域）
    //================================================
    wire        ped_active;
    wire [1:0]  ped_sel;
    wire [7:0]  ped_phase;

    //================================================
    // 十字路口基础图层 RGB（base layer）
    //================================================
    wire [7:0] base_r, base_g, base_b;

    //================================================
    // PIP 输出（摄像头缩放后）
    //================================================
    wire        pip_de;
    wire [7:0]  pip_r, pip_g, pip_b;

    // 摄像头/自动对焦状态
    wire        I2C_RELEASE;
    wire        READY_AF;

    // pip 输出的时钟/同步
    wire pip_vga_clk_25;
    wire pip_vga_sync_n_unused;
    wire pip_vga_blank_n_unused;

    //================================================
    // 1) 复位管理：按键复位 + 键盘软复位脉冲
    //================================================
    reset_soft_n #(
        .SOFT_RST_CYC(50_000 * 2)
    ) u_reset (
        .clk            (CLOCK_50),
        .rst_button_n    (rst_button_n),
        .soft_trig_pulse (reset_pulse_kbd),
        .rst_n           (rst_n)
    );

    //================================================
    // 2) PS2 接收器：输出扫描码与新码脉冲
    //================================================
    ps2 u_ps2 (
        .clock_key (PS2_CLK),
        .data_key  (PS2_DAT),
        .clock_fpga(CLOCK_50),
        .reset     (rst_n),
        .led       (),
        .data_out  (kb_scan),
        .new_code  (kb_new)
    );

    //================================================
    // 3) 键盘解码：模式选择、车辆输入、行人请求、软复位等
    //================================================
    ps2_keyboard u_kbd (
        .clk          (CLOCK_50),
        .rst_n        (rst_n),
        .scan_code    (kb_scan),
        .new_code     (kb_new),

        .mode_sel     (mode_sel),

        .veh_NS_level (veh_NS_level_kbd),
        .veh_EW_level (veh_EW_level_kbd),
        .veh_NS_pulse (veh_NS_pulse_kbd),
        .veh_EW_pulse (veh_EW_pulse_kbd),

        .reset_pulse  (reset_pulse_kbd),

        .ns_up        (ns_up),
        .ns_down      (ns_down),
        .ew_left      (ew_left),
        .ew_right     (ew_right),

        .ns_ws_fwd    (ns_ws_fwd),
        .ns_ws_bwd    (ns_ws_bwd),
        .ew_ad_fwd    (ew_ad_fwd),
        .ew_ad_bwd    (ew_ad_bwd),

        .ped_NS_req   (ped_NS_req_kbd),
        .ped_EW_req   (ped_EW_req_kbd)
    );

    //================================================
    // 4) 车辆请求锁存/合并：支持电平与脉冲、以及特定相位下的策略
    //================================================
    veh_req_latch #(
        .MODE_ACT  (MODE_ACT),
        .S_NS_GREEN(S_NS_GREEN),
        .S_EW_GREEN(S_EW_GREEN)
    ) u_veh (
        .clk        (CLOCK_50),
        .rst_n      (rst_n),
        .mode_sel   (mode_sel),
        .phase_id   (phase_id),
        .veh_NS_lvl (veh_NS_level_kbd),
        .veh_EW_lvl (veh_EW_level_kbd),
        .veh_NS_p   (veh_NS_pulse_kbd),
        .veh_EW_p   (veh_EW_pulse_kbd),
        .veh_NS     (veh_NS),
        .veh_EW     (veh_EW)
    );

    //================================================
    // 5) 1 秒 tick 产生器（CLOCK_50 域）
    //================================================
    clk_div_sec u_clk_div(
        .clk     (CLOCK_50),
        .rst_n   (rst_n),
        .tick_1s (tick_1s)
    );

    //================================================
    // 6) GPIO 映射：交通灯输出 + HC-SR04 IO
    //================================================
    gpio_io_pack u_gpio (
        .GPIO_1      (GPIO_1),

        .light_ns    (light_ns),
        .light_ew    (light_ew),

        .hcsr_ns_trig(hcsr_ns_trig),
        .hcsr_ew_trig(hcsr_ew_trig),
        .hcsr_ns_echo(hcsr_ns_echo),
        .hcsr_ew_echo(hcsr_ew_echo)
    );

    //================================================
    // 7) HC-SR04 两路测距调度 + 两通道行人请求检测
    //================================================
    hcsr04_2ch_scheduler #(
        .GUARD_MS(10)
    ) u_hc_sched (
        .clk      (CLOCK_50),
        .rst_n    (rst_n),
        .done_ns  (done_ns),
        .done_ew  (done_ew),
        .start_ns (start_ns),
        .start_ew (start_ew)
    );

    hcsr04_ped #(
        .THRESH_CM(20),
        .PULSE_MS (50)
    ) u_hc_ns (
        .clk        (CLOCK_50),
        .rst_n      (rst_n),
        .echo_in    (hcsr_ns_echo),
        .trig_out   (hcsr_ns_trig),
        .ped_req    (ped_NS_req_hc),
        .start      (start_ns),
        .busy       (),
        .done_pulse (done_ns)
    );

    hcsr04_ped #(
        .THRESH_CM(20),
        .PULSE_MS (50)
    ) u_hc_ew (
        .clk        (CLOCK_50),
        .rst_n      (rst_n),
        .echo_in    (hcsr_ew_echo),
        .trig_out   (hcsr_ew_trig),
        .ped_req    (ped_EW_req_hc),
        .start      (start_ew),
        .busy       (),
        .done_pulse (done_ew)
    );

    //================================================
    // 8) 交通灯核心：模式/车辆/行人输入 -> 灯色、相位、剩余时间
    //================================================
    tlc_core_stage1 u_core(
        .clk       (CLOCK_50),
        .rst_n     (rst_n),
        .tick_1s   (tick_1s),
        .mode_sel  (mode_sel),
        .veh_NS    (veh_NS),
        .veh_EW    (veh_EW),
        .ped_NS    (ped_NS_req),
        .ped_EW    (ped_EW_req),
        .light_ns  (light_ns),
        .light_ew  (light_ew),
        .phase_id  (phase_id),
        .time_left (time_left)
    );

    //================================================
    // 9) 时间拆分 + BCD：将 time_left 拆到 NS/EW 显示，并输出模式编号等
    //================================================
    time_splitter #(
        .MODE_FIXED (MODE_FIXED),
        .MODE_ACT   (MODE_ACT),
        .S_NS_GREEN (S_NS_GREEN),
        .S_NS_YELLOW(S_NS_YELLOW),
        .S_EW_GREEN (S_EW_GREEN),
        .S_EW_YELLOW(S_EW_YELLOW)
    ) u_time (
        .mode_sel (mode_sel),
        .phase_id (phase_id),
        .time_left(time_left),
        .ns_tens  (ns_tens),
        .ns_ones  (ns_ones),
        .ew_tens  (ew_tens),
        .ew_ones  (ew_ones),
        .mode_num (mode_num),
        .mode_ones(mode_ones)
    );

    //================================================
    // 10) 数码管显示
    //================================================
    hex7seg u_hex0(.hex(ns_ones),   .seg(HEX0));
    hex7seg u_hex1(.hex(ns_tens),   .seg(HEX1));
    hex7seg u_hex2(.hex(ew_ones),   .seg(HEX2));
    hex7seg u_hex3(.hex(ew_tens),   .seg(HEX3));
    hex7seg u_hex4(.hex(phase_id),  .seg(HEX4));
    hex7seg u_hex5(.hex(mode_ones), .seg(HEX5));

    //================================================
    // 11) 车辆移动 tick + 车辆坐标更新（CLOCK_50 域）
    //================================================
    car_tick_div #(
        .DIV_MAX(26'd4_999_999)
    ) u_cartick (
        .clk      (CLOCK_50),
        .rst_n    (rst_n),
        .tick_car (tick_car)
    );

    car_pos_ctrl #(
        .CAR_NS_Y_START(CAR_NS_Y_START),
        .CAR_NS_Y_MAX  (CAR_NS_Y_MAX),
        .CAR_EW_X_START(CAR_EW_X_START),
        .CAR_EW_X_MAX  (CAR_EW_X_MAX),
        .CAR_STEP_PIX  (CAR_STEP_PIX)
    ) u_carpos (
        .clk      (CLOCK_50),
        .rst_n    (rst_n),
        .tick_car (tick_car),

        .ns_up    (ns_up),
        .ns_down  (ns_down),
        .ew_left  (ew_left),
        .ew_right (ew_right),
        .ns_ws_fwd(ns_ws_fwd),
        .ns_ws_bwd(ns_ws_bwd),
        .ew_ad_fwd(ew_ad_fwd),
        .ew_ad_bwd(ew_ad_bwd),

        .car_n_y  (car_n_y),
        .car_s_y  (car_s_y),
        .car_w_x  (car_w_x),
        .car_e_x  (car_e_x)
    );

    //================================================
    // 12) 违规检测（CLOCK_50 域）：结合车辆位置、方向与红绿灯状态输出 viol_*
    //================================================
    violation_det #(
        .CAR_NS_LEN (CAR_NS_LEN),
        .CAR_EW_LEN (CAR_EW_LEN),
        .CAR_NS_Y_START(CAR_NS_Y_START),
        .CAR_NS_Y_MAX  (CAR_NS_Y_MAX),
        .CAR_EW_X_START(CAR_EW_X_START),
        .CAR_EW_X_MAX  (CAR_EW_X_MAX),
        .CAR_STEP_PIX  (CAR_STEP_PIX),
        .V_ROAD_X_L(V_ROAD_X_L),
        .V_ROAD_X_R(V_ROAD_X_R),
        .H_ROAD_Y_T(H_ROAD_Y_T),
        .H_ROAD_Y_B(H_ROAD_Y_B)
    ) u_viol (
        .clk      (CLOCK_50),
        .rst_n    (rst_n),
        .tick_car (tick_car),

        .ns_up    (ns_up),
        .ns_down  (ns_down),
        .ew_left  (ew_left),
        .ew_right (ew_right),
        .ns_ws_fwd(ns_ws_fwd),
        .ns_ws_bwd(ns_ws_bwd),
        .ew_ad_fwd(ew_ad_fwd),
        .ew_ad_bwd(ew_ad_bwd),

        .car_n_y  (car_n_y),
        .car_s_y  (car_s_y),
        .car_w_x  (car_w_x),
        .car_e_x  (car_e_x),

        .light_ns (light_ns),
        .light_ew (light_ew),

        .viol_n   (viol_n),
        .viol_s   (viol_s),
        .viol_w   (viol_w),
        .viol_e   (viol_e)
    );

    //================================================
    // 13) 先例化 PIP：从 pip_cam_200x150 获取 25MHz 像素时钟
    //================================================
    pip_cam_200x150 #(
        .SRC_W     (640),
        .SRC_H     (480),
        .DST_W     (200),
        .DST_H     (150),
        .PIP_X_S   (640-200),
        .PIP_Y_S   (480-150),
        .USE_FOCUS (1)
    ) u_pip (
        .CLOCK2_50      (CLOCK2_50),
        .CLOCK3_50      (CLOCK3_50),
        .CLOCK4_50      (CLOCK4_50),
        .CLOCK_50       (CLOCK_50),

        .rst_n_key       (rst_n),

        // 由 vga_sync 产生的可视坐标与时序
        .vga_x           (vis_x),
        .vga_y           (vis_y),
        .video_on        (video_on),
        .vga_hs          (VGA_HS),
        .vga_vs          (VGA_VS),

        // 自动对焦开关/区域设置
        .auto_foc_en     (~KEY[3]),
        .sw_fuc_line     (SW[3]),
        .sw_fuc_all_cen  (SW[3]),

        // PIP 输出像素（带 de）
        .pip_de          (pip_de),
        .pip_r           (pip_r),
        .pip_g           (pip_g),
        .pip_b           (pip_b),

        // pip 输出的 25MHz 像素时钟
        .VGA_CLK_25      (pip_vga_clk_25),
        .VGA_SYNC_N      (pip_vga_sync_n_unused),
        .VGA_BLANK_N     (pip_vga_blank_n_unused),

        // SDRAM
        .DRAM_ADDR       (DRAM_ADDR),
        .DRAM_BA         (DRAM_BA),
        .DRAM_CAS_N      (DRAM_CAS_N),
        .DRAM_CKE        (DRAM_CKE),
        .DRAM_CLK        (DRAM_CLK),
        .DRAM_CS_N       (DRAM_CS_N),
        .DRAM_DQ         (DRAM_DQ),
        .DRAM_LDQM       (DRAM_LDQM),
        .DRAM_RAS_N      (DRAM_RAS_N),
        .DRAM_UDQM       (DRAM_UDQM),
        .DRAM_WE_N       (DRAM_WE_N),

        // 摄像头/MIPI Bridge
        .CAMERA_I2C_SCL   (CAMERA_I2C_SCL),
        .CAMERA_I2C_SDA   (CAMERA_I2C_SDA),
        .CAMERA_PWDN_n    (CAMERA_PWDN_n),
        .MIPI_CS_n        (MIPI_CS_n),
        .MIPI_I2C_SCL     (MIPI_I2C_SCL),
        .MIPI_I2C_SDA     (MIPI_I2C_SDA),
        .MIPI_MCLK        (MIPI_MCLK),
        .MIPI_PIXEL_CLK   (MIPI_PIXEL_CLK),
        .MIPI_PIXEL_D     (MIPI_PIXEL_D),
        .MIPI_PIXEL_HS    (MIPI_PIXEL_HS),
        .MIPI_PIXEL_VS    (MIPI_PIXEL_VS),
        .MIPI_REFCLK      (MIPI_REFCLK),
        .MIPI_RESET_n     (MIPI_RESET_n),

        // 状态输出
        .I2C_RELEASE      (I2C_RELEASE),
        .READY_AF         (READY_AF)
    );

    // 系统像素时钟取自 pip 输出
    assign pixel_clk = pip_vga_clk_25;
    assign VGA_CLK   = pixel_clk;

    //================================================
    // 14) VGA 640x480 时序生成（pixel_clk 域）
    //================================================
    vga_sync_640x480 u_sync (
        .clk      (pixel_clk),
        .reset_n  (rst_n),
        .h_count  (h_count),
        .v_count  (v_count),
        .hsync    (VGA_HS),
        .vsync    (VGA_VS),
        .video_on (video_on)
    );

    // 可视区坐标（0..639 / 0..479），超出可视区置 0
    wire [9:0] vis_x = (h_count < 10'd640) ? h_count : 10'd0;
    wire [9:0] vis_y = (v_count < 10'd480) ? v_count : 10'd0;

    //================================================
    // 15) 动画相位与帧 tick（pixel_clk 域）
    //================================================
    vga_anim_phase u_anim (
        .pixel_clk (pixel_clk),
        .rst_n     (rst_n),
        .vga_vs    (VGA_VS),
        .tick_1s_50(tick_1s),
        .anim      (anim),
        .frame_tick(frame_tick)
    );

    //================================================
    // 16) 爆炸特效强度生成（pixel_clk 域），输入为 50MHz 域违规信号
    //================================================
    boom_gen u_boom (
        .pixel_clk (pixel_clk),
        .rst_n     (rst_n),
        .frame_tick(frame_tick),

        .viol_n_50 (viol_n),
        .viol_s_50 (viol_s),
        .viol_w_50 (viol_w),
        .viol_e_50 (viol_e),

        .boom_amp  (boom_amp)
    );

    //================================================
    // 17) 行人动画控制（pixel_clk 域），输入为 50MHz 域信号
    //================================================
    ped_walk_ctrl #(
        .MODE_NIGHT(MODE_NIGHT),
        .MODE_LOCK (MODE_LOCK),
        .PED_STEP_PER_FRAME(8'd2)
    ) u_ped (
        .pixel_clk   (pixel_clk),
        .rst_n       (rst_n),
        .frame_tick  (frame_tick),

        .mode_sel_50 (mode_sel),
        .light_ns_50 (light_ns),
        .light_ew_50 (light_ew),
        .ped_ns_50   (ped_NS_req),
        .ped_ew_50   (ped_EW_req),

        .ped_active  (ped_active),
        .ped_sel     (ped_sel),
        .ped_phase   (ped_phase)
    );

    //================================================
    // 18) 十字路口场景渲染（基础层）
    //================================================
    crossroad_pattern u_pattern (
        .x         (h_count),
        .y         (v_count),
        .video_on  (video_on),

        .light_ns  (light_ns),
        .light_ew  (light_ew),

        .ns_tens   (ns_tens),
        .ns_ones   (ns_ones),
        .ew_tens   (ew_tens),
        .ew_ones   (ew_ones),
        .mode_num  (mode_num),

        .car_n_y   (car_n_y),
        .car_s_y   (car_s_y),
        .car_w_x   (car_w_x),
        .car_e_x   (car_e_x),

        .viol_n    (viol_n),
        .viol_s    (viol_s),
        .viol_w    (viol_w),
        .viol_e    (viol_e),

        .anim      (anim),
        .boom_amp  (boom_amp),

        .ped_active(ped_active),
        .ped_sel   (ped_sel),
        .ped_phase (ped_phase),

        .r         (base_r),
        .g         (base_g),
        .b         (base_b)
    );

    //================================================
    // 19) 最终 VGA 叠加输出
    //     - 将 I2C_RELEASE 同步到 pixel_clk 域
    //     - use_pip=1 时输出 PIP，否则输出基础层 base_*
    //     - 对输出 RGB 做寄存器打拍，确保时序稳定
    //================================================
    reg i2c_ff1, i2c_ff2;
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            i2c_ff1 <= 1'b0;
            i2c_ff2 <= 1'b0;
        end else begin
            i2c_ff1 <= I2C_RELEASE;
            i2c_ff2 <= i2c_ff1;
        end
    end
    wire I2C_REL_PIX = i2c_ff2;

    // PIP 使用条件：PIP 有效像素 + 可视区 + I2C 初始化完成
    wire use_pip = pip_de & video_on & I2C_REL_PIX;

    // RGB 输出寄存器
    reg [7:0] vga_r_r, vga_g_r, vga_b_r;
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            vga_r_r <= 8'd0;
            vga_g_r <= 8'd0;
            vga_b_r <= 8'd0;
        end else if (!video_on) begin
            // 非可视区输出黑色
            vga_r_r <= 8'd0;
            vga_g_r <= 8'd0;
            vga_b_r <= 8'd0;
        end else begin
            // 可视区：根据 use_pip 选择 PIP 或 base 层
            if (use_pip) begin
                vga_r_r <= pip_r;
                vga_g_r <= pip_g;
                vga_b_r <= pip_b;
            end else begin
                vga_r_r <= base_r;
                vga_g_r <= base_g;
                vga_b_r <= base_b;
            end
        end
    end

    // VGA RGB 输出
    assign VGA_R = vga_r_r;
    assign VGA_G = vga_g_r;
    assign VGA_B = vga_b_r;

    // VGA blank/sync
    assign VGA_BLANK_N = video_on;
    assign VGA_SYNC_N  = 1'b0;

    //================================================
    // 20) LED 调试/状态输出
    //================================================
    assign LEDR[2:0] = light_ns;     // NS 灯色状态
    assign LEDR[5:3] = light_ew;     // EW 灯色状态
    assign LEDR[6]   = I2C_RELEASE;  // I2C 初始化完成标志
    assign LEDR[7]   = READY_AF;     // 自动对焦就绪
    assign LEDR[8]   = pip_de;       // PIP 数据有效指示
    assign LEDR[9]   = 1'b0;

endmodule
