//======================================================================
// File Name : ps2.v
// Function  : PS/2 接收器
//             - 在单一 FPGA 时钟域内接收 PS/2 键盘串行数据
//             - 对 PS/2 clock/data 做多级同步，并在同步后的 PS/2 时钟下降沿采样数据
//             - 按 11bit 帧格式移位接收：start(0) + data(8) + parity(1) + stop(1)
//             - 在帧收齐时进行合法性检查：start/stop/奇校验
//             - 合法帧输出 data_out，并拉高 new_code 一个 clock_fpga 周期
//
// Inputs/Outputs:
//   Inputs : clock_key, data_key
//            clock_fpga, reset
//   Outputs: led, data_out, new_code
//======================================================================

module ps2 (
    input  wire clock_key,
    input  wire data_key,

    input  wire clock_fpga,
    input  wire reset,

    output wire led,
    output wire [7:0] data_out,
    output wire new_code
);

    //==================================================
    // 1) PS/2 clock/data 同步到 FPGA 时钟域
    //    - PS/2 空闲为高电平，复位时同步寄存器置 1
    //    - 用同步后的 clock 变化检测下降沿作为采样时刻
    //==================================================
    reg [2:0] ps2_clk_sync;
    reg [2:0] ps2_data_sync;

    always @(posedge clock_fpga or negedge reset) begin
        if (!reset) begin
            ps2_clk_sync  <= 3'b111;
            ps2_data_sync <= 3'b111;
        end else begin
            ps2_clk_sync  <= {ps2_clk_sync[1:0],  clock_key};
            ps2_data_sync <= {ps2_data_sync[1:0], data_key};
        end
    end

    wire ps2_data_s = ps2_data_sync[2];
    wire ps2_clk_falling = (ps2_clk_sync[2:1] == 2'b10);

    //==================================================
    // 2) 串行移位接收 11bit 帧
    //    帧格式
    //      bit0  : start
    //      bit8:1: data[7:0]
    //      bit9  : parity
    //      bit10 : stop
    //==================================================
    reg [10:0] shift_reg;
    reg [3:0]  bit_count;

    wire [10:0] next_shift = {ps2_data_s, shift_reg[10:1]};
    wire frame_done = (bit_count == 4'd10);

    //==================================================
    // 3) 帧合法性检查
    //    - start 必须为 0
    //    - stop  必须为 1
    //    - 奇校验：{parity, data} 的 1 个数为奇数
    //==================================================
    wire start_ok   = (next_shift[0]  == 1'b0);
    wire stop_ok    = (next_shift[10] == 1'b1);

    wire parity_odd = ^{next_shift[9], next_shift[8:1]};
    wire parity_ok  = parity_odd;

    wire frame_valid = start_ok & stop_ok & parity_ok;

    //==================================================
    // 4) 帧完成时输出扫描码
    //    - new_code_reg 为 1-cycle 脉冲
    //    - 不合法帧直接丢弃
    //==================================================
    reg [7:0] data_reg;
    reg       new_code_reg;

    always @(posedge clock_fpga or negedge reset) begin
        if (!reset) begin
            shift_reg    <= 11'd0;
            bit_count    <= 4'd0;
            data_reg     <= 8'd0;
            new_code_reg <= 1'b0;
        end else begin
            new_code_reg <= 1'b0;

            if (ps2_clk_falling) begin
                shift_reg <= next_shift;

                if (frame_done) begin
                    bit_count <= 4'd0;

                    if (frame_valid) begin
                        data_reg     <= next_shift[8:1];
                        new_code_reg <= 1'b1;
                    end
                end else begin
                    bit_count <= bit_count + 4'd1;
                end
            end
        end
    end

    //==================================================
    // 5) 输出映射
    //==================================================
    assign data_out = data_reg;
    assign new_code = new_code_reg;
    assign led      = new_code_reg;

endmodule
