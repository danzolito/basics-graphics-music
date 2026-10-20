# ALINX AX7Z020B HDMI + TM1638 (LED&KEY module)

The board wrapper drives the **HDMI** connector (DVI-compatible video, 640×480) and an
external **TM1638 LED&KEY** module at the same time, for the labs that display graphics
and are controlled by the module's buttons (for example
`labs/2_graphics/2_11_mandelbrot_set`).

## Wiring

The TM1638 module has five pins — `VCC`, `GND`, `STB`, `CLK`, `DIO`. Connect it to the
**J20 40-pin expansion port** (0.1-inch pitch) on the carrier board:

| TM1638 pin | J20 pin | FPGA pin | Signal |
| --- | --- | --- | --- |
| `VCC` | 39 or 40 (`+3.3 V`) | — | power the module from 3.3 V, not 5 V |
| `GND` | 1, 37 or 38 (`GND`) | — | |
| `STB` | 35 | V15 | `tm_stb` |
| `CLK` | 36 | W15 | `tm_clk` |
| `DIO` | 33 | U20 | `tm_dio` (bidirectional) |

The module must be powered from **+3.3 V** (J20 pins 39/40), not +5 V, so its `DIO`
line stays within the FPGA's 3.3 V I/O limit — otherwise a level shifter is required.

| HDMI signal | FPGA positive pin |
| --- | --- |
| Clock | U13 |
| Data 0: blue and sync | W14 |
| Data 1: green | Y18 |
| Data 2: red | Y16 |

Pin `V16` (`hdmi_oen`) enables the connector's +5 V supply and is active high.

## Use

1. Connect the monitor to the HDMI connector, connect the TM1638 module to J20 as
   above, and connect the board's JTAG programmer.
2. Open a lab, for example `labs/2_graphics/2_11_mandelbrot_set`.
3. Run `./06_choose_another_fpga_board.bash` and select `alinx_ax7z020b_hdmi_tm1638`.
4. Run `./03_synthesize_for_fpga.bash`, then `./04_configure_fpga.bash`.

## Implementation

The HDMI transmitter (`ax7z020b_hdmi.sv`) derives a 50 MHz lab clock, a 25 MHz pixel
clock and a 125 MHz serializer clock from the 50 MHz board oscillator and drives the
TMDS lanes. The lab runs on the 50 MHz lab clock.

The lab reads the module's eight buttons through `tm1638_board_controller`
(`peripherals/tm1638_board.sv`) and drives the module's LEDs and digits. The four
on-board buttons mirror the first four module keys, and the four on-board LEDs mirror
the first four module LEDs. The lab's segment order `abcdefgh` is reversed into the
controller's `hgfedcba` order.

Video mode: 640×480, 8 bits per color, 25 MHz pixel clock, negative h/v sync. There is
no EDID negotiation, hot-plug detection, HDMI audio, or HDCP support.
