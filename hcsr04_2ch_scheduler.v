//======================================================================
// File Name : hcsr04_2ch_scheduler.v
// Function  : HC-SR04 双通道测距调度器（防串扰）
//             - 交替触发 EW 与 NS 两路测距：EW -> (等待 done_ew) -> 静默 GUARD -> NS -> (等待 done_ns) -> 静默 GUARD -> 循环
//             - 内部产生 1ms tick，用于 GUARD_MS 毫秒级计时
//             - start_ns / start_ew 均为“单个 clk 周期”的启动脉冲
//
// Inputs/Outputs:
//   Inputs : clk（系统时钟，典型 50MHz）, rst_n（低有效复位）
//            done_ns（NS 通道测距完成脉冲）, done_ew（EW 通道测距完成脉冲）
//   Outputs: start_ns（NS 通道启动测距脉冲，宽度 1 个 clk 周期）
//            start_ew（EW 通道启动测距脉冲，宽度 1 个 clk 周期）
//
// Parameters:
//   GUARD_MS : 两次测距之间的静默时间（ms），用于抑制两路超声测距互相串扰（建议 5~20ms）
//
//======================================================================

module hcsr04_2ch_scheduler #(
    parameter integer GUARD_MS = 10   // 两次测距之间的静默时间(ms)，抑制串扰
)(
    input  wire clk,                 // 系统时钟（典型 50MHz）
    input  wire rst_n,                // 低有效复位

    input  wire done_ns,              // NS 通道：测距完成指示
    input  wire done_ew,              // EW 通道：测距完成指示
    output reg  start_ns,             // NS 通道：启动测距脉冲（宽度 1 个 clk 周期）
    output reg  start_ew              // EW 通道：启动测距脉冲（宽度 1 个 clk 周期）
);

    //==================================================
    // 1) 产生 1ms tick（用于 GUARD_MS 计时）
    //==================================================
    localparam integer CLK_HZ = 50_000_000;          // 系统时钟频率（Hz），默认按 50MHz
    localparam integer MS_DIV = CLK_HZ / 1000;       // 1ms 分频计数值（50_000）

    reg [$clog2(MS_DIV)-1:0] ms_cnt;                 // 1ms 分频计数器
    reg tick_ms;                                     // 1ms 节拍（宽度 1 个 clk 周期）

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ms_cnt  <= 0;
            tick_ms <= 1'b0;
        end else begin
            if (ms_cnt == MS_DIV-1) begin
                ms_cnt  <= 0;
                tick_ms <= 1'b1;                     // 每 MS_DIV 个 clk 输出一个 1clk 宽 tick
            end else begin
                ms_cnt  <= ms_cnt + 1'b1;
                tick_ms <= 1'b0;
            end
        end
    end

    //==================================================
    // 2) 调度状态机：EW -> Guard -> NS -> Guard -> 循环
    //==================================================
    localparam [2:0]
        S_START_EW = 3'd0,                            // 触发 EW 通道 start
        S_WAIT_EW  = 3'd1,                            // 等待 EW 通道 done
        S_GUARD_1  = 3'd2,                            // Guard 静默（EW -> NS）
        S_START_NS = 3'd3,                            // 触发 NS 通道 start
        S_WAIT_NS  = 3'd4,                            // 等待 NS 通道 done
        S_GUARD_2  = 3'd5;                            // Guard 静默（NS -> EW）

    reg [2:0]  st;                                   // 当前状态
    reg [15:0] guard_cnt;                             // Guard 计数器（单位：ms）

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st        <= S_START_EW;                  // 复位后默认先触发 EW
            start_ns  <= 1'b0;
            start_ew  <= 1'b0;
            guard_cnt <= 0;
        end else begin
            // 默认：start 只打一拍（若处于 START 状态才置 1）
            start_ns <= 1'b0;
            start_ew <= 1'b0;

            case (st)
                //---- 触发 EW 测距 ----
                S_START_EW: begin
                    start_ew <= 1'b1;                 // EW 启动脉冲（1clk）
                    st       <= S_WAIT_EW;            // 转入等待 EW 完成
                end

                //---- 等待 EW 完成 ----
                S_WAIT_EW: begin
                    if (done_ew) begin
                        guard_cnt <= GUARD_MS[15:0];  // 装载 Guard 时间（ms）
                        st        <= S_GUARD_1;       // 转入静默区
                    end
                end

                //---- Guard 静默：EW -> NS ----
                S_GUARD_1: begin
                    if (tick_ms) begin
                        if (guard_cnt == 0)
                            st <= S_START_NS;         // Guard 到期，触发 NS
                        else
                            guard_cnt <= guard_cnt - 1'b1;
                    end
                end

                //---- 触发 NS 测距 ----
                S_START_NS: begin
                    start_ns <= 1'b1;                 // NS 启动脉冲（1clk）
                    st       <= S_WAIT_NS;            // 转入等待 NS 完成
                end

                //---- 等待 NS 完成 ----
                S_WAIT_NS: begin
                    if (done_ns) begin
                        guard_cnt <= GUARD_MS[15:0];  // 装载 Guard 时间（ms）
                        st        <= S_GUARD_2;       // 转入静默区
                    end
                end

                //---- Guard 静默：NS -> EW ----
                S_GUARD_2: begin
                    if (tick_ms) begin
                        if (guard_cnt == 0)
                            st <= S_START_EW;         // Guard 到期，回到触发 EW
                        else
                            guard_cnt <= guard_cnt - 1'b1;
                    end
                end

                default: st <= S_START_EW;
            endcase
        end
    end

endmodule
