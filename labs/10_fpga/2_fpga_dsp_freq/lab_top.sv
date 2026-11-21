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

    // Change multiplication operands width here

    localparam operand_w = 8;


    // Some counters to generate multiplication operands
    logic [operand_w-1:0] operand_a;
    logic [operand_w-1:0] operand_b;

    always_ff @( posedge clk or posedge rst  ) begin
        if (rst) begin
            operand_a <= '0;
            operand_b <= '0;
        end
        else begin
            operand_a <= operand_a + 1;
            operand_b <= operand_b - 1;
        end
    end

    // Use "multstyle" attribute to select either DSP or LUT multiplication

    (* multstyle = "dsp" *) logic [(operand_w*2)-1:0] mult_result;
    //(* multstyle = "logic" *) logic [(operand_w*2)-1:0] mult_result;

    assign mult_result = operand_a * operand_b;


    logic [(operand_w*2)-1:0] mult_result_reg;

    always_ff @( posedge clk or posedge rst  ) begin
        if (rst)
            mult_result_reg <= '0;
        else
            mult_result_reg <= mult_result;
    end


    //------------------------------------------------------------------------

    // 4 bits per hexadecimal digit
    localparam w_display_number = w_digit * 4;

    logic [w_display_number-1:0] mult_16msb;

    assign mult_16msb = (2*operand_w > w_display_number) ? (mult_result_reg >> (operand_w*2 - w_display_number))
                                                         : mult_result_reg;

    seven_segment_display # (w_digit) i_7segment
    (
        .clk      ( clk                                 ),
        .rst      ( rst                                 ),
        .number   ( mult_16msb                          ),
        .dots     ( w_digit' (0)                        ),
        .abcdefgh ( abcdefgh                            ),
        .digit    ( digit                               )
    );

endmodule
