# ALINX AX7Z020B TM1638 (LED&KEY module)

The board wrapper drives an external **TM1638 LED&KEY** module (8 digits, 8 LEDs and
8 buttons) from the PL, for the labs that use a seven-segment display and the module's
buttons.

## Wiring

The module has five pins — `VCC`, `GND`, `STB`, `CLK`, `DIO`. Connect it to the **J20
40-pin expansion port** (0.1-inch pitch) on the carrier board:

| TM1638 pin | J20 pin | FPGA pin | Notes |
| --- | --- | --- | --- |
| `VCC` | 39 or 40 (`+3.3 V`) | — | power the module from 3.3 V, not 5 V |
| `GND` | 1, 37 or 38 (`GND`) | — | |
| `STB` | 35 | V15 | `tm_stb` |
| `CLK` | 36 | W15 | `tm_clk` |
| `DIO` | 33 | U20 | `tm_dio` (bidirectional) |

The module must be powered from **+3.3 V** (J20 pins 39/40), not +5 V, so its `DIO`
line stays within the FPGA's 3.3 V I/O limit — otherwise a level shifter is required.

## Use

1. Connect the TM1638 module to the J20 expansion port as above and connect the
   board's JTAG programmer.
2. Open a seven-segment lab, for example `labs/1_basics/1_05_7seven_segment_letter`.
3. Run `./06_choose_another_fpga_board.bash` and select `alinx_ax7z020b_tm1638`.
4. Run `./03_synthesize_for_fpga.bash`, then `./04_configure_fpga.bash`.

## Implementation

The lab reads the module's eight buttons through `tm1638_board_controller` (in
`peripherals/tm1638_board.sv`) and writes its `abcdefgh`/`digit`/`led` outputs to the
module. The lab's segment order `abcdefgh` is reversed into the controller's `hgfedcba`
order. The four on-board buttons and LEDs are still connected, but when the TM1638
controller is instantiated the lab is driven by the module's eight buttons and LEDs
(following the `a7_lite_35t` board's pattern).
