//======================================================================
// File Name : Sdram_Control.v
// Function  : SDRAM 顶层控制器
//             - 提供最多 2 路写入通道与 2 路读取通道的“流式”SDRAM 访问接口
//             - 每路通道通过异步 FIFO 完成跨时钟域缓存与突发访问聚合
//             - 内部状态机在 CLK 域发起 READ/WRITE 命令，并按突发长度 mLENGTH 进行数据搬运
//             - 通过 WR*_LOAD / RD*_LOAD 对 FIFO 与通道地址/长度进行初始化/重新对齐
//             - 本版本对 WR1/RD1 增强：支持动态切换 base/max/len，并在安全窗口提交，避免读写混帧
//
// Inputs/Outputs:
//   Host Side
//     Inputs : RESET_N, CLK
//   Write Side 1
//     Inputs : WR1_DATA, WR1, WR1_ADDR, WR1_MAX_ADDR, WR1_LENGTH, WR1_LOAD, WR1_CLK
//   Write Side 2
//     Inputs : WR2_DATA, WR2, WR2_ADDR, WR2_MAX_ADDR, WR2_LENGTH, WR2_LOAD, WR2_CLK
//   Read Side 1
//     Inputs : RD1, RD1_ADDR, RD1_MAX_ADDR, RD1_LENGTH, RD1_LOAD, RD1_CLK
//     Outputs: RD1_DATA
//   Read Side 2
//     Inputs : RD2, RD2_ADDR, RD2_MAX_ADDR, RD2_LENGTH, RD2_LOAD, RD2_CLK
//     Outputs: RD2_DATA
//   SDRAM Side
//     Outputs: SA, BA, CS_N, CKE, RAS_N, CAS_N, WE_N, DQM
//     Inout  : DQ
//======================================================================

module Sdram_Control (
    RESET_N,
    CLK,

    WR1_DATA,
    WR1,
    WR1_ADDR,
    WR1_MAX_ADDR,
    WR1_LENGTH,
    WR1_LOAD,
    WR1_CLK,

    WR2_DATA,
    WR2,
    WR2_ADDR,
    WR2_MAX_ADDR,
    WR2_LENGTH,
    WR2_LOAD,
    WR2_CLK,

    RD1_DATA,
    RD1,
    RD1_ADDR,
    RD1_MAX_ADDR,
    RD1_LENGTH,
    RD1_LOAD,
    RD1_CLK,

    RD2_DATA,
    RD2,
    RD2_ADDR,
    RD2_MAX_ADDR,
    RD2_LENGTH,
    RD2_LOAD,
    RD2_CLK,

    SA,
    BA,
    CS_N,
    CKE,
    RAS_N,
    CAS_N,
    WE_N,
    DQ,
    DQM
);

