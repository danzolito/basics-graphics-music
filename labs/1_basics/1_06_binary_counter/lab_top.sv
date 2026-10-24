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

       assign abcdefgh   = '0;
       assign digit      = '0;
       assign red        = '0;
       assign green      = '0;
       assign blue       = '0;
       assign sound      = '0;
       assign uart_tx    = '1;

    //------------------------------------------------------------------------

    // Exercise 1: Free running counter.
    // How do you change the speed of LED blinking?
    // Try different bit slices to display.

    // localparam w_cnt = $clog2 (clk_mhz * 1000 * 1000 * 64);

    // logic [w_cnt - 1:0] cnt;

    // always_ff @ (posedge clk or posedge rst)
    //     if (rst)
    //         cnt <= '0;
    //     else
    //         cnt <= cnt + 1'd1;

    // assign led = cnt [$left (cnt) - 4 -: w_led];

    // Exercise 2: Key-controlled counter.
    // Comment out the code above.
    // Uncomment and synthesize the code below.
    // Press the key to see the counter incrementing.
    //
    // Change the design, for example:
    //
    // 1. One key is used to increment, another to decrement.
    //
    // 2. Two counters controlled by different keys
    // displayed in different groups of LEDs.

    

    // wire any_key = | key;

    logic [w_key-1:0] key_r;

    always_ff @ (posedge clk or posedge rst)
        if (rst)
            key_r <= '0;
        else
            key_r <= key;

    wire [w_key-1:0] key_pressed = ~ key & key_r;

    logic [w_led/2 - 1:0] cnt_1;
    logic [w_led/2 - 1:0] cnt_2;

    always_ff @ (posedge clk or posedge rst)
        if (rst) begin
            cnt_1 <= '0;
            cnt_2 <= '0;
        end
        else begin
            if (key_pressed[0])
                cnt_1 <= cnt_1 + 1'd1;
            else if (key_pressed[1])
                cnt_1 <= cnt_1 - 1'd1;

            if (key_pressed[2])
                cnt_2 <= cnt_2 + 1'd1;
            else if (key_pressed[3])
                cnt_2 <= cnt_2 - 1'd1;
        end

    assign led = {cnt_2, cnt_1};

endmodule
