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

    logic [clk_div_cnt_w-1:0] clk_div_counter_ff;
    logic                     clk_slow;
    logic                     clk_slow_global;
    logic [(4*w_digit)-1:0]   slow_counter_ff;

    // Clock divider counter
    always_ff @(posedge clk or posedge rst)
        if (rst)
            clk_div_counter_ff <= '0;
        else
            clk_div_counter_ff <= clk_div_counter_ff + 1;

    // "Slow clock" is taken from divider counter MSB
    assign clk_slow = clk_div_counter_ff[clk_div_cnt_w-1];

    // Route slow clock to global clock tree
    // Only for Altera. Comment out this line if you use Xilinx/GoWin or simulator.
    global i_slow_clk_global (.in(clk_slow), .out(clk_slow_global));

    // Uncomment this line if you use Xilinx/GoWin or simulator.
    // assign clk_slow_global = clk_slow;

    // "Slow counter" FF
    always_ff @(posedge clk_slow_global or posedge rst)
        if (rst)
            slow_counter_ff <= '0;
        else
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