`include  "Sdram_Params.h"

    //==================================================
    // 1) 端口定义
    //==================================================
    input                           RESET_N;
    input                           CLK;

    input  [`DSIZE-1:0]             WR1_DATA;
    input                           WR1;
    input  [`ASIZE-1:0]             WR1_ADDR;
    input  [`ASIZE-1:0]             WR1_MAX_ADDR;
    input         [10:0]            WR1_LENGTH;
    input                           WR1_LOAD;
    input                           WR1_CLK;

    input  [`DSIZE-1:0]             WR2_DATA;
    input                           WR2;
    input  [`ASIZE-1:0]             WR2_ADDR;
    input  [`ASIZE-1:0]             WR2_MAX_ADDR;
    input         [10:0]            WR2_LENGTH;
    input                           WR2_LOAD;
    input                           WR2_CLK;

    output [`DSIZE-1:0]             RD1_DATA;
    input                           RD1;
    input  [`ASIZE-1:0]             RD1_ADDR;
    input  [`ASIZE-1:0]             RD1_MAX_ADDR;
    input         [10:0]            RD1_LENGTH;
    input                           RD1_LOAD;
    input                           RD1_CLK;

    output [`DSIZE-1:0]             RD2_DATA;
    input                           RD2;
    input  [`ASIZE-1:0]             RD2_ADDR;
    input  [`ASIZE-1:0]             RD2_MAX_ADDR;
    input         [10:0]            RD2_LENGTH;
    input                           RD2_LOAD;
    input                           RD2_CLK;

    output        [11:0]            SA;
    output         [1:0]            BA;
    output         [1:0]            CS_N;
    output                          CKE;
    output                          RAS_N;
    output                          CAS_N;
    output                          WE_N;
    inout   [`DSIZE-1:0]            DQ;
    output [`DSIZE/8-1:0]           DQM;

    //==================================================
    // 2) 控制器内部寄存器与状态
    //==================================================
    reg     [`ASIZE-1:0]            mADDR;
    reg            [10:0]           mLENGTH;

    reg     [`ASIZE-1:0]            rWR1_ADDR;
    reg     [`ASIZE-1:0]            rWR1_MAX_ADDR;
    reg            [10:0]           rWR1_LENGTH;

    reg     [`ASIZE-1:0]            rWR2_ADDR;
    reg     [`ASIZE-1:0]            rWR2_MAX_ADDR;
    reg            [10:0]           rWR2_LENGTH;

    reg     [`ASIZE-1:0]            rRD1_ADDR;
    reg     [`ASIZE-1:0]            rRD1_MAX_ADDR;
    reg            [10:0]           rRD1_LENGTH;

    reg     [`ASIZE-1:0]            rRD2_ADDR;
    reg     [`ASIZE-1:0]            rRD2_MAX_ADDR;
    reg            [10:0]           rRD2_LENGTH;

    //==================================================
    // 3) WR1/RD1 base 与动态配置切换机制
    //    - base 用于环形回绕，避免依赖输入端口直接 wrap
    //    - 监测输入参数变化，先挂起 pending，再在安全窗口提交
    //==================================================
    reg     [`ASIZE-1:0]            rWR1_BASE;
    reg     [`ASIZE-1:0]            rRD1_BASE;

    reg     [`ASIZE-1:0]            inWR1_ADDR_q, inWR1_MAX_q;
    reg            [10:0]           inWR1_LEN_q;
    reg                             wr1_cfg_pending;
    reg     [`ASIZE-1:0]            wr1_addr_pend, wr1_max_pend;
    reg            [10:0]           wr1_len_pend;

    reg     [`ASIZE-1:0]            inRD1_ADDR_q, inRD1_MAX_q;
    reg            [10:0]           inRD1_LEN_q;
    reg                             rd1_cfg_pending;
    reg     [`ASIZE-1:0]            rd1_addr_pend, rd1_max_pend;
    reg            [10:0]           rd1_len_pend;

    //==================================================
    // 4) 读写仲裁与突发控制
    //==================================================
    reg            [1:0]            WR_MASK;
    reg            [1:0]            RD_MASK;
    reg                             mWR_DONE;
    reg                             mRD_DONE;
    reg                             mWR, Pre_WR;
    reg                             mRD, Pre_RD;
    reg            [9:0]            ST;
    reg            [1:0]            CMD;
    reg                             PM_STOP;
    reg                             PM_DONE;
    reg                             Read;
    reg                             Write;
    reg     [`DSIZE-1:0]            mDATAOUT;
    wire    [`DSIZE-1:0]            mDATAIN;
    wire    [`DSIZE-1:0]            mDATAIN1;
    wire    [`DSIZE-1:0]            mDATAIN2;
    wire                            CMDACK;

    //==================================================
    // 5) SDRAM 控制信号寄存与数据通路
    //==================================================
    reg     [`DSIZE/8-1:0]          DQM;
    reg            [12:0]           SA;
    reg             [1:0]           BA;
    reg             [1:0]           CS_N;
    reg                             CKE;
    reg                             RAS_N;
    reg                             CAS_N;
    reg                             WE_N;
    wire    [`DSIZE-1:0]            DQOUT;

    wire    [`DSIZE/8-1:0]          IDQM;
    wire           [12:0]           ISA;
    wire            [1:0]           IBA;
    wire            [1:0]           ICS_N;
    wire                            ICKE;
    wire                            IRAS_N;
    wire                            ICAS_N;
    wire                            IWE_N;

    //==================================================
    // 6) FIFO 与 SDRAM 内部接口信号
    //==================================================
    reg                             OUT_VALID;
    reg                             IN_REQ;
    wire           [10:0]           write_side_fifo_rusedw1;
    wire           [10:0]           write_side_fifo_rusedw2;
    wire           [10:0]           read_side_fifo_wusedw1;
    wire           [10:0]           read_side_fifo_wusedw2;

    wire    [`ASIZE-1:0]            saddr;
    wire                            load_mode;
    wire                            nop;
    wire                            reada;
    wire                            writea;
    wire                            refresh;
    wire                            precharge;
    wire                            oe;
    wire                            ref_ack;
    wire                            ref_req;
    wire                            init_req;
    wire                            cm_ack;
    wire                            active;

    //==================================================
    // 7) 子模块实例
    //    - control_interface 负责命令仲裁与地址译码
    //    - command 负责 SDRAM 时序产生
    //    - sdr_data_path 负责 DQ 数据方向与掩码
    //    - WR/RD FIFO 负责跨时钟域缓冲
    //==================================================
    control_interface  u_control_interface (
        .CLK(CLK),
        .RESET_N(RESET_N),
        .CMD(CMD),
        .ADDR(mADDR),
        .REF_ACK(ref_ack),
        .CM_ACK(cm_ack),
        .NOP(nop),
        .READA(reada),
        .WRITEA(writea),
        .REFRESH(refresh),
        .PRECHARGE(precharge),
        .LOAD_MODE(load_mode),
        .SADDR(saddr),
        .REF_REQ(ref_req),
        .INIT_REQ(init_req),
        .CMD_ACK(CMDACK)
    );

    command  u_command (
        .CLK(CLK),
        .RESET_N(RESET_N),
        .SADDR(saddr),
        .NOP(nop),
        .READA(reada),
        .WRITEA(writea),
        .REFRESH(refresh),
        .LOAD_MODE(load_mode),
        .PRECHARGE(precharge),
        .REF_REQ(ref_req),
        .INIT_REQ(init_req),
        .REF_ACK(ref_ack),
        .CM_ACK(cm_ack),
        .OE(oe),
        .PM_STOP(PM_STOP),
        .PM_DONE(PM_DONE),
        .SA(ISA),
        .BA(IBA),
        .CS_N(ICS_N),
        .CKE(ICKE),
        .RAS_N(IRAS_N),
        .CAS_N(ICAS_N),
        .WE_N(IWE_N)
    );

    sdr_data_path  u_sdr_data_path (
        .CLK(CLK),
        .RESET_N(RESET_N),
        .DATAIN(mDATAIN),
        .DM(2'b00),
        .DQOUT(DQOUT),
        .DQM(IDQM)
    );

    Sdram_WR_FIFO  u_write1_fifo (
        .data(WR1_DATA),
        .wrreq(WR1),
        .wrclk(WR1_CLK),
        .aclr(WR1_LOAD),
        .rdreq(IN_REQ && WR_MASK[0]),
        .rdclk(CLK),
        .q(mDATAIN1),
        .rdusedw(write_side_fifo_rusedw1)
    );

    Sdram_RD_FIFO  u_read1_fifo (
        .data(mDATAOUT),
        .wrreq(OUT_VALID && RD_MASK[0]),
        .wrclk(CLK),
        .aclr(RD1_LOAD),
        .rdreq(RD1),
        .rdclk(RD1_CLK),
        .q(RD1_DATA),
        .wrusedw(read_side_fifo_wusedw1)
    );

    //==================================================
    // 8) 结构连接与 SDRAM 输出寄存
    //==================================================
    assign mDATAIN = mDATAIN1;
    assign DQ      = oe ? DQOUT : `DSIZE'hzzzz;
    assign active  = Read | Write;

    always @ (posedge CLK) begin
        SA      <= (ST==SC_CL+mLENGTH) ? 12'h200 : ISA;
        BA      <= IBA;
        CS_N    <= ICS_N;
        CKE     <= ICKE;
        RAS_N   <= (ST==SC_CL+mLENGTH) ? 1'b0 : IRAS_N;
        CAS_N   <= (ST==SC_CL+mLENGTH) ? 1'b1 : ICAS_N;
        WE_N    <= (ST==SC_CL+mLENGTH) ? 1'b0 : IWE_N;
        PM_STOP <= (ST==SC_CL+mLENGTH) ? 1'b1 : 1'b0;
        PM_DONE <= (ST==SC_CL+SC_RCD+mLENGTH+2) ? 1'b1 : 1'b0;
        DQM     <= (active && (ST>=SC_CL)) ? (((ST==SC_CL+mLENGTH) && Write) ? 2'b11 : 2'b0) : 2'b11;
        mDATAOUT<= DQ;
    end

    //==================================================
    // 9) 主读写状态机
    //    - ST 控制一次突发访问的时序推进
    //    - mWR/mRD 上升沿触发一次写/读事务
    //    - IN_REQ 在写突发窗口内拉高，用于从写 FIFO 取数
    //    - OUT_VALID 在读突发窗口内拉高，用于写入读 FIFO
    //==================================================
    always@(posedge CLK or negedge RESET_N) begin
        if(!RESET_N) begin
            CMD       <= 0;
            ST        <= 0;
            Pre_RD    <= 0;
            Pre_WR    <= 0;
            Read      <= 0;
            Write     <= 0;
            OUT_VALID <= 0;
            IN_REQ    <= 0;
            mWR_DONE  <= 0;
            mRD_DONE  <= 0;
        end else begin
            Pre_RD <= mRD;
            Pre_WR <= mWR;

            case (ST)
            0: begin
                if (!Pre_WR && mWR) begin
                    Read  <= 0;
                    Write <= 1;
                    CMD   <= 2'b10;
                    ST    <= 1;
                end else if (!Pre_RD && mRD) begin
                    Read  <= 1;
                    Write <= 0;
                    CMD   <= 2'b01;
                    ST    <= 1;
                end
            end
            1: begin
                if (CMDACK) begin
                    CMD <= 2'b00;
                    ST  <= 2;
                end
            end
            default: begin
                if (ST != SC_CL+SC_RCD+mLENGTH+1) ST <= ST + 1;
                else ST <= 0;
            end
            endcase

            if (Write) begin
                if (ST==SC_CL-1) IN_REQ <= 1;
                else if (ST==SC_CL+mLENGTH-1) IN_REQ <= 0;
                else if (ST==SC_CL+SC_RCD+mLENGTH) begin
                    Write    <= 0;
                    mWR_DONE <= 1;
                end
            end else mWR_DONE <= 0;

            if (Read) begin
                if (ST==SC_CL+SC_RCD+1) OUT_VALID <= 1;
                else if (ST==SC_CL+SC_RCD+mLENGTH+1) begin
                    OUT_VALID <= 0;
                    Read      <= 0;
                    mRD_DONE  <= 1;
                end
            end else mRD_DONE <= 0;
        end
    end

    //==================================================
    // 10) WR1/RD1 内部地址与长度控制
    //     - 监测输入配置变化，挂起 pending
    //     - 在 FIFO 空且控制器空闲时提交新配置，避免突发过程中切换
    //     - 完成一次突发后地址递增，达到 max 后回绕到 base
    //==================================================
    always@(posedge CLK or negedge RESET_N) begin
        if (!RESET_N) begin
            rWR1_BASE     <= WR1_ADDR;
            rWR1_ADDR     <= WR1_ADDR;
            rWR1_MAX_ADDR <= WR1_MAX_ADDR;
            rWR1_LENGTH   <= WR1_LENGTH;

            rRD1_BASE     <= RD1_ADDR;
            rRD1_ADDR     <= RD1_ADDR;
            rRD1_MAX_ADDR <= RD1_MAX_ADDR;
            rRD1_LENGTH   <= RD1_LENGTH;

            rWR2_ADDR     <= WR2_ADDR;
            rRD2_ADDR     <= RD2_ADDR;
            rWR2_MAX_ADDR <= WR2_MAX_ADDR;
            rRD2_MAX_ADDR <= RD2_MAX_ADDR;
            rWR2_LENGTH   <= WR2_LENGTH;
            rRD2_LENGTH   <= RD2_LENGTH;

            inWR1_ADDR_q    <= WR1_ADDR;
            inWR1_MAX_q     <= WR1_MAX_ADDR;
            inWR1_LEN_q     <= WR1_LENGTH;
            wr1_cfg_pending <= 1'b0;
            wr1_addr_pend   <= WR1_ADDR;
            wr1_max_pend    <= WR1_MAX_ADDR;
            wr1_len_pend    <= WR1_LENGTH;

            inRD1_ADDR_q    <= RD1_ADDR;
            inRD1_MAX_q     <= RD1_MAX_ADDR;
            inRD1_LEN_q     <= RD1_LENGTH;
            rd1_cfg_pending <= 1'b0;
            rd1_addr_pend   <= RD1_ADDR;
            rd1_max_pend    <= RD1_MAX_ADDR;
            rd1_len_pend    <= RD1_LENGTH;

        end else begin
            if ((WR1_ADDR != inWR1_ADDR_q) || (WR1_MAX_ADDR != inWR1_MAX_q) || (WR1_LENGTH != inWR1_LEN_q)) begin
                inWR1_ADDR_q    <= WR1_ADDR;
                inWR1_MAX_q     <= WR1_MAX_ADDR;
                inWR1_LEN_q     <= WR1_LENGTH;
                wr1_addr_pend   <= WR1_ADDR;
                wr1_max_pend    <= WR1_MAX_ADDR;
                wr1_len_pend    <= WR1_LENGTH;
                wr1_cfg_pending <= 1'b1;
            end

            if ((RD1_ADDR != inRD1_ADDR_q) || (RD1_MAX_ADDR != inRD1_MAX_q) || (RD1_LENGTH != inRD1_LEN_q)) begin
                inRD1_ADDR_q    <= RD1_ADDR;
                inRD1_MAX_q     <= RD1_MAX_ADDR;
                inRD1_LEN_q     <= RD1_LENGTH;
                rd1_addr_pend   <= RD1_ADDR;
                rd1_max_pend    <= RD1_MAX_ADDR;
                rd1_len_pend    <= RD1_LENGTH;
                rd1_cfg_pending <= 1'b1;
            end

            if (WR1_LOAD) begin
                rWR1_BASE     <= WR1_ADDR;
                rWR1_ADDR     <= WR1_ADDR;
                rWR1_MAX_ADDR <= WR1_MAX_ADDR;
                rWR1_LENGTH   <= WR1_LENGTH;
                wr1_cfg_pending <= 1'b0;
            end else if (wr1_cfg_pending &&
                         (write_side_fifo_rusedw1 == 11'd0) &&
                         (Write == 1'b0) && (WR_MASK == 2'b00) && (mWR == 1'b0) && (ST == 10'd0)) begin
                rWR1_BASE     <= wr1_addr_pend;
                rWR1_ADDR     <= wr1_addr_pend;
                rWR1_MAX_ADDR <= wr1_max_pend;
                rWR1_LENGTH   <= wr1_len_pend;
                wr1_cfg_pending <= 1'b0;
            end else if (mWR_DONE && WR_MASK[0]) begin
                if (rWR1_ADDR < rWR1_MAX_ADDR - rWR1_LENGTH)
                    rWR1_ADDR <= rWR1_ADDR + rWR1_LENGTH;
                else
                    rWR1_ADDR <= rWR1_BASE;
            end

            if (RD1_LOAD) begin
                rRD1_BASE     <= RD1_ADDR;
                rRD1_ADDR     <= RD1_ADDR;
                rRD1_MAX_ADDR <= RD1_MAX_ADDR;
                rRD1_LENGTH   <= RD1_LENGTH;
                rd1_cfg_pending <= 1'b0;
            end else if (rd1_cfg_pending &&
                         (read_side_fifo_wusedw1 == 11'd0) &&
                         (Read == 1'b0) && (RD_MASK == 2'b00) && (mRD == 1'b0) && (ST == 10'd0)) begin
                rRD1_BASE     <= rd1_addr_pend;
                rRD1_ADDR     <= rd1_addr_pend;
                rRD1_MAX_ADDR <= rd1_max_pend;
                rRD1_LENGTH   <= rd1_len_pend;
                rd1_cfg_pending <= 1'b0;
            end else if (mRD_DONE && RD_MASK[0]) begin
                if (rRD1_ADDR < rRD1_MAX_ADDR - rRD1_LENGTH)
                    rRD1_ADDR <= rRD1_ADDR + rRD1_LENGTH;
                else
                    rRD1_ADDR <= rRD1_BASE;
            end
        end
    end

    //==================================================
    // 11) 自动读写调度
    //     - 空闲时优先检查写 FIFO 是否达到突发阈值
    //     - 否则检查读 FIFO 是否低于阈值，触发一次读突发补充数据
    //==================================================
    always@(posedge CLK or negedge RESET_N) begin
        if (!RESET_N) begin
            mWR     <= 0;
            mRD     <= 0;
            mADDR   <= 0;
            mLENGTH <= 0;
            RD_MASK <= 0;
            WR_MASK <= 0;
        end else begin
            if ( (mWR==0) && (mRD==0) && (ST==0) &&
                 (WR_MASK==0) && (RD_MASK==0) &&
                 (WR1_LOAD==0) && (RD1_LOAD==0)
            ) begin
                if ( (write_side_fifo_rusedw1 >= rWR1_LENGTH) && (rWR1_LENGTH!=0) ) begin
                    mADDR   <= rWR1_ADDR;
                    mLENGTH <= rWR1_LENGTH;
                    WR_MASK <= 2'b01;
                    RD_MASK <= 2'b00;
                    mWR     <= 1;
                    mRD     <= 0;
                end
                else if ( (read_side_fifo_wusedw1 < rRD1_LENGTH) ) begin
                    mADDR   <= rRD1_ADDR;
                    mLENGTH <= rRD1_LENGTH;
                    WR_MASK <= 2'b00;
                    RD_MASK <= 2'b01;
                    mWR     <= 0;
                    mRD     <= 1;
                end
            end

            if (mRD_DONE) begin
                RD_MASK <= 0;
                mRD     <= 0;
            end else if (mWR_DONE) begin
                WR_MASK <= 0;
                mWR     <= 0;
            end
        end
    end

endmodule
