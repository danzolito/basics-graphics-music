`include "config.svh"
`include "lab_specific_board_config.svh"

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
    output wire       hdmi_oen
);

    // The AX7Z020B PL oscillator runs at 50 MHz.
    localparam int CLK_MHZ = 50;

    localparam int W_KEY    = 4;
    localparam int W_LED    = 4;

    localparam int SCREEN_WIDTH  = 640;
    localparam int SCREEN_HEIGHT = 480;
    localparam int W_RED   = 8;
    localparam int W_GREEN = 8;
    localparam int W_BLUE  = 8;

    //------------------------------------------------------------------------
    // Buttons, LEDs and reset
    //------------------------------------------------------------------------

    // The buttons are active-low; lab_top expects active-high keys/switches.
    wire [W_KEY - 1:0] lab_key = ~ key;

    // The LEDs are active-low; lab_top drives active-high, so invert.
    wire [W_LED - 1:0] lab_led;
    assign led = ~ lab_led;

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
    // Selected educational lab
    //------------------------------------------------------------------------

    wire [7:0] abcdefgh;
    wire [0:0] digit;
    wire [0:0] gpio_unused;

    lab_top
    #(
        .clk_mhz       (CLK_MHZ),
        .w_key         (W_KEY),
        .w_sw          (W_KEY),
        .w_led         (W_LED),
        .w_digit       (1),
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

        // The four buttons act as both keys and switches.
        .key      (lab_key),
        .sw       (lab_key),

        .led      (lab_led),

        .abcdefgh (abcdefgh),
        .digit    (digit),

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

endmodule
