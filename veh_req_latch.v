module veh_req_latch #(
    parameter [1:0] MODE_ACT   = 2'b01,
    parameter [3:0] S_NS_GREEN = 4'd0,
    parameter [3:0] S_EW_GREEN = 4'd3
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [1:0] mode_sel,
    input  wire [3:0] phase_id,

    input  wire       veh_NS_lvl,
    input  wire       veh_EW_lvl,
    input  wire       veh_NS_p,
    input  wire       veh_EW_p,

    output wire       veh_NS,
    output wire       veh_EW
);

    reg veh_NS_req, veh_EW_req;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            veh_NS_req <= 1'b0;
            veh_EW_req <= 1'b0;
        end else if (mode_sel == MODE_ACT) begin
            if (veh_NS_p)                 veh_NS_req <= 1'b1;
            else if (phase_id == S_NS_GREEN) veh_NS_req <= 1'b0;

            if (veh_EW_p)                 veh_EW_req <= 1'b1;
            else if (phase_id == S_EW_GREEN) veh_EW_req <= 1'b0;
        end else begin
            veh_NS_req <= 1'b0;
            veh_EW_req <= 1'b0;
        end
    end

    assign veh_NS = veh_NS_lvl | veh_NS_req;
    assign veh_EW = veh_EW_lvl | veh_EW_req;

endmodule
