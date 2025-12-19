//======================================================================
// File Name : ped_walk_once_dir.v
// Function  : 行人单次走完整趟控制模块
//             - 接收 NS/EW 行人请求，内部做同步与上升沿检测
//             - 收到请求后进入 WALK：ped_active=1，ped_sel 选择方向，ped_phase 从 0 递增到 255
//             - 通过 step_tick 将 WALK_MS 时间等分为 256 步，确保在 WALK_MS 内走完整趟
//             - WALK 过程中再次收到请求时，记录一次 pending 并保存方向
//             - 一趟走完后，若 pending 有效则立即开始下一趟，否则回到 IDLE
//
// Inputs/Outputs:
//   Inputs : clk, rst_n, ped_NS_req, ped_EW_req
//   Outputs: ped_active, ped_sel, ped_phase
//
// Parameters:
//   CLK_HZ
//   WALK_MS
//======================================================================

module ped_walk_once_dir #(
    parameter integer CLK_HZ  = 25_000_000,
    parameter integer WALK_MS = 2500
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire       ped_NS_req,
    input  wire       ped_EW_req,

    output reg        ped_active,
    output reg [1:0]  ped_sel,
    output reg [7:0]  ped_phase
);

    //==================================================
    // 1) 输入同步与上升沿检测
    //==================================================
    reg ns_m, ns_s, ns_d;
    reg ew_m, ew_s, ew_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ns_m <= 1'b0; ns_s <= 1'b0; ns_d <= 1'b0;
            ew_m <= 1'b0; ew_s <= 1'b0; ew_d <= 1'b0;
        end else begin
            ns_m <= ped_NS_req; ns_s <= ns_m; ns_d <= ns_s;
            ew_m <= ped_EW_req; ew_s <= ew_m; ew_d <= ew_s;
        end
    end
    wire ns_rise = ns_s & ~ns_d;
    wire ew_rise = ew_s & ~ew_d;

    //==================================================
    // 2) 步进节拍
    //==================================================
    localparam integer TOTAL_CYC = (CLK_HZ/1000) * WALK_MS;
    localparam integer STEP_CYC  = (TOTAL_CYC < 256) ? 1 : (TOTAL_CYC / 256);

    reg [$clog2(STEP_CYC)-1:0] step_cnt;
    wire step_tick = (step_cnt == STEP_CYC-1);

    //==================================================
    // 3) 状态机与请求排队
    //==================================================
    localparam IDLE = 1'b0;
    localparam WALK = 1'b1;

    reg       st;
    reg       pending;
    reg [1:0] pending_sel;

    function [1:0] sel_from_req;
        input ns_r, ew_r;
        begin
            if (ns_r)      sel_from_req = 2'b01;
            else if (ew_r) sel_from_req = 2'b10;
            else           sel_from_req = 2'b01;
        end
    endfunction

    //==================================================
    // 4) 主时序逻辑
    //==================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st         <= IDLE;
            ped_active <= 1'b0;
            ped_sel    <= 2'b00;
            ped_phase  <= 8'd0;

            step_cnt   <= 0;
            pending    <= 1'b0;
            pending_sel<= 2'b00;
        end else begin
            if (st == WALK) begin
                if (step_tick) step_cnt <= 0;
                else           step_cnt <= step_cnt + 1'b1;
            end else begin
                step_cnt <= 0;
            end

            case (st)
                IDLE: begin
                    ped_active <= 1'b0;
                    ped_sel    <= 2'b00;
                    ped_phase  <= 8'd0;
                    pending    <= 1'b0;

                    if (ns_rise || ew_rise) begin
                        ped_sel    <= sel_from_req(ns_rise, ew_rise);
                        ped_phase  <= 8'd0;
                        ped_active <= 1'b1;
                        st         <= WALK;
                    end
                end

                WALK: begin
                    ped_active <= 1'b1;

                    if (ns_rise || ew_rise) begin
                        pending     <= 1'b1;
                        pending_sel <= sel_from_req(ns_rise, ew_rise);
                    end

                    if (step_tick) begin
                        if (ped_phase == 8'hFF) begin
                            if (pending) begin
                                ped_sel    <= pending_sel;
                                ped_phase  <= 8'd0;
                                pending    <= 1'b0;
                                st         <= WALK;
                            end else begin
                                ped_active <= 1'b0;
                                ped_sel    <= 2'b00;
                                ped_phase  <= 8'd0;
                                st         <= IDLE;
                            end
                        end else begin
                            ped_phase <= ped_phase + 1'b1;
                        end
                    end
                end
            endcase
        end
    end

endmodule
