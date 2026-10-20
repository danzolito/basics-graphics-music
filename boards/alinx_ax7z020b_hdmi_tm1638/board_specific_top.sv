`include "config.svh"
`include "lab_specific_board_config.svh"
`include "swap_bits.svh"

// The AX7Z020B has no microphone or audio output, and these interfaces are not
// used by the graphics labs, so drop them rather than wiring non-existent pins.
`ifdef INSTANTIATE_MICROPHONE_INTERFACE_MODULE
`undef INSTANTIATE_MICROPHONE_INTERFACE_MODULE
`endif

`ifdef INSTANTIATE_SOUND_OUTPUT_INTERFACE_MODULE
`undef INSTANTIATE_SOUND_OUTPUT_INTERFACE_MODULE
`endif

module board_specific_top
(
    input  wire       sys_clk,
    input  wire [3:0] key,
    output wire [3:0] led,

    // HDMI (DVI-compatible) output, driven directly by the PL.
    output wire       TMDS_clk_p,
    output wire       TMDS_clk_n,
    output wire [2:0] TMDS_data_p,
    output wire [2:0] TMDS_data_n,
    output wire       hdmi_oen,

    // TM1638 LED&KEY module, connected to the J20 expansion port:
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

    localparam int SCREEN_WIDTH  = 640;
    localparam int SCREEN_HEIGHT = 480;
    localparam int W_RED   = 8;
    localparam int W_GREEN = 8;
    localparam int W_BLUE  = 8;

    //------------------------------------------------------------------------
    // Reset
    //------------------------------------------------------------------------

    // Reset only on power-up. The AX7Z020B has no dedicated reset input and no
    // switches, so all four buttons stay available as lab inputs.
    wire rst_on_power_up;

    imitate_reset_on_power_up i_reset_on_power_up
    (
        .clk (sys_clk),
        .rst (rst_on_power_up)
    );

    //------------------------------------------------------------------------
    // HDMI graphics interface
    //------------------------------------------------------------------------

    // The HDMI transmitter derives a 50 MHz lab clock, a 25 MHz pixel clock and
    // a 125 MHz serializer clock from the 50 MHz board clock, and returns a lab
    // reset released synchronously with the lab clock.
    wire clk;
    wire rst;

    wire [9:0] x;
    wire [8:0] y;

    wire [W_RED   - 1:0] red;
    wire [W_GREEN - 1:0] green;
    wire [W_BLUE  - 1:0] blue;

    ax7z020b_hdmi i_hdmi
    (
        .clk_in      (sys_clk),
        .rst_in      (rst_on_power_up),
        .clk         (clk),
        .rst         (rst),
        .x           (x),
        .y           (y),
        .red         (red),
        .green       (green),
        .blue        (blue),
        .tmds_clk_p  (TMDS_clk_p),
        .tmds_clk_n  (TMDS_clk_n),
        .tmds_data_p (TMDS_data_p),
        .tmds_data_n (TMDS_data_n),
        .hdmi_enable (hdmi_oen)
    );

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

    wire [W_TM_KEY   - 1:0] tm_key;
    wire [W_TM_LED   - 1:0] tm_led;
    wire [W_TM_DIGIT - 1:0] tm_digit;

    wire  [W_TM_LED   - 1:0] lab_led;
    wire  [W_TM_DIGIT - 1:0] lab_digit;

    // The lab reads the eight TM1638 module keys. The four on-board buttons
    // (active-low) mirror the first four of them, so either can be used.
    wire [W_TM_KEY - 1:0] lab_key = tm_key | {{(W_TM_KEY - W_KEY) {1'b0}}, ~ key};

    assign tm_led   = lab_led;
    assign tm_digit = lab_digit;

    // The four board LEDs mirror the first four TM1638 LEDs.
    assign led = W_LED' (~ lab_led);

    wire [7:0] abcdefgh;
    wire [0:0] gpio_unused;

    //------------------------------------------------------------------------
    // Selected educational lab
    //------------------------------------------------------------------------

    lab_top
    #(
        .clk_mhz       (CLK_MHZ),
        .w_key         (W_TM_KEY),
        .w_sw          (W_TM_KEY),
        .w_led         (W_TM_LED),
        .w_digit       (W_TM_DIGIT),
        .w_gpio        (1),

        .screen_width  (SCREEN_WIDTH),
        .screen_height (SCREEN_HEIGHT),

        .w_red         (W_RED),
        .w_green       (W_GREEN),
        .w_blue        (W_BLUE)
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

        .x        (x),
        .y        (y),

        .red      (red),
        .green    (green),
        .blue     (blue),

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

endmodule
