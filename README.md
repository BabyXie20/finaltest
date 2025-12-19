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
- **`veh_req_latch.v`**：车辆请求锁存模块（`veh_req_latch`）。
- **`vga_anim_phase.v`**：VGA 动画相位生成（帧/秒步进）。
- **`vga_sync_640x480.v`**：VGA 640x480@60Hz 时序发生器。
- **`violation_det.v`**：闯红灯检测（进入边界时红灯锁存）。

## `V/` 目录 `.v` 文件
- **`V/D8M_LUT.v`**：D8M 摄像头像素查找/处理模块（`D8M_LUT`）。
- **`V/FpsMonitor.v`**：帧率监视模块（`FpsMonitor`）。
- **`V/I2C_READ_DATA.v`**：I2C 读数据模块（`I2C_READ_DATA`）。
- **`V/I2C_RESET_DELAY.v`**：I2C 复位延时模块（`I2C_RESET_DELAY`）。
- **`V/I2C_WRITE_PTR.v`**：I2C 写指针模块（`I2C_WRITE_PTR`）。
- **`V/I2C_WRITE_WDATA.v`**：I2C 写数据模块（`I2C_WRITE_WDATA`）。
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
- **`V_D8M/FRM_COUNTER.v`**：帧计数器（`FRM_COUNTER`）。
- **`V_D8M/G_GAIN.v`**：LPM_CONSTANT 常量（增益）。
- **`V_D8M/G_GAIN_bb.v`**：LPM_CONSTANT 黑盒声明。
- **`V_D8M/Line_Buffer_J.v`**：行缓冲模块（`Line_Buffer_J`）。
- **`V_D8M/MIPI_BRIDGE_CAMERA_Config.v`**：MIPI/Camera I2C 配置模块（`MIPI_BRIDGE_CAMERA_Config`）。
- **`V_D8M/MIPI_BRIDGE_CONFIG.v`**：MIPI 桥配置模块（`MIPI_BRIDGE_CONFIG`）。
- **`V_D8M/MIPI_CAMERA_CONFIG.v`**：摄像头配置模块（`MIPI_CAMERA_CONFIG`）。
- **`V_D8M/ON_CHIP_FRAM.v`**：片上帧缓存模块（`ON_CHIP_FRAM`）。
- **`V_D8M/RAM_READ_COUNTER.v`**：RAW TO RGB 读计数模块（`RAM_READ_COUNTER`）。
- **`V_D8M/RAW2RGB_J.v`**：RAW Bayer → RGB 输出模块（行缓冲/插值/坐标对齐）。
- **`V_D8M/RAW2RGB_J.v.bak`**：RAW2RGB 旧版模块（`RAW2RGB_J` 备份）。
- **`V_D8M/RAW_RGB_BIN.v`**：RAW 解码模块（`RAW_RGB_BIN`）。
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
- **`V_Auto/AUTO_FOCUS_ON.v`**：自动对焦触发模块（`AUTO_FOCUS_ON`）。
- **`V_Auto/AUTO_SYNC_MODIFY.v`**：自动同步修改模块（`AUTO_SYNC_MODIFY`）。
- **`V_Auto/CLOCKMEM.v`**：1Hz 时钟生成模块（`CLOCKMEM`）。
- **`V_Auto/FOCUS_ADJ.v`**：自动对焦调整模块（`FOCUS_ADJ`）。
- **`V_Auto/F_VCM.v`**：VCM 控制相关模块（`F_VCM`）。
- **`V_Auto/I2C_DELAY.v`**：I2C 延时模块（`I2C_DELAY`）。
- **`V_Auto/LCD_COUNTER.v`**：行场计数模块（`LCD_COUNTER`）。
- **`V_Auto/MODIFY_SYNC.v`**：同步修改模块（`MODIFY_SYNC`）。
- **`V_Auto/RESET_DELAY.v`**：复位延时模块（`RESET_DELAY`）。
- **`V_Auto/VCM_CTRL_P.v`**：VCM 控制模块（`VCM_CTRL_P`）。
- **`V_Auto/VCM_I2C.v`**：VCM I2C 通信模块（`VCM_I2C`）。
- **`V_Auto/VCM_STEP.v`**：VCM 步进模块（`VCM_STEP`）。
- **`V_Auto/VCM_TEST.v`**：VCM 测试模块（`VCM_TEST`）。

## `.c` 文件
- 未发现 `.c` 文件。
