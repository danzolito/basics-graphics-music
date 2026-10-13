`include "config.svh"
`include "lab_specific_board_config.svh"

module board_specific_top
(
    input  wire       sys_clk,
    input  wire [3:0] key,
    output wire [3:0] led
);

    // The AX7Z020B PL oscillator runs at 50 MHz.
    localparam int CLK_MHZ = 50;

    localparam int W_KEY    = 4;
    localparam int W_LED    = 4;

    //------------------------------------------------------------------------
    // Clock and reset
    //------------------------------------------------------------------------

    // The buttons are active-low; lab_top expects active-high keys/switches.
    wire [W_KEY - 1:0] lab_key = ~ key;

    // Reset only on power-up. The AX7Z020B has no dedicated reset input and no
    // switches, so all four buttons stay available as lab inputs.
    wire rst_on_power_up;

    imitate_reset_on_power_up i_reset_on_power_up
    (
        .clk (sys_clk),
        .rst (rst_on_power_up)
    );

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
        .clk      (sys_clk),
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
        .clk_mhz (CLK_MHZ),
        .w_key   (W_KEY),
        .w_sw    (W_KEY),
        .w_led   (W_LED),
        .w_digit (1),
        .w_gpio  (1)
    )
    i_lab_top
    (
        .clk      (sys_clk),
        .slow_clk (slow_clk),
        .rst      (rst),

        // The four buttons act as both keys and switches.
        .key      (lab_key),
        .sw       (lab_key),

        .led      (led),

        .abcdefgh (abcdefgh),
        .digit    (digit),

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

endmodule
