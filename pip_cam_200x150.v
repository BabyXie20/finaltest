//======================================================================
// File Name : pip_cam_200x150.v
// Function  : 摄像头画中画输出模块
//             - 从 MIPI 摄像头采集 640x480 RAW 数据写入 SDRAM
//             - 从 SDRAM 读取 640x480 数据并做 RAW2RGB
//             - 将全幅图像缩放到 200x150，并叠加到 VGA 画面的右下角窗口
//             - 可选启用对焦处理模块，对画中画结果做对焦相关处理
//             - 通过跨时钟域帧同步脉冲，使 SDRAM 读写在帧边界对齐，减少撕裂
//
// Inputs/Outputs:
//   Inputs : CLOCK2_50, CLOCK3_50, CLOCK4_50, CLOCK_50
//            rst_n_key
//            vga_x, vga_y, video_on, vga_hs, vga_vs
//            auto_foc_en, sw_fuc_line, sw_fuc_all_cen
//            MIPI_PIXEL_CLK, MIPI_PIXEL_D, MIPI_PIXEL_HS, MIPI_PIXEL_VS
//   Outputs: pip_de, pip_r, pip_g, pip_b
//            VGA_CLK_25, VGA_SYNC_N, VGA_BLANK_N
//            SDRAM signals
//            camera and MIPI I2C and control signals
//            I2C_RELEASE, READY_AF
//
// Parameters:
//   SRC_W, SRC_H : 采集源分辨率
//   DST_W, DST_H : 画中画输出分辨率
//   PIP_X_S      : 画中画窗口左上角 X 坐标
//   PIP_Y_S      : 画中画窗口左上角 Y 坐标
//   USE_FOCUS    : 是否启用对焦处理通路
//======================================================================

