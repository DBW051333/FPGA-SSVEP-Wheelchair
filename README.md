# 脑电识别与轮椅交互 FPGA 源码

本工程集成 SSVEP、注意力、情绪推理、HDMI 交互与轮椅控制接口，目标器件为 GW5AT-LV60PG484AC1/I0（GW5AT-60B），顶层为 fusion_top。

使用 Gowin Designer V1.9.12.03 打开 fusion.gprj。工程配置指定 SystemVerilog 2017，头文件搜索路径为 src。综合和布局布线也可在工程目录执行 gw_sh build.tcl。

src 存放 RTL 与头文件，constraints 存放板级引脚及时钟约束，assets 存放片上存储初始化数据，tools 存放当前硬件和初始化数据的生成工具。

情绪模块使用训练好的定点权重，供硬件推理链路使用。
