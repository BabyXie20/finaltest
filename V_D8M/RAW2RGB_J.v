//======================================================================
// File Name : RAW2RGB_J.v
// Function  : RAW Bayer 数据转 RGB 输出模块
//             - 以 READ_Request 作为有效像素区指示，生成与像素流对齐的 oDVAL
//             - 在 VGA_CLK 域内维护源坐标 src_x/src_y，并输出对齐后的 oX/oY
//             - 通过 Line_Buffer_J 形成 2 行抽头数据，用于 Bayer 插值/重建
//             - 通过 RAW_RGB_BIN 根据 (X,Y) 奇偶进行 Bayer 解码，输出 R/G/B 10bit
//             - 最终在 oDVAL 有效时输出 8bit RGB，否则输出 0
//
// Inputs/Outputs:
//   Inputs : mCCD_DATA
//            CCD_PIXCLK
//            RST
//            VGA_CLK
//            READ_Request
//            VGA_VS, VGA_HS
//   Outputs: oRed, oGreen, oBlue
//            oDVAL
//            oX, oY
//======================================================================

module RAW2RGB_J(
   input      [9:0]  mCCD_DATA,
   input             CCD_PIXCLK,
   input             RST,
   input             VGA_CLK,
   input             READ_Request,
   input             VGA_VS,
   input             VGA_HS,

   output     [7:0]  oRed,
   output     [7:0]  oGreen,
   output     [7:0]  oBlue,
   output            oDVAL,

   output reg [10:0] oX,
   output reg [10:0] oY
);

  //==================================================
  // 1) 行缓冲抽头与 RAW->RGB 中间信号
  //==================================================
  wire [9:0]  mDAT0_0, mDAT0_1;
  wire [9:0]  mCCD_R, mCCD_G, mCCD_B;

  //==================================================
  // 2) 源坐标与有效区边沿检测
  //    - src_x 在每行有效区内递增
  //    - src_y 在行结束时递增
  //    - req_d 用于检测 READ_Request 上升沿/下降沿
  //==================================================
  reg  [10:0] src_x, src_y;
  reg         req_d;

  //==================================================
  // 3) 输出对齐打一拍
  //    - dval_d1 作为 oDVAL，保证与 oX/oY 同步
  //==================================================
  reg         dval_d1;

  //==================================================
  // 4) 坐标与有效信号生成
  //    - 以 VGA_VS 作为帧复位信号，帧开始时清零坐标
  //    - 行起点用 READ_Request 上升沿识别
  //    - 行终点用 READ_Request 下降沿识别
  //==================================================
  always @(posedge VGA_CLK or negedge VGA_VS) begin
    if (!VGA_VS) begin
      src_x   <= 11'd0;
      src_y   <= 11'd0;
      req_d   <= 1'b0;

      dval_d1 <= 1'b0;
      oX      <= 11'd0;
      oY      <= 11'd0;
    end else begin
      req_d <= READ_Request;

      if (READ_Request && !req_d) begin
        src_x <= 11'd0;
      end else if (READ_Request) begin
        src_x <= src_x + 11'd1;
      end

      if (!READ_Request && req_d) begin
        src_y <= src_y + 11'd1;
      end

      dval_d1 <= READ_Request;
      oX      <= src_x;
      oY      <= src_y;
    end
  end

  assign oDVAL  = dval_d1;

  //==================================================
  // 5) RGB 输出裁剪与门控
  //    - 10bit -> 8bit 取高位
  //    - oDVAL 无效时输出清零
  //==================================================
  assign oRed   = oDVAL ? mCCD_R[9:2] : 8'd0;
  assign oGreen = oDVAL ? mCCD_G[9:2] : 8'd0;
  assign oBlue  = oDVAL ? mCCD_B[9:2] : 8'd0;

  //==================================================
  // 6) 行缓冲
  //    - 使用 READ_Request 作为行有效写入使能，避免无效区写入干扰
  //==================================================
  Line_Buffer_J u0 (
    .CCD_PIXCLK    ( VGA_CLK ),
    .mCCD_FVAL     ( VGA_VS ),
    .mCCD_LVAL     ( READ_Request ),
    .X_Cont        ( src_x ),
    .mCCD_DATA     ( mCCD_DATA ),
    .VGA_CLK       ( VGA_CLK ),
    .READ_Request  ( READ_Request ),
    .VGA_VS        ( VGA_VS ),
    .READ_Cont     ( src_x ),
    .V_Cont        ( src_y ),
    .taps0x        ( mDAT0_1 ),
    .taps1x        ( mDAT0_0 )
  );

  //==================================================
  // 7) Bayer 解码
  //    - 使用 X/Y 奇偶决定当前像素的 Bayer 位置
  //    - 输出 10bit R/G/B
  //==================================================
  RAW_RGB_BIN bin (
    .CLK    ( VGA_CLK ),
    .RST_N  ( RST ),
    .D0     ( mDAT0_0 ),
    .D1     ( mDAT0_1 ),
    .X      ( src_x[0] ),
    .Y      ( src_y[0] ),
    .B      ( mCCD_R ),
    .G      ( mCCD_G ),
    .R      ( mCCD_B )
  );

endmodule
