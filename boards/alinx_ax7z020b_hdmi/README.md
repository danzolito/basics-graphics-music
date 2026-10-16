# ALINX AX7Z020B HDMI output

The board wrapper sends the lab's RGB graphics to the board's **HDMI** connector using
DVI-compatible video signaling. Connect that output to a monitor that accepts 640×480
video.

## Video mode

| Property | Value |
| --- | --- |
| Visible image | 640×480, 8 bits each for red, green, and blue |
| Pixel clock | 25 MHz |
| Total frame | 800×525 pixels, approximately 59.52 Hz |
| Horizontal timing | 640 visible, 16 front porch, 96 sync, 48 back porch |
| Vertical timing | 480 visible, 10 front porch, 2 sync, 33 back porch |
| Sync polarity | Negative horizontal and vertical sync |
| Lab clock | 50 MHz |
| Serializer clock | 125 MHz DDR, 250 Mbit/s per data lane |

This is a fixed video mode, using the repository's existing 25 MHz timing. Changing the
wrapper's screen or clock parameters alone does not select another mode. The nominal
640×480 pixel clock is 25.175 MHz; this implementation runs slightly slower. There is no
EDID negotiation, hot-plug detection, HDMI audio, or HDCP support.

## Use

1. Connect the monitor to the HDMI connector and connect the board's JTAG programmer.
2. Open a graphics lab, for example `labs/2_graphics/2_1_rectangle_ellipse_parabola`.
3. Run `./06_choose_another_fpga_board.bash` and select `alinx_ax7z020b_hdmi`.
4. Run `./03_synthesize_for_fpga.bash` to build the bitstream, then
   `./04_configure_fpga.bash` to program the PL over JTAG.

## Implementation

`ax7z020b_hdmi.sv` derives phase-related lab (50 MHz), pixel (25 MHz), and serializer
(125 MHz) clocks from the board's 50 MHz oscillator with an `MMCME2_BASE`. Reset asserts on
power-up or loss of clock lock and releases through separate synchronizers in the lab and
pixel clock domains.

The common `dvi_sync` and `tmds_encoder` modules in `peripherals/dvi.sv` generate video
timing and TMDS symbols. Colors and sync signals are registered together. Each output lane
uses a master/slave pair of Zynq-7000 `OSERDESE2` primitives to transmit ten bits, least
significant bit first, followed by a `TMDS_33` differential output buffer. The clock lane
uses the same serializer arrangement to maintain alignment with the data lanes.

The lab receives pixel coordinates and supplies RGB values using its existing interface.
Its clock remains 50 MHz; pixels advance at 25 MHz. Lab logic and pixel logic use clocks
from the same MMCM, so Vivado can time their crossings.

| HDMI signal | FPGA positive pin |
| --- | --- |
| Clock | U13 |
| Data 0: blue and sync | W14 |
| Data 1: green | Y18 |
| Data 2: red | Y16 |

Pin `V16` (`hdmi_oen` in the wrapper) enables the connector's +5 V supply. It is **active
high**, despite the "OEN" signal name. It goes high after the pixel reset releases and low
during reset or loss of lock.

Pin assignments follow the official
[ALINX AX7Z020B_2023.1](https://github.com/alinxalinx/AX7Z020B_2023.1) example
`course_s1_fpga/02_hdmi_output_test`. Serializer wiring follows AMD's
[OSERDESE2 primitive documentation](https://docs.amd.com/r/2024.2-English/ug953-vivado-7series-libraries/OSERDESE2).

## Simulation

`tests/hdmi_tb.sv` uses AMD's actual MMCM, serializer, and output-buffer models. It decodes
the transmitted differential signals, checks every active pixel and blanking symbol in a
complete frame, checks clock alignment, then repeats after an asynchronous reset. Its test
pattern encodes the coordinates into RGB to detect swapped channels, incorrect bit order,
and pixel alignment errors.

With Vivado's `settings64.sh` sourced, run these commands from the repository root. Build
products stay in a temporary directory.

```bash
repo="$PWD"
simulation_dir=$(mktemp -d)
cd "$simulation_dir"

xvlog --sv -i "$repo/labs/common" -i "$repo/peripherals" \
    "$repo/boards/alinx_ax7z020b_hdmi/ax7z020b_hdmi.sv" \
    "$repo/peripherals/dvi.sv" \
    "$repo/boards/alinx_ax7z020b_hdmi/tests/hdmi_tb.sv" \
    "$XILINX_VIVADO/data/verilog/src/glbl.v"

xelab -L unisims_ver -L secureip work.hdmi_tb work.glbl \
    -s hdmi_test --debug typical

xsim hdmi_test -runall -onerror quit -onfinish quit
```

A successful run prints two `PASS: frame` messages and `PASS: HDMI reset recovery`.
Simulation does not replace checking the display on a physical board.
