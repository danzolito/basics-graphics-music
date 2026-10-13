## Alinx AX7Z020B — Xilinx Zynq-7000 XC7Z020 (package CLG400), PL constraints.
##
## Pin assignments are taken from the official Alinx AX7Z020B_2023.1 examples:
##   course_s1_fpga/01_led/.../constraints/led.xdc        (sys_clk, rst_n, led[3:0])
##   course_s1_fpga/11_linux_base/.../constraints/key.xdc (the four PL buttons)
##
## The AX7Z020B has a 50 MHz PL clock, four active-high PL LEDs and four
## active-low PL buttons. No CFGBVS / CONFIG_VOLTAGE / SPI settings are needed
## because this is a Zynq board and the PL is programmed over JTAG.

# 50 MHz PL system clock
set_property -dict { PACKAGE_PIN U18  IOSTANDARD LVCMOS33 } [get_ports { sys_clk }];
create_clock -period 20.000 -name sys_clk -waveform {0.000 10.000} [get_ports { sys_clk }];

# PL user buttons (active-low)
set_property -dict { PACKAGE_PIN M15  IOSTANDARD LVCMOS33 } [get_ports { key[0] }];
set_property -dict { PACKAGE_PIN M14  IOSTANDARD LVCMOS33 } [get_ports { key[1] }];
set_property -dict { PACKAGE_PIN L17  IOSTANDARD LVCMOS33 } [get_ports { key[2] }];
set_property -dict { PACKAGE_PIN L16  IOSTANDARD LVCMOS33 } [get_ports { key[3] }];

# PL user LEDs (active-high)
set_property -dict { PACKAGE_PIN J14  IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN K14  IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN J18  IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN H18  IOSTANDARD LVCMOS33 } [get_ports { led[3] }];
