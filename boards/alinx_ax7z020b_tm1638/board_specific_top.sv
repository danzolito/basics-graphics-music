`include "config.svh"
`include "lab_specific_board_config.svh"
`include "swap_bits.svh"

module board_specific_top
(
    input  wire       sys_clk,
    input  wire [3:0] key,
    output wire [3:0] led,

    // TM1638 LED&KEY module, connected to the J1 board connector:
    //   tm_stb -> STB, tm_clk -> CLK, tm_dio -> DIO
    output wire       tm_stb,
    output wire       tm_clk,
    inout  wire       tm_dio
);

    // The AX7Z020B PL oscillator runs at 50 MHz.
    localparam int CLK_MHZ = 50;

    localparam int W_KEY = 4;
    localparam int W_LED = 4;

    localparam int W_TM_KEY   = 8;
    localparam int W_TM_LED   = 8;
    localparam int W_TM_DIGIT = 8;

    //------------------------------------------------------------------------
    // Clock and reset
    //------------------------------------------------------------------------

    // Reset only on power-up. The AX7Z020B has no dedicated reset input and no
    // switches, so all four buttons stay available as lab inputs.
    wire rst_on_power_up;

    imitate_reset_on_power_up i_reset_on_power_up
    (
        .clk (sys_clk),
        .rst (rst_on_power_up)
    );

    wire clk = sys_clk;
    wire rst = rst_on_power_up;

    //------------------------------------------------------------------------
    // Slow clock used by some educational labs
    //------------------------------------------------------------------------

    wire slow_clk;

    slow_clk_gen
    #(
        .fast_clk_mhz (CLK_MHZ),
        .slow_clk_hz  (1)
    )
    i_slow_clk_gen
    (
        .clk      (clk),
        .rst      (rst),
        .slow_clk (slow_clk)
    );

    //------------------------------------------------------------------------
    // Keys, switches, LEDs and seven-segment display
    //------------------------------------------------------------------------

    // When the TM1638 module is present, the lab reads its eight keys and
    // drives its eight LEDs and eight digits through it.
    `ifdef INSTANTIATE_TM1638_BOARD_CONTROLLER_MODULE
        localparam int W_LAB_KEY   = W_TM_KEY;
        localparam int W_LAB_LED   = W_TM_LED;
        localparam int W_LAB_DIGIT = W_TM_DIGIT;
    `else
        localparam int W_LAB_KEY   = W_KEY;
        localparam int W_LAB_LED   = W_LED;
        localparam int W_LAB_DIGIT = 1;
    `endif

    wire [W_TM_KEY   - 1:0] tm_key;
    wire [W_TM_LED   - 1:0] tm_led;
    wire [W_TM_DIGIT - 1:0] tm_digit;

    logic [W_LAB_KEY   - 1:0] lab_key;
    wire  [W_LAB_LED   - 1:0] lab_led;
    wire  [W_LAB_DIGIT - 1:0] lab_digit;

    wire [7:0] abcdefgh;
    wire [0:0] gpio_unused;

    `ifdef INSTANTIATE_TM1638_BOARD_CONTROLLER_MODULE
        assign tm_led   = lab_led;
        assign tm_digit = lab_digit;
        assign lab_key  = tm_key;

        // The four board LEDs mirror the first four TM1638 LEDs.
        assign led      = W_LED' (~ lab_led);
    `else
        // The buttons are active-low; lab_top expects active-high keys/switches.
        assign lab_key  = ~ key;

        // The LEDs are active-low; lab_top drives active-high, so invert.
        assign led      = ~ lab_led;
    `endif

    //------------------------------------------------------------------------
    // Selected educational lab
    //------------------------------------------------------------------------

    lab_top
    #(
        .clk_mhz       (CLK_MHZ),
        .w_key         (W_LAB_KEY),
        .w_sw          (W_LAB_KEY),
        .w_led         (W_LAB_LED),
        .w_digit       (W_LAB_DIGIT),
        .w_gpio        (1)
    )
    i_lab_top
    (
        .clk      (clk),
        .slow_clk (slow_clk),
        .rst      (rst),

        .key      (lab_key),
        .sw       (lab_key),

        .led      (lab_led),

        .abcdefgh (abcdefgh),
        .digit    (lab_digit),

        // Graphics are not connected on this board.
        .x        ('0),
        .y        ('0),
        .red      (),
        .green    (),
        .blue     (),

        // Audio is not connected.
        .mic      (24'd0),
        .sound    (),

        // An idle UART input is logic 1.
        .uart_rx  (1'b1),
        .uart_tx  (),

        .gpio     (gpio_unused)
    );

    //------------------------------------------------------------------------
    // TM1638 LED&KEY board controller
    //------------------------------------------------------------------------

    // The controller wants the segments in hgfedcba order; the lab outputs
    // abcdefgh, so the eight bits are reversed.
    wire [$left(abcdefgh):0] hgfedcba;
    `SWAP_BITS (hgfedcba, abcdefgh);

    `ifdef INSTANTIATE_TM1638_BOARD_CONTROLLER_MODULE
        tm1638_board_controller
        #(
            .clk_mhz (CLK_MHZ),
            .w_digit (W_TM_DIGIT)
        )
        i_tm1638
        (
            .clk      (clk),
            .rst      (rst),
            .hgfedcba (hgfedcba),
            .digit    (tm_digit),
            .ledr     (tm_led),
            .keys     (tm_key),
            .sio_data (tm_dio),
            .sio_clk  (tm_clk),
            .sio_stb  (tm_stb)
        );
    `else
        // No TM1638 controller: hold the module in its idle state. tm_dio is
        // left as an un-driven input.
        assign tm_stb = 1'b1;
        assign tm_clk = 1'b0;
    `endif

endmodule
