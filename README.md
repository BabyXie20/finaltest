# finaltest 交通灯工程 README

本 README 仅基于仓库内 `.v`、`.c`、`.h` 文件的**开头注释或首行内容**整理（本工程中仅存在 `.v` 与少量 `.h`，未发现 `.c` 文件）。顶层为 `systemtop.v`。

## 顶层模块
- **`systemtop.v`**：板级顶层（DE1/类似平台）。提供 640x480 VGA 十字路口交通灯场景；摄像头画中画经 SDRAM 缓存和 RAW2RGB 转换后缩放至 200x150，并叠加至右下角；PIP 模块输出 25MHz VGA 像素时钟。

## 根目录 `.v` 文件
- **`ScaleBuf200x150.v`**：640x480 像素流缩放缓存到 200x150，双缓冲读出。
- **`boom_gen.v`**：违规触发后的爆炸/闪光强度生成器。
- **`car_pos_ctrl.v`**：四方向车辆坐标更新与回绕。
- **`clk_div_sec.v`**：时钟分频/节拍模块（1s tick、25MHz 像素时钟、车辆节拍）。
- **`crossroad_pattern.v`**：VGA 场景渲染（十字路口、人行道、斑马线、信号灯、HUD 等）。
- **`gpio_io_pack.v`**：交通灯/超声波 GPIO 引脚打包与映射。
- **`hcsr04_2ch_scheduler.v`**：双通道 HC-SR04 测距调度器。
- **`hcsr04_ped.v`**：HC-SR04 测距行人触发（回波判定、请求保持）。
- **`hex7seg.v`**：7 段数码管译码显示。
- **`ped_walk_ctrl.v`**：行人斑马线行走/动画控制（像素时钟域）。
- **`ped_walk_once_dir.v`**：行人单次走完整趟控制。
- **`pip_cam_200x150.v`**：摄像头画中画输出（RAW→SDRAM→RAW2RGB→缩放叠加）。
- **`ps2.v`**：PS/2 接收器。
- **`ps2_keyboard.v`**：PS/2 扫描码解析。
- **`reset_soft_n.v`**：硬复位键 + 软件触发复位合成。
- **`time_splitter.v`**：倒计时显示拆分（NS/EW 十位/个位与模式显示）。
- **`tlc_core_stage1.v`**：交通灯控制核心（固定/感应/夜间/封禁模式，含行人覆盖）。
- **`veh_req_latch.v`**：无文件头注释（模块 `veh_req_latch`）。
- **`vga_anim_phase.v`**：VGA 动画相位生成（帧/秒步进）。
- **`vga_sync_640x480.v`**：VGA 640x480@60Hz 时序发生器。
- **`violation_det.v`**：闯红灯检测（进入边界时红灯锁存）。

## `V/` 目录 `.v` 文件
- **`V/D8M_LUT.v`**：无文件头注释（模块 `D8M_LUT`）。
- **`V/FpsMonitor.v`**：无文件头注释（模块 `FpsMonitor`）。
- **`V/I2C_READ_DATA.v`**：无文件头注释（模块 `I2C_READ_DATA`）。
- **`V/I2C_RESET_DELAY.v`**：无文件头注释（模块 `I2C_RESET_DELAY`）。
- **`V/I2C_WRITE_PTR.v`**：无文件头注释（模块 `I2C_WRITE_PTR`）。
- **`V/I2C_WRITE_WDATA.v`**：无文件头注释（模块 `I2C_WRITE_WDATA`）。
- **`V/MIPI_PLL.v`**：Altera PLL 生成文件（MIPI_PLL）。
- **`V/Reset_Delay_DRAM.v`**：Terasic 版权的复位延时模块说明。
- **`V/SDRAM_PLL.v`**：Altera PLL 生成文件（SDRAM_PLL）。
- **`V/MIPI_PLL/MIPI_PLL_0002.v`**：PLL 实例文件。
- **`V/SDRAM_PLL/SDRAM_PLL_0002.v`**：PLL 实例文件。

