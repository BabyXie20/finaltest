//======================================================================
// File Name : hcsr04_ped.v
// Function  : HC-SR04 测距行人触发模块（单次测距 + 行人请求保持）
//             - 接收顶层 start 触发，内部锁存为 start_pending，避免错过 us_tick
//             - 产生 trig_out 触发脉冲，测量 echo 高电平宽度
//             - 用回波宽度与门限换算结果比较，判定是否“有人靠近”
//             - 仅在“有人”从无到有时触发 ped_req，并保持一段时间
//             - done_pulse 在一次测距结束时输出脉冲，供调度器/顶层采样
//             - busy 指示模块正忙或存在待处理 start_pending
//
// Inputs/Outputs:
//   Inputs : clk, rst_n, echo_in, start
//   Outputs: trig_out, ped_req, busy, done_pulse
//
// Parameters:
//   THRESH_CM : 距离门限（cm）
//   PULSE_MS  : ped_req 保持时间（ms）
//======================================================================

module hcsr04_ped #(
    parameter integer THRESH_CM = 20,   // 小于等于该距离判定“有人”
    parameter integer PULSE_MS  = 50    // ped_req 保持时间（ms）
)(
    input  wire clk,
    input  wire rst_n,
    input  wire echo_in,
    output reg  trig_out,
    output reg  ped_req,

    input  wire start,
    output wire busy,
    output reg  done_pulse
);

    //==================================================
    // 1) 时基/门限换算
    //    - us_tick：用 1us 粒度推进 FSM
    //    - THRESH_US：把 cm 门限换算为 echo 高电平宽度门限（经验：cm≈us/58）
    //    - HOLD_US：把 ms 保持时间换算为 us 倒计时
    //==================================================
    localparam integer CLK_HZ     = 50_000_000;
    localparam integer US_DIV     = CLK_HZ / 1_000_000;
    localparam integer TRIG_US    = 10;
    localparam integer TIMEOUT_US = 30_000;
    localparam integer HOLD_US    = PULSE_MS  * 1000;
    localparam integer THRESH_US  = THRESH_CM * 58;

    //==================================================
    // 2) Echo 同步：两级寄存器同步到 clk 域，降低亚稳态风险
    //==================================================
    reg echo_ff1, echo_ff2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            echo_ff1 <= 1'b0;
            echo_ff2 <= 1'b0;
        end else begin
            echo_ff1 <= echo_in;
            echo_ff2 <= echo_ff1;
        end
    end
    wire echo = echo_ff2;

    //==================================================
    // 3) 1us tick 产生：每 US_DIV 个 clk 周期输出一次 us_tick
    //==================================================
    reg [$clog2(US_DIV)-1:0] us_cnt;
    reg us_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            us_cnt  <= 0;
            us_tick <= 1'b0;
        end else begin
            if (us_cnt == US_DIV-1) begin
                us_cnt  <= 0;
                us_tick <= 1'b1;
            end else begin
                us_cnt  <= us_cnt + 1'b1;
                us_tick <= 1'b0;
            end
        end
    end

    //==================================================
    // 4) 测距 FSM
    //    IDLE  : 等待 start_pending
    //    TRIG  : 输出 10us trig 脉冲
    //    ECHO_H: 等待 echo 拉高（超时则结束）
    //    ECHO_W: 统计 echo 高电平宽度（回落或超时则结束）
    //    DONE  : 依据宽度判“近”，在 0->1 时触发 ped_req 保持，并输出 done_pulse
    //==================================================
    localparam [2:0]
        ST_IDLE   = 3'd0,
        ST_TRIG   = 3'd1,
        ST_ECHO_H = 3'd2,
        ST_ECHO_W = 3'd3,
        ST_DONE   = 3'd4;

    reg [2:0]  st;
    reg [31:0] t_us;
    reg [31:0] echo_w_us;

    //==================================================
    // 5) 行人触发保持：near_prev 用于“上升沿触发”，hold_us 用于保持窗口
    //==================================================
    reg near_prev;
    reg [31:0] hold_us;

    //==================================================
    // 6) start 锁存与 busy
    //    - start_pending：把来自顶层的 start 脉冲锁存为“待处理请求”
    //    - busy：FSM 运行中或存在待处理 start_pending
    //==================================================
    reg start_pending;
    assign busy = (st != ST_IDLE) | start_pending;

    //==================================================
    // 7) 主时序：在 us_tick 下推进 FSM；done_pulse 为一次测距结束脉冲
    //==================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st            <= ST_IDLE;
            trig_out      <= 1'b0;
            ped_req       <= 1'b0;
            done_pulse    <= 1'b0;

            t_us          <= 0;
            echo_w_us     <= 0;

            near_prev     <= 1'b0;
            hold_us       <= 0;

            start_pending <= 1'b0;
        end else begin
            done_pulse <= 1'b0;

            // 锁存 start：避免错过 us_tick 推进窗口
            if (start && (st == ST_IDLE) && !start_pending)
                start_pending <= 1'b1;

            // ped_req 保持：hold_us 倒计时期间维持为高
            if (us_tick) begin
                if (hold_us != 0) begin
                    hold_us <= hold_us - 1;
                    ped_req <= 1'b1;
                end else begin
                    ped_req <= 1'b0;
                end
            end

            if (us_tick) begin
                case (st)
                    ST_IDLE: begin
                        trig_out  <= 1'b0;
                        t_us      <= 0;
                        echo_w_us <= 0;
                        if (start_pending) begin
                            start_pending <= 1'b0;
                            st            <= ST_TRIG;
                            t_us          <= 0;
                        end
                    end

                    ST_TRIG: begin
                        trig_out <= 1'b1;
                        if (t_us >= TRIG_US-1) begin
                            trig_out  <= 1'b0;
                            t_us      <= 0;
                            echo_w_us <= 0;
                            st        <= ST_ECHO_H;
                        end else begin
                            t_us <= t_us + 1;
                        end
                    end

                    ST_ECHO_H: begin
                        if (echo) begin
                            t_us <= 0;
                            st   <= ST_ECHO_W;
                        end else if (t_us >= TIMEOUT_US) begin
                            st   <= ST_DONE;
                        end else begin
                            t_us <= t_us + 1;
                        end
                    end

                    ST_ECHO_W: begin
                        if (!echo) begin
                            st <= ST_DONE;
                        end else if (echo_w_us >= TIMEOUT_US) begin
                            st <= ST_DONE;
                        end else begin
                            echo_w_us <= echo_w_us + 1;
                        end
                    end

                    ST_DONE: begin
                        // “近”判定 + 上升沿触发保持窗口
                        if (echo_w_us != 0 && echo_w_us <= THRESH_US) begin
                            if (!near_prev)
                                hold_us <= HOLD_US;
                            near_prev <= 1'b1;
                        end else begin
                            near_prev <= 1'b0;
                        end

                        done_pulse <= 1'b1;

                        st        <= ST_IDLE;
                        trig_out  <= 1'b0;
                        t_us      <= 0;
                        echo_w_us <= 0;
                    end

                    default: st <= ST_IDLE;
                endcase
            end
        end
    end

endmodule
