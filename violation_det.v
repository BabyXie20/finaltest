//======================================================================
// File Name : violation_det.v
// Function  : 闯红灯检测模块
//             - 在车辆按键驱动移动的场景中，检测车辆进入路口边界瞬间是否为红灯
//             - 对四个方向车辆分别输出一次性锁存的违章标记 viol_n/viol_s/viol_w/viol_e
//             - 违章标记在车辆“回到边界/回环位置”时清零，用于下一次检测
//             - 仅在 tick_car 节拍到来时更新，保证与车辆位置更新节奏一致
//
// Inputs/Outputs:
//   Inputs : clk, rst_n, tick_car
//            ns_up, ns_down, ew_left, ew_right
//            ns_ws_fwd, ns_ws_bwd, ew_ad_fwd, ew_ad_bwd
//            car_n_y, car_s_y, car_w_x, car_e_x
//            light_ns, light_ew
//   Outputs: viol_n, viol_s, viol_w, viol_e
//
// Parameters:
//   CAR_NS_LEN, CAR_EW_LEN               : 车辆图元长度
//   CAR_NS_Y_START, CAR_NS_Y_MAX         : NS 方向车辆运动范围
//   CAR_EW_X_START, CAR_EW_X_MAX         : EW 方向车辆运动范围
//   CAR_STEP_PIX                         : 每次 tick_car 的移动步长
//   V_ROAD_X_L, V_ROAD_X_R               : 竖直道路左右边界
//   H_ROAD_Y_T, H_ROAD_Y_B               : 水平道路上下边界
//======================================================================

module violation_det #(
    parameter [9:0] CAR_NS_LEN     = 10'd20,
    parameter [9:0] CAR_EW_LEN     = 10'd20,
    parameter [9:0] CAR_NS_Y_START = 10'd0,
    parameter [9:0] CAR_NS_Y_MAX   = 10'd460,
    parameter [9:0] CAR_EW_X_START = 10'd0,
    parameter [9:0] CAR_EW_X_MAX   = 10'd620,
    parameter [9:0] CAR_STEP_PIX   = 10'd8,

    parameter [9:0] V_ROAD_X_L = 10'd260,
    parameter [9:0] V_ROAD_X_R = 10'd380,
    parameter [9:0] H_ROAD_Y_T = 10'd180,
    parameter [9:0] H_ROAD_Y_B = 10'd300
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tick_car,

    input  wire       ns_up,
    input  wire       ns_down,
    input  wire       ew_left,
    input  wire       ew_right,
    input  wire       ns_ws_fwd,
    input  wire       ns_ws_bwd,
    input  wire       ew_ad_fwd,
    input  wire       ew_ad_bwd,

    input  wire [9:0] car_n_y,
    input  wire [9:0] car_s_y,
    input  wire [9:0] car_w_x,
    input  wire [9:0] car_e_x,

    input  wire [2:0] light_ns,
    input  wire [2:0] light_ew,

    output reg        viol_n,
    output reg        viol_s,
    output reg        viol_w,
    output reg        viol_e
);

    //==================================================
    // 1) 红灯判定
    //    light_* 编码为 {R,Y,G}，红灯取 bit2
    //==================================================
    wire red_ns = light_ns[2];
    wire red_ew = light_ew[2];

    //==================================================
    // 2) 违章标记锁存与清除
    //    - 在车辆跨越路口边界的那一个 tick_car 进行“瞬时判定并锁存”
    //    - 在车辆回到边界/回环条件满足时清除违章标记
    //==================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            viol_n <= 1'b0;
            viol_s <= 1'b0;
            viol_w <= 1'b0;
            viol_e <= 1'b0;
        end else if (tick_car) begin
            //==================================================
            // 2.1) 回环清标记
            //      当车辆移动到边界条件，认为已完成一次循环，允许重新检测
            //==================================================
            if (ns_up    && !(car_n_y > (CAR_NS_Y_START + CAR_STEP_PIX))) viol_n <= 1'b0;
            if (ns_down  && !((car_n_y + CAR_STEP_PIX) < CAR_NS_Y_MAX))  viol_n <= 1'b0;

            if (ns_ws_fwd && !((car_s_y + CAR_STEP_PIX) < CAR_NS_Y_MAX))  viol_s <= 1'b0;
            if (ns_ws_bwd && !(car_s_y > (CAR_NS_Y_START + CAR_STEP_PIX))) viol_s <= 1'b0;

            if (ew_left  && !(car_w_x > (CAR_EW_X_START + CAR_STEP_PIX))) viol_w <= 1'b0;
            if (ew_right && !((car_w_x + CAR_STEP_PIX) < CAR_EW_X_MAX))   viol_w <= 1'b0;

            if (ew_ad_fwd && !((car_e_x + CAR_STEP_PIX) < CAR_EW_X_MAX))   viol_e <= 1'b0;
            if (ew_ad_bwd && !(car_e_x > (CAR_EW_X_START + CAR_STEP_PIX))) viol_e <= 1'b0;

            //==================================================
            // 2.2) 进入路口瞬间锁存
            //      通过“本 tick 前后位置跨越边界线”的条件判定进入路口
            //      在进入瞬间采样红灯并锁存到对应 viol_*
            //==================================================
            if (ns_up &&
                (car_n_y > (CAR_NS_Y_START + CAR_STEP_PIX)) &&
                (car_n_y >= H_ROAD_Y_B) &&
                ((car_n_y - CAR_STEP_PIX) < H_ROAD_Y_B)) begin
                viol_n <= red_ns;
            end

            if (ns_ws_fwd &&
                ((car_s_y + CAR_STEP_PIX) < CAR_NS_Y_MAX) &&
                ((car_s_y + CAR_NS_LEN) <= H_ROAD_Y_T) &&
                ((car_s_y + CAR_STEP_PIX + CAR_NS_LEN) > H_ROAD_Y_T)) begin
                viol_s <= red_ns;
            end

            if (ew_left &&
                (car_w_x > (CAR_EW_X_START + CAR_STEP_PIX)) &&
                (car_w_x >= V_ROAD_X_R) &&
                ((car_w_x - CAR_STEP_PIX) < V_ROAD_X_R)) begin
                viol_w <= red_ew;
            end

            if (ew_ad_fwd &&
                ((car_e_x + CAR_STEP_PIX) < CAR_EW_X_MAX) &&
                ((car_e_x + CAR_EW_LEN) <= V_ROAD_X_L) &&
                ((car_e_x + CAR_STEP_PIX + CAR_EW_LEN) > V_ROAD_X_L)) begin
                viol_e <= red_ew;
            end
        end
    end

endmodule
