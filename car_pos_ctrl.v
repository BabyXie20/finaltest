//======================================================================
// File Name : car_pos_ctrl.v
// Function  : 小车位置控制模块（四方向车辆坐标更新）
//             - 在 tick_car 有效时，根据方向控制输入更新车辆坐标
//             - 支持四辆车：北向车/南向车（Y 坐标），西向车/东向车（X 坐标）
//             - 采用“到边界后回绕”的方式：越界则跳回起始端，实现循环移动
//
// Parameters: CAR_NS_Y_START - 南北向 Y 起始位置（最小值/起点）
//             CAR_NS_Y_MAX   - 南北向 Y 最大位置（最大值/终点）
//             CAR_EW_X_START - 东西向 X 起始位置（最小值/起点）
//             CAR_EW_X_MAX   - 东西向 X 最大位置（最大值/终点）
//             CAR_STEP_PIX   - 每次 tick_car 更新的像素步进（移动速度）
//
// Inputs    : clk       - 工作时钟
//             rst_n     - 低有效复位（异步复位）
//             tick_car  - 车辆移动节拍脉冲（为 1 时才更新坐标）
//
//             ns_up     - 北向车 car_n_y：向上移动控制（Y 减小）
//             ns_down   - 北向车 car_n_y：向下移动控制（Y 增大）
//             ew_left   - 西向车 car_w_x：向左移动控制（X 减小）
//             ew_right  - 西向车 car_w_x：向右移动控制（X 增大）
//
//             ns_ws_fwd - 南向车 car_s_y：正向移动控制（Y 增大）
//             ns_ws_bwd - 南向车 car_s_y：反向移动控制（Y 减小）
//             ew_ad_fwd - 东向车 car_e_x：正向移动控制（X 增大）
//             ew_ad_bwd - 东向车 car_e_x：反向移动控制（X 减小）
//
// Outputs   : car_n_y   - 北向车 Y 坐标
//             car_s_y   - 南向车 Y 坐标
//             car_w_x   - 西向车 X 坐标
//             car_e_x   - 东向车 X 坐标
//======================================================================

module car_pos_ctrl #(
    parameter [9:0] CAR_NS_Y_START = 10'd0,
    parameter [9:0] CAR_NS_Y_MAX   = 10'd460,
    parameter [9:0] CAR_EW_X_START = 10'd0,
    parameter [9:0] CAR_EW_X_MAX   = 10'd620,
    parameter [9:0] CAR_STEP_PIX   = 10'd8
)(
    input  wire clk,
    input  wire rst_n,
    input  wire tick_car,

    input  wire ns_up,
    input  wire ns_down,
    input  wire ew_left,
    input  wire ew_right,
    input  wire ns_ws_fwd,
    input  wire ns_ws_bwd,
    input  wire ew_ad_fwd,
    input  wire ew_ad_bwd,

    output reg  [9:0] car_n_y,
    output reg  [9:0] car_s_y,
    output reg  [9:0] car_w_x,
    output reg  [9:0] car_e_x
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位初始化：将四辆车放到各自的起始位置（这里按你的设定分别放到两端）
            car_n_y <= CAR_NS_Y_MAX;    // 北向车：初始化在 Y 最大端
            car_s_y <= CAR_NS_Y_START;  // 南向车：初始化在 Y 起始端
            car_w_x <= CAR_EW_X_MAX;    // 西向车：初始化在 X 最大端
            car_e_x <= CAR_EW_X_START;  // 东向车：初始化在 X 起始端
        end else if (tick_car) begin
            // 只有 tick_car 有效时才更新坐标，控制移动节奏/速度

            //==================================================
            // 北向车（car_n_y）：ns_up / ns_down 控制
            // 规则：只允许单方向有效（ns_up && !ns_down 或 ns_down && !ns_up）
            //==================================================
            if (ns_up && !ns_down) begin
                // 向上：Y 减小；到达起始边界则回绕到最大端
                if (car_n_y > CAR_NS_Y_START + CAR_STEP_PIX) car_n_y <= car_n_y - CAR_STEP_PIX;
                else                                        car_n_y <= CAR_NS_Y_MAX;
            end else if (ns_down && !ns_up) begin
                // 向下：Y 增大；到达最大边界则回绕到起始端
                if (car_n_y + CAR_STEP_PIX < CAR_NS_Y_MAX)  car_n_y <= car_n_y + CAR_STEP_PIX;
                else                                        car_n_y <= CAR_NS_Y_START;
            end

            //==================================================
            // 南向车（car_s_y）：ns_ws_fwd / ns_ws_bwd 控制
            //==================================================
            if (ns_ws_fwd && !ns_ws_bwd) begin
                // 正向：Y 增大；到达最大边界则回绕到起始端
                if (car_s_y + CAR_STEP_PIX < CAR_NS_Y_MAX)  car_s_y <= car_s_y + CAR_STEP_PIX;
                else                                        car_s_y <= CAR_NS_Y_START;
            end else if (ns_ws_bwd && !ns_ws_fwd) begin
                // 反向：Y 减小；到达起始边界则回绕到最大端
                if (car_s_y > CAR_NS_Y_START + CAR_STEP_PIX) car_s_y <= car_s_y - CAR_STEP_PIX;
                else                                         car_s_y <= CAR_NS_Y_MAX;
            end

            //==================================================
            // 西向车（car_w_x）：ew_left / ew_right 控制
            //==================================================
            if (ew_left && !ew_right) begin
                // 向左：X 减小；到达起始边界则回绕到最大端
                if (car_w_x > CAR_EW_X_START + CAR_STEP_PIX) car_w_x <= car_w_x - CAR_STEP_PIX;
                else                                         car_w_x <= CAR_EW_X_MAX;
            end else if (ew_right && !ew_left) begin
                // 向右：X 增大；到达最大边界则回绕到起始端
                if (car_w_x + CAR_STEP_PIX < CAR_EW_X_MAX)   car_w_x <= car_w_x + CAR_STEP_PIX;
                else                                         car_w_x <= CAR_EW_X_START;
            end

            //==================================================
            // 东向车（car_e_x）：ew_ad_fwd / ew_ad_bwd 控制
            //==================================================
            if (ew_ad_fwd && !ew_ad_bwd) begin
                // 正向：X 增大；到达最大边界则回绕到起始端
                if (car_e_x + CAR_STEP_PIX < CAR_EW_X_MAX)   car_e_x <= car_e_x + CAR_STEP_PIX;
                else                                         car_e_x <= CAR_EW_X_START;
            end else if (ew_ad_bwd && !ew_ad_fwd) begin
                // 反向：X 减小；到达起始边界则回绕到最大端
                if (car_e_x > CAR_EW_X_START + CAR_STEP_PIX) car_e_x <= car_e_x - CAR_STEP_PIX;
                else                                         car_e_x <= CAR_EW_X_MAX;
            end
        end
    end

endmodule
