## Alinx AX7Z020B TM1638 — Xilinx Zynq-7000 XC7Z020 (package CLG400), PL constraints.
##
## Pin assignments are taken from the official Alinx AX7Z020B_2023.1 examples:
##   course_s1_fpga/01_led/.../constraints/led.xdc        (sys_clk, led[3:0])
##   course_s1_fpga/11_linux_base/.../constraints/key.xdc (the four PL buttons)
##   Hardware/05_manual/AX7Z020B_User_Manual.pdf           (3.17 Expansion Port, J20)
##
## The TM1638 LED&KEY module (VCC, GND, STB, CLK, DIO) is connected to the J20
## 40-pin expansion port (0.1-inch pitch, bank 34): STB/CLK/DIO to three PL I/O,
## VCC to +3.3 V and GND to GND. Power the module from +3.3 V, not +5 V, to keep
## the DIO line within the FPGA's 3.3 V limit. No CFGBVS / CONFIG_VOLTAGE / SPI
## settings are needed because this is a Zynq board and the PL is programmed
## over JTAG.

# 50 MHz PL system clock
set_property -dict { PACKAGE_PIN U18  IOSTANDARD LVCMOS33 } [get_ports { sys_clk }];
create_clock -period 20.000 -name sys_clk -waveform {0.000 10.000} [get_ports { sys_clk }];

# PL user buttons (active-low)
set_property -dict { PACKAGE_PIN M15  IOSTANDARD LVCMOS33 } [get_ports { key[0] }];
set_property -dict { PACKAGE_PIN M14  IOSTANDARD LVCMOS33 } [get_ports { key[1] }];
set_property -dict { PACKAGE_PIN L17  IOSTANDARD LVCMOS33 } [get_ports { key[2] }];
set_property -dict { PACKAGE_PIN L16  IOSTANDARD LVCMOS33 } [get_ports { key[3] }];

# PL user LEDs
set_property -dict { PACKAGE_PIN J14  IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN K14  IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN J18  IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN H18  IOSTANDARD LVCMOS33 } [get_ports { led[3] }];

# TM1638 LED&KEY module, connected to the J20 40-pin expansion port (bank 34):
#   STB -> J20 pin 35 (V15)   CLK -> J20 pin 36 (W15)   DIO -> J20 pin 33 (U20)
#   VCC -> J20 +3.3 V (pin 39/40)   GND -> J20 GND (pin 37/38)
set_property -dict { PACKAGE_PIN V15  IOSTANDARD LVCMOS33 } [get_ports { tm_stb }];
set_property -dict { PACKAGE_PIN W15  IOSTANDARD LVCMOS33 } [get_ports { tm_clk }];
set_property -dict { PACKAGE_PIN U20  IOSTANDARD LVCMOS33 } [get_ports { tm_dio }];