module pip_cam_200x150 #(
    parameter integer SRC_W = 640,
    parameter integer SRC_H = 480,
    parameter integer DST_W = 200,
    parameter integer DST_H = 150,

    parameter integer PIP_X_S = (640 - 200),
    parameter integer PIP_Y_S = (480 - 150),

    parameter integer USE_FOCUS = 1
)(
    input                    CLOCK2_50,
    input                    CLOCK3_50,
    input                    CLOCK4_50,
    input                    CLOCK_50,

    input                    rst_n_key,

    input      [9:0]         vga_x,
    input      [9:0]         vga_y,
    input                    video_on,
    input                    vga_hs,
    input                    vga_vs,

    input                    auto_foc_en,
    input                    sw_fuc_line,
    input                    sw_fuc_all_cen,

    output                   pip_de,
    output     [7:0]         pip_r,
    output     [7:0]         pip_g,
    output     [7:0]         pip_b,

    output                   VGA_CLK_25,
    output                   VGA_SYNC_N,
    output                   VGA_BLANK_N,

    output     [12:0]        DRAM_ADDR,
    output     [1:0]         DRAM_BA,
    output                   DRAM_CAS_N,
    output                   DRAM_CKE,
    output                   DRAM_CLK,
    output                   DRAM_CS_N,
    inout      [15:0]        DRAM_DQ,
    output                   DRAM_LDQM,
    output                   DRAM_RAS_N,
    output                   DRAM_UDQM,
    output                   DRAM_WE_N,

    inout                    CAMERA_I2C_SCL,
    inout                    CAMERA_I2C_SDA,
    output                   CAMERA_PWDN_n,
    output                   MIPI_CS_n,
    inout                    MIPI_I2C_SCL,
    inout                    MIPI_I2C_SDA,
    output                   MIPI_MCLK,
    input                    MIPI_PIXEL_CLK,
    input      [9:0]         MIPI_PIXEL_D,
    input                    MIPI_PIXEL_HS,
    input                    MIPI_PIXEL_VS,
    output                   MIPI_REFCLK,
    output                   MIPI_RESET_n,

    output                   I2C_RELEASE,
    output                   READY_AF
);

    //==================================================
    // 1) 固定控制脚
    //==================================================
    assign CAMERA_PWDN_n = 1'b1;
    assign MIPI_CS_n     = 1'b0;

    //==================================================
    // 2) 复位延时与分级复位
    //==================================================
    wire RESET_N, RESET_N_DELAY;
    RESET_DELAY u_rst_delay(
        .RESET_N ( rst_n_key ),
        .CLK     ( CLOCK3_50 ),
        .READY0  ( RESET_N ),
        .READY1  ( RESET_N_DELAY )
    );

    wire DLY_RST_0, DLY_RST_1, DLY_RST_2;
    Reset_Delay_DRAM u_rst_dram(
        .iCLK   ( CLOCK4_50 ),
        .iRST   ( rst_n_key ),
        .oRST_0 ( DLY_RST_0 ),
        .oRST_1 ( DLY_RST_1 ),
        .oRST_2 ( DLY_RST_2 )
    );

    //==================================================
    // 3) 时钟生成
    //    - MIPI_REFCLK 与 VGA_CLK_25 由同一 PLL 产生
    //    - SDRAM_CTRL_CLK 与 DRAM_CLK 由 SDRAM_PLL 产生
    //==================================================
    MIPI_PLL u_pll_mipi(
        .refclk   ( CLOCK_50 ),
        .rst      ( 1'b0 ),
        .outclk_0 ( MIPI_REFCLK ),
        .outclk_1 ( VGA_CLK_25 )
    );
    assign MIPI_MCLK    = MIPI_REFCLK;
    assign MIPI_RESET_n = RESET_N;

    wire SDRAM_CTRL_CLK;
    SDRAM_PLL u_pll_sdram(
        .refclk   ( CLOCK2_50 ),
        .rst      ( 1'b0 ),
        .outclk_1 ( DRAM_CLK ),
        .outclk_0 ( SDRAM_CTRL_CLK ),
        .locked   ( )
    );

    // VGA 固定输出脚
    assign VGA_SYNC_N  = 1'b0;
    assign VGA_BLANK_N = video_on;

    //==================================================
    // 4) MIPI 桥与摄像头配置
    //    - 配置模块使用 MIPI I2C，总线释放后再交给自动对焦模块使用
    //==================================================
    wire CAMERA_I2C_SCL_MIPI;
    wire CAMERA_I2C_SCL_AF;
    wire CAMERA_MIPI_RELAESE;
    wire MIPI_BRIDGE_RELEASE;
    wire VCM_RELAESE;
    wire AUTO_FOC;

    MIPI_BRIDGE_CAMERA_Config u_mipi_cfg(
        .RESET_N            ( DLY_RST_0 ),
        .CLK_50             ( CLOCK4_50 ),
        .MIPI_I2C_SCL       ( MIPI_I2C_SCL ),
        .MIPI_I2C_SDA       ( MIPI_I2C_SDA ),
        .MIPI_I2C_RELEASE   ( MIPI_BRIDGE_RELEASE ),
        .CAMERA_I2C_SCL     ( CAMERA_I2C_SCL_MIPI ),
        .CAMERA_I2C_SDA     ( CAMERA_I2C_SDA ),
        .CAMERA_I2C_RELAESE ( CAMERA_MIPI_RELAESE ),
        .VCM_RELAESE        ( VCM_RELAESE )
    );

    assign I2C_RELEASE   = CAMERA_MIPI_RELAESE & MIPI_BRIDGE_RELEASE;
    assign CAMERA_I2C_SCL = (I2C_RELEASE) ? CAMERA_I2C_SCL_AF : CAMERA_I2C_SCL_MIPI;

    AUTO_FOCUS_ON u_af_on(
        .CLK_50      ( CLOCK4_50 ),
        .I2C_RELEASE ( I2C_RELEASE ),
        .AUTO_FOC    ( AUTO_FOC )
    );

    //==================================================
    // 5) 跨时钟域帧同步信号
    //    - 摄像头域用 VS 边沿翻转 cam_tgl
    //    - VGA 域用左上角可视点翻转 vga_tgl
    //    - 在 SDRAM_CTRL_CLK 域做双触发同步并异或得到单周期脉冲
    //==================================================
    reg cam_vs_d;
    reg cam_tgl;
    always @(posedge MIPI_PIXEL_CLK or negedge rst_n_key) begin
        if (!rst_n_key) begin
            cam_vs_d <= 1'b1;
            cam_tgl  <= 1'b0;
        end else begin
            cam_vs_d <= MIPI_PIXEL_VS;
            if (cam_vs_d && !MIPI_PIXEL_VS) begin
                cam_tgl <= ~cam_tgl;
            end
        end
    end

    wire vga_sof = (vga_x == 10'd0) && (vga_y == 10'd0) && video_on;
    reg  vga_tgl;
    always @(posedge VGA_CLK_25 or negedge rst_n_key) begin
        if (!rst_n_key) vga_tgl <= 1'b0;
        else if (vga_sof) vga_tgl <= ~vga_tgl;
    end

    reg cam_tgl_s0, cam_tgl_s1;
    reg vga_tgl_s0, vga_tgl_s1;
    always @(posedge SDRAM_CTRL_CLK or negedge rst_n_key) begin
        if (!rst_n_key) begin
            cam_tgl_s0 <= 1'b0; cam_tgl_s1 <= 1'b0;
            vga_tgl_s0 <= 1'b0; vga_tgl_s1 <= 1'b0;
        end else begin
            cam_tgl_s0 <= cam_tgl;   cam_tgl_s1 <= cam_tgl_s0;
            vga_tgl_s0 <= vga_tgl;   vga_tgl_s1 <= vga_tgl_s0;
        end
    end

    wire cam_frame_pulse_sdram = (cam_tgl_s0 ^ cam_tgl_s1);
    wire vga_frame_pulse_sdram = (vga_tgl_s0 ^ vga_tgl_s1);

    //==================================================
    // 6) SDRAM 流式读写
    //    - 写端来自 MIPI_PIXEL 域
    //    - 读端在 VGA_CLK_25 域输出给 RAW2RGB
    //    - WR1_LOAD 与 RD1_LOAD 在初始化和每帧对齐时触发
    //==================================================
    wire READ_Request = video_on;

    wire [9:0] RD_DATA;

    wire WR1_LOAD_PULSE = (~I2C_RELEASE) | cam_frame_pulse_sdram;
    wire RD1_LOAD_PULSE = (~I2C_RELEASE) | vga_frame_pulse_sdram;

    Sdram_Control u_sdram(
        .RESET_N      ( rst_n_key ),
        .CLK          ( SDRAM_CTRL_CLK ),

        .WR1_DATA     ( MIPI_PIXEL_D[9:0] ),
        .WR1          ( MIPI_PIXEL_HS & MIPI_PIXEL_VS ),
        .WR1_ADDR     ( 0 ),
        .WR1_MAX_ADDR ( SRC_W*SRC_H ),
        .WR1_LENGTH   ( 11'd256 ),
        .WR1_LOAD     ( WR1_LOAD_PULSE ),
        .WR1_CLK      ( MIPI_PIXEL_CLK ),

        .RD1_DATA     ( RD_DATA[9:0] ),
        .RD1          ( READ_Request ),
        .RD1_ADDR     ( 0 ),
        .RD1_MAX_ADDR ( SRC_W*SRC_H ),
        .RD1_LENGTH   ( 11'd256 ),
        .RD1_LOAD     ( RD1_LOAD_PULSE ),
        .RD1_CLK      ( VGA_CLK_25 ),

        .SA           ( DRAM_ADDR ),
        .BA           ( DRAM_BA ),
        .CS_N         ( DRAM_CS_N ),
        .CKE          ( DRAM_CKE ),
        .RAS_N        ( DRAM_RAS_N ),
        .CAS_N        ( DRAM_CAS_N ),
        .WE_N         ( DRAM_WE_N ),
        .DQ           ( DRAM_DQ ),
        .DQM          ( {DRAM_UDQM, DRAM_LDQM} )
    );

    //==================================================
    // 7) RAW 转 RGB
    //==================================================
    wire [7:0] RED, GREEN, BLUE;
    wire       raw_dval;

    RAW2RGB_J u_raw2rgb(
        .RST          ( vga_vs ),
        .CCD_PIXCLK   ( VGA_CLK_25 ),
        .mCCD_DATA    ( RD_DATA[9:0] ),
        .VGA_CLK      ( VGA_CLK_25 ),
        .READ_Request ( READ_Request ),
        .VGA_VS       ( vga_vs ),
        .VGA_HS       ( vga_hs ),
        .oRed         ( RED ),
        .oGreen       ( GREEN ),
        .oBlue        ( BLUE ),
        .oDVAL        ( raw_dval )
    );

    //==================================================
    // 8) 源坐标计数
    //    - 利用 raw_dval 的行有效边界生成 src_x 与 src_y
    //==================================================
    reg  [10:0] src_x, src_y;
    reg         dval_d;
    reg         vs_d;

    always @(posedge VGA_CLK_25 or negedge rst_n_key) begin
        if (!rst_n_key) begin
            src_x  <= 11'd0;
            src_y  <= 11'd0;
            dval_d <= 1'b0;
            vs_d   <= 1'b1;
        end else begin
            dval_d <= raw_dval;
            vs_d   <= vga_vs;

            if (vs_d && !vga_vs) begin
                src_x <= 11'd0;
                src_y <= 11'd0;
            end else begin
                if (raw_dval && !dval_d) begin
                    src_x <= 11'd0;
                end else if (raw_dval) begin
                    src_x <= src_x + 11'd1;
                end

                if (!raw_dval && dval_d) begin
                    src_y <= src_y + 11'd1;
                end
            end
        end
    end

    //==================================================
    // 9) 画中画窗口几何
    //==================================================
    wire win_active =
        video_on &&
        (vga_x >= PIP_X_S[9:0]) && (vga_x < (PIP_X_S + DST_W)) &&
        (vga_y >= PIP_Y_S[9:0]) && (vga_y < (PIP_Y_S + DST_H));

    wire [7:0] win_x = vga_x[7:0] - PIP_X_S[7:0];
    wire [7:0] win_y = vga_y[7:0] - PIP_Y_S[7:0];

    wire frame_start_pulse = (vga_x == 10'd0) && (vga_y == 10'd0) && video_on;

    wire [9:0] inR10 = {RED,   2'b00};
    wire [9:0] inG10 = {GREEN, 2'b00};
    wire [9:0] inB10 = {BLUE,  2'b00};

    //==================================================
    // 10) 缩放与缓存
    //     - 输入为全幅像素流与源坐标
    //     - 输出为窗口内的 200x150 像素流
    //==================================================
    wire        win_de;
    wire [9:0]  winR10, winG10, winB10;

    ScaleBuf200x150 u_scale(
        .clk        ( VGA_CLK_25 ),
        .rst_n      ( rst_n_key ),

        .frame_start( frame_start_pulse ),

        .pix_valid  ( raw_dval ),
        .sx         ( src_x ),
        .sy         ( src_y ),
        .in_r       ( inR10 ),
        .in_g       ( inG10 ),
        .in_b       ( inB10 ),

        .win_active ( win_active ),
        .win_x      ( win_x ),
        .win_y      ( win_y ),

        .out_valid  ( win_de ),
        .out_r      ( winR10 ),
        .out_g      ( winG10 ),
        .out_b      ( winB10 )
    );

    wire [7:0] winR8 = winR10[9:2];
    wire [7:0] winG8 = winG10[9:2];
    wire [7:0] winB8 = winB10[9:2];

    //==================================================
    // 11) 可选对焦处理通路
    //==================================================
    wire [7:0] focR, focG, focB;

    FOCUS_ADJ u_focus(
        .CLK_50         ( CLOCK4_50 ),
        .RESET_N        ( I2C_RELEASE ),
        .RESET_SUB_N    ( I2C_RELEASE ),
        .AUTO_FOC       ( auto_foc_en & AUTO_FOC ),
        .SW_Y           ( 1'b0 ),
        .SW_H_FREQ      ( 1'b0 ),
        .SW_FUC_ALL_CEN ( sw_fuc_all_cen ),
        .SW_FUC_LINE    ( sw_fuc_line ),

        .VIDEO_HS       ( vga_hs ),
        .VIDEO_VS       ( vga_vs ),
        .VIDEO_CLK      ( VGA_CLK_25 ),
        .VIDEO_DE       ( win_de ),

        .iR             ( winR8 ),
        .iG             ( winG8 ),
        .iB             ( winB8 ),

        .oR             ( focR ),
        .oG             ( focG ),
        .oB             ( focB ),

        .READY          ( READY_AF ),
        .SCL            ( CAMERA_I2C_SCL_AF ),
        .SDA            ( CAMERA_I2C_SDA ),
        .STATUS         ( )
    );

    //==================================================
    // 12) 输出对齐与通路选择
    //     - 对 win 与 foc 输出做一拍对齐，保证 pip_de 与 RGB 同步
    //     - use_focus_now 控制是否使用对焦输出
    //==================================================
    reg        win_de_d1;
    reg [7:0]  winR_d1, winG_d1, winB_d1;
    reg [7:0]  focR_d1, focG_d1, focB_d1;

    always @(posedge VGA_CLK_25 or negedge rst_n_key) begin
        if (!rst_n_key) begin
            win_de_d1 <= 1'b0;
            winR_d1   <= 8'd0; winG_d1 <= 8'd0; winB_d1 <= 8'd0;
            focR_d1   <= 8'd0; focG_d1 <= 8'd0; focB_d1 <= 8'd0;
        end else begin
            win_de_d1 <= win_de;
            winR_d1   <= winR8;
            winG_d1   <= winG8;
            winB_d1   <= winB8;

            focR_d1   <= focR;
            focG_d1   <= focG;
            focB_d1   <= focB;
        end
    end

    wire use_focus_now = (USE_FOCUS != 0) && I2C_RELEASE;

    assign pip_de = win_de_d1;
    assign pip_r  = use_focus_now ? focR_d1 : winR_d1;
    assign pip_g  = use_focus_now ? focG_d1 : winG_d1;
    assign pip_b  = use_focus_now ? focB_d1 : winB_d1;

endmodule