## `V_D8M/` 目录 `.v` 文件
- **`V_D8M/B_GAIN.v`**：LPM_CONSTANT 常量（增益）。
- **`V_D8M/B_GAIN_bb.v`**：LPM_CONSTANT 黑盒声明。
- **`V_D8M/FRAM_BUFF.v`**：altsyncram 双口 RAM。
- **`V_D8M/FRAM_BUFF_bb.v`**：altsyncram 黑盒声明。
- **`V_D8M/FRM_COUNTER.v`**：无文件头注释（帧计数器）。
- **`V_D8M/G_GAIN.v`**：LPM_CONSTANT 常量（增益）。
- **`V_D8M/G_GAIN_bb.v`**：LPM_CONSTANT 黑盒声明。
- **`V_D8M/Line_Buffer_J.v`**：无文件头注释（行缓冲）。
- **`V_D8M/MIPI_BRIDGE_CAMERA_Config.v`**：无文件头注释（MIPI/Camera I2C 配置）。
- **`V_D8M/MIPI_BRIDGE_CONFIG.v`**：无文件头注释（MIPI 桥配置）。
- **`V_D8M/MIPI_CAMERA_CONFIG.v`**：无文件头注释（摄像头配置）。
- **`V_D8M/ON_CHIP_FRAM.v`**：无文件头注释（片上帧缓存）。
- **`V_D8M/RAM_READ_COUNTER.v`**：开头注释“RAW TO RGB”。
- **`V_D8M/RAW2RGB_J.v`**：RAW Bayer → RGB 输出模块（行缓冲/插值/坐标对齐）。
- **`V_D8M/RAW2RGB_J.v.bak`**：无文件头注释（RAW2RGB 旧版）。
- **`V_D8M/RAW_RGB_BIN.v`**：无文件头注释（RAW 解码）。
- **`V_D8M/int_line.v`**：altsyncram 双口 RAM。
- **`V_D8M/int_line_bb.v`**：altsyncram 黑盒声明。

## `V_Sdram_Control/` 目录 `.v` 与 `.h` 文件
- **`V_Sdram_Control/Sdram_Control.v`**：SDRAM 顶层控制器（多通道读写、FIFO、动态切换）。
- **`V_Sdram_Control/Sdram_RD_FIFO.v`**：dcfifo megafunction。
- **`V_Sdram_Control/Sdram_RD_FIFO_bb.v`**：dcfifo 黑盒声明。
- **`V_Sdram_Control/Sdram_WR_FIFO.v`**：dcfifo megafunction。
- **`V_Sdram_Control/Sdram_WR_FIFO_bb.v`**：dcfifo 黑盒声明。
- **`V_Sdram_Control/command.v`**：Terasic 版权说明（SDRAM 控制组件）。
- **`V_Sdram_Control/control_interface.v`**：Terasic 版权说明（SDRAM 控制接口）。
- **`V_Sdram_Control/sdr_data_path.v`**：Terasic 版权说明（SDRAM 数据通路）。
- **`V_Sdram_Control/Sdram_Params.h`**：SDRAM 地址/总线参数宏定义。

## `V_Auto/` 目录 `.v` 文件
- **`V_Auto/AUTO_FOCUS_ON.v`**：无文件头注释（自动对焦触发）。
- **`V_Auto/AUTO_SYNC_MODIFY.v`**：开头注释“AUTO SYNC_TO_NS”。
- **`V_Auto/CLOCKMEM.v`**：无文件头注释（1Hz 生成）。
- **`V_Auto/FOCUS_ADJ.v`**：开头注释“AutoFous”。
- **`V_Auto/F_VCM.v`**：无文件头注释（VCM 相关）。
- **`V_Auto/I2C_DELAY.v`**：无文件头注释（I2C 延时）。
- **`V_Auto/LCD_COUNTER.v`**：无文件头注释（行场计数）。
- **`V_Auto/MODIFY_SYNC.v`**：无文件头注释（同步修改）。
- **`V_Auto/RESET_DELAY.v`**：无文件头注释（复位延时）。
- **`V_Auto/VCM_CTRL_P.v`**：无文件头注释（VCM 控制）。
- **`V_Auto/VCM_I2C.v`**：无文件头注释（VCM I2C）。
- **`V_Auto/VCM_STEP.v`**：无文件头注释（VCM 步进）。
- **`V_Auto/VCM_TEST.v`**：无文件头注释（VCM 测试）。

## `.c` 文件
- 未发现 `.c` 文件。
