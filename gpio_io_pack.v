//======================================================================
// File Name : gpio_io_pack.v
// Function  : GPIO 引脚打包/映射模块
//             - 将交通灯状态（NS/EW 的 R/Y/G）映射到 GPIO_1[0..5] 作为输出
//             - 将两路 HC-SR04 超声波模块 TRIG 映射到 GPIO_1[6..7] 作为输出
//             - 从 GPIO_1[8..9] 读取两路 HC-SR04 的 ECHO 信号作为输入输出到内部逻辑
//
// Inputs/Outputs:
//   inout  [9:0] GPIO_1
//     - GPIO_1[0] : 输出 NS_R（南北向红灯）
//     - GPIO_1[1] : 输出 NS_G（南北向绿灯）
//     - GPIO_1[2] : 输出 NS_Y（南北向黄灯）
//     - GPIO_1[3] : 输出 EW_R（东西向红灯）
//     - GPIO_1[4] : 输出 EW_G（东西向绿灯）
//     - GPIO_1[5] : 输出 EW_Y（东西向黄灯）
//     - GPIO_1[6] : 输出 hcsr_ns_trig（NS 方向超声波 TRIG）
//     - GPIO_1[7] : 输出 hcsr_ew_trig（EW 方向超声波 TRIG）
//     - GPIO_1[8] : 输入 hcsr_ns_echo（NS 方向超声波 ECHO）
//     - GPIO_1[9] : 输入 hcsr_ew_echo（EW 方向超声波 ECHO）
//
//   input  [2:0] light_ns : 南北向灯色状态，约定 {R,Y,G}
//   input  [2:0] light_ew : 东西向灯色状态，约定 {R,Y,G}
//   input        hcsr_ns_trig : NS 路超声波 TRIG 输出
//   input        hcsr_ew_trig : EW 路超声波 TRIG 输出
//   output       hcsr_ns_echo : NS 路超声波 ECHO 输入
//   output       hcsr_ew_echo : EW 路超声波 ECHO 输入
//
//======================================================================

module gpio_io_pack(
    inout  [9:0] GPIO_1,         

    input  wire [2:0] light_ns,   // 南北向红绿灯状态，约定 {R,Y,G}
    input  wire [2:0] light_ew,   // 东西向红绿灯状态，约定 {R,Y,G}

    input  wire       hcsr_ns_trig,// NS 方向 HC-SR04：TRIG 输出
    input  wire       hcsr_ew_trig,// EW 方向 HC-SR04：TRIG 输出
    output wire       hcsr_ns_echo,// NS 方向 HC-SR04：ECHO 输入
    output wire       hcsr_ew_echo // EW 方向 HC-SR04：ECHO 输入
);

    //==================================================
    // 1) 交通灯信号映射到 GPIO 输出
    //==================================================
    assign GPIO_1[0] = light_ns[2]; // GPIO_1[0] -> NS_R（南北向红灯）
    assign GPIO_1[1] = light_ns[0]; // GPIO_1[1] -> NS_G（南北向绿灯）
    assign GPIO_1[2] = light_ns[1]; // GPIO_1[2] -> NS_Y（南北向黄灯）

    assign GPIO_1[3] = light_ew[2]; // GPIO_1[3] -> EW_R（东西向红灯）
    assign GPIO_1[4] = light_ew[0]; // GPIO_1[4] -> EW_G（东西向绿灯）
    assign GPIO_1[5] = light_ew[1]; // GPIO_1[5] -> EW_Y（东西向黄灯）

    //==================================================
    // 2) HC-SR04 TRIG 输出映射到 GPIO
    //==================================================
    assign GPIO_1[6] = hcsr_ns_trig; // GPIO_1[6] -> NS 超声波 TRIG
    assign GPIO_1[7] = hcsr_ew_trig; // GPIO_1[7] -> EW 超声波 TRIG

    //==================================================
    // 3) HC-SR04 ECHO 从 GPIO 输入读取
    //==================================================
    assign hcsr_ns_echo = GPIO_1[8]; // GPIO_1[8] -> NS 超声波 ECHO
    assign hcsr_ew_echo = GPIO_1[9]; // GPIO_1[9] -> EW 超声波 ECHO

endmodule
