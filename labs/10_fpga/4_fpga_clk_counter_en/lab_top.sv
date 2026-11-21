`include "config.svh"

module lab_top
# (
    parameter  clk_mhz       = 50,
               w_key         = 4,
               w_sw          = 8,
               w_led         = 8,
               w_digit       = 8,
               w_gpio        = 100,

               screen_width  = 640,
               screen_height = 480,

               w_red         = 4,
               w_green       = 4,
               w_blue        = 4,

               w_x           = $clog2 ( screen_width  ),
               w_y           = $clog2 ( screen_height )
)
(
    input                        clk,
    input                        slow_clk,
    input                        rst,

    // Keys, switches, LEDs

    input        [w_key   - 1:0] key,
    input        [w_sw    - 1:0] sw,
    output logic [w_led   - 1:0] led,

    // A dynamic seven-segment display

    output logic [          7:0] abcdefgh,
    output logic [w_digit - 1:0] digit,

    // Graphics

    input        [w_x     - 1:0] x,
    input        [w_y     - 1:0] y,

    output logic [w_red   - 1:0] red,
    output logic [w_green - 1:0] green,
    output logic [w_blue  - 1:0] blue,

    // Microphone, sound output and UART

    input        [         23:0] mic,
    output       [         15:0] sound,

    input                        uart_rx,
    output                       uart_tx,

    // General-purpose Input/Output

    inout        [w_gpio  - 1:0] gpio
);

    //------------------------------------------------------------------------

       assign led        = '0;
    // assign abcdefgh   = '0;
    // assign digit      = '0;
       assign red        = '0;
       assign green      = '0;
       assign blue       = '0;
       assign sound      = '0;
       assign uart_tx    = '1;

    //------------------------------------------------------------------------

    localparam clk_div_cnt_w = 24;

    logic [clk_div_cnt_w-1:0] clkgate_counter_ff;
    logic [(4*w_digit)-1:0]   slow_counter_ff;
    logic                     slow_counter_en;

    // Clock divider counter
    always_ff @(posedge clk or posedge rst)
        if (rst)
            clkgate_counter_ff <= '0;
        else
            clkgate_counter_ff <= clkgate_counter_ff + 1;


    // "Slow counter" enable is active then all
    // cycle counter FF bits are "1"
    assign slow_counter_en = &clkgate_counter_ff;

    // "Slow counter" FF
    always_ff @(posedge clk or posedge rst)
        if (rst)
            slow_counter_ff <= '0;
        else if (slow_counter_en)
            slow_counter_ff <= slow_counter_ff + 1;

    //------------------------------------------------------------------------

    // 4 bits per hexadecimal digit
    localparam w_display_number = w_digit * 4;

    seven_segment_display # (w_digit) i_7segment
    (
        .clk      ( clk                                 ),
        .rst      ( rst                                 ),
        .number   ( w_display_number' (slow_counter_ff) ),
        .dots     ( w_digit' (0)                        ),
        .abcdefgh ( abcdefgh                            ),
        .digit    ( digit                               )
    );

endmodule
