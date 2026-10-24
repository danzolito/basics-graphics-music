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

    // assign led        = '0;
    // assign abcdefgh   = '0;
    // assign digit      = '0;
       assign red        = '0;
       assign green      = '0;
       assign blue       = '0;
       assign sound      = '0;
       assign uart_tx    = '1;

    //------------------------------------------------------------------------

    wire enable;
    wire fsm_in, moore_fsm_out, mealy_fsm_out;

    // Generate a strobe signal 3 times a second

    strobe_gen
    # (.clk_mhz (clk_mhz), .strobe_hz (3))
    i_strobe_gen
    (.strobe (enable), .*);

    shift_reg # (.depth (w_led)) i_shift_reg
    (
        .en      (   enable ),
        .seq_in  ( | key    ),
        .seq_out (   fsm_in ),
        .par_out (   led    ),
        .*
    );

    my_moore_fsm i_moore_fsm
        (.en (enable), .a (fsm_in), .y (moore_fsm_out), .*);

    my_mealy_fsm i_mealy_fsm
        (.en (enable), .a (fsm_in), .y (mealy_fsm_out), .*);

    //------------------------------------------------------------------------

    //   --a--
    //  |     |
    //  f     b
    //  |     |
    //   --g--
    //  |     |
    //  e     c
    //  |     |
    //   --d--  h

    always_comb
    begin
        case ({ mealy_fsm_out, moore_fsm_out })
        2'b00: abcdefgh = 8'b0000_0000;
        2'b01: abcdefgh = 8'b1100_0110;  // Moore only
        2'b10: abcdefgh = 8'b0011_1010;  // Mealy only
        2'b11: abcdefgh = 8'b1111_1110;
        endcase

        digit = w_digit' (1);
    end

    // Exercise: Implement FSM for recognizing other sequence,
    // for example 10110

endmodule

module my_moore_fsm
(
    input  clk,
    input  rst,
    input  en,
    input  a,
    output y
);

    typedef enum bit [2:0]
    {
        S0 = 3'd0,
        S1 = 3'd1,
        S2 = 3'd2,
        S3 = 3'd3,
        S4 = 3'd4,
        S5 = 3'd5
    }
    state_e;

    state_e state, next_state;

    // State register

    always_ff @ (posedge clk or posedge rst)
        if (rst)
            state <= S0;
        else if (en)
            state <= next_state;

    // Next state logic

    always_comb
    begin
        next_state = state;

        case (state)
        S0: if (  a) next_state = S1;
        S1: if (~  a) next_state = S2;
        S2: if (a)
                    next_state = S3;
                else
                    next_state = S0;

        S3: if (a)
                    next_state = S4;
                else
                    next_state = S2;

        S4: if (~  a) 
                    next_state = S5;
                else
                    next_state = S1;

        S5: if (a)
                    next_state = S3;
                else
                    next_state = S0;

        endcase
    end

    // Output logic based on current state

    assign y = (state == S5);

endmodule

// Asynchronous reset here is needed for some FPGA boards we use

`include "config.svh"

module my_mealy_fsm
(
    input  clk,
    input  rst,
    input  en,
    input  a,
    output y
);

    typedef enum bit [2:0]
    {
        S0 = 3'd0,
        S1 = 3'd1,
        S2 = 3'd2,
        S3 = 3'd3,
        S4 = 3'd4
    }
    state_e;

    state_e state, next_state;

    // State register

    always_ff @ (posedge clk or posedge rst)
        if (rst)
            state <= S0;
        else if (en)
            state <= next_state;

    // Next state logic

    always_comb
    begin
        next_state = state;

        case (state)
        S0: if (  a) next_state = S1;
        S1: if (~  a) next_state = S2;
        S2: if (a)
                    next_state = S3;
                else
                    next_state = S0;

        S3: if (a)
                    next_state = S4;
                else
                    next_state = S2;

        S4: if ( a)
                    next_state = S1;
                else
                    next_state = S2;

        // S4: if (~  a) 
        //             next_state = S5;
        //         else
        //             next_state = S1;

        // S5: if (a)
        //             next_state = S3;
        //         else
        //             next_state = S0;

        endcase
    end

    // Output logic based on current state and inputs

    assign y = (~a & state == S4);

endmodule
